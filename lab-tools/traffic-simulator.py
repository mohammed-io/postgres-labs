#!/usr/bin/env python3
"""
Traffic Simulator - Simulates realistic application traffic.

Usage:
    python lab-tools/traffic-simulator.py <write_qps> <read_qps> <duration>
    python lab-tools/traffic-simulator.py 10 100 60  # 10 writes/s, 100 reads/s, 60 seconds
"""
import sys
import time
import random
import threading
from datetime import datetime
from collections import Counter

try:
    import psycopg
except ImportError:
    print("Installing psycopg...")
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "psycopg[binary]"], check=True)
    import psycopg


# Default connection strings
PRIMARY = "postgres://postgres:postgres@localhost:5432/postgres"
REPLICAS = [
    "postgres://postgres:postgres@localhost:5433/postgres",
    "postgres://postgres:postgres@localhost:5434/postgres",
]


class TrafficSimulator:
    def __init__(self, primary_url, replica_urls, write_qps=10, read_qps=100):
        self.primary = primary_url
        self.replicas = replica_urls
        self.write_qps = write_qps
        self.read_qps = read_qps
        self.stop = False
        self.writes_succeeded = 0
        self.writes_failed = 0
        self.reads_succeeded = 0
        self.reads_failed = 0
        self.write_errors = Counter()
        self.read_errors = Counter()
        self.last_stats = time.time()

    def simulate_write(self):
        """INSERT query - must go to primary."""
        try:
            with psycopg.connect(self.primary) as conn:
                conn.execute("""
                    INSERT INTO traffic_metrics (sensor_id, value, created_at)
                    VALUES (%s, %s, NOW())
                    ON CONFLICT (sensor_id) DO UPDATE
                    SET value = EXCLUDED.value, created_at = EXCLUDED.created_at
                """, (random.randint(1, 100), random.random() * 100))
                self.writes_succeeded += 1
                return True
        except Exception as e:
            self.writes_failed += 1
            error_key = str(type(e).__name__)
            self.write_errors[error_key] += 1
            return False

    def simulate_read(self):
        """SELECT query - can go to any replica, fall back to primary."""
        targets = self.replicas + [self.primary]

        for target in targets:
            try:
                with psycopg.connect(target) as conn:
                    conn.execute("""
                        SELECT COUNT(*) FROM traffic_metrics
                        WHERE created_at > NOW() - INTERVAL '1 minute'
                    """).fetchone()
                    self.reads_succeeded += 1
                    return True
            except Exception:
                continue

        self.reads_failed += 1
        return False

    def writer_thread(self):
        """Continuously generate write traffic."""
        while not self.stop:
            start = time.time()
            self.simulate_write()
            sleep_time = max(0, 1.0/self.write_qps - (time.time() - start))
            time.sleep(sleep_time)

    def reader_thread(self):
        """Continuously generate read traffic."""
        while not self.stop:
            start = time.time()
            self.simulate_read()
            sleep_time = max(0, 1.0/self.read_qps - (time.time() - start))
            time.sleep(sleep_time)

    def start(self, duration_seconds=60):
        """Start traffic simulation."""
        print(f"\n{'='*60}")
        print(f"🚀 TRAFFIC SIMULATOR STARTED")
        print(f"{'='*60}")
        print(f"Primary: {self.primary[:40]}...")
        print(f"Replicas: {len(self.replicas)}")
        print(f"Target: {self.write_qps} writes/sec, {self.read_qps} reads/sec")
        print(f"Duration: {duration_seconds}s")
        print(f"Press Ctrl+C to stop early\n")

        # Start threads
        threads = []
        writer_count = max(1, self.write_qps // 5)
        reader_count = max(1, self.read_qps // 10)

        for _ in range(writer_count):
            t = threading.Thread(target=self.writer_thread, daemon=True)
            t.start()
            threads.append(t)

        for _ in range(reader_count):
            t = threading.Thread(target=self.reader_thread, daemon=True)
            t.start()
            threads.append(t)

        # Monitor for specified duration
        start_time = time.time()
        last_writes = 0
        last_reads = 0

        try:
            while time.time() - start_time < duration_seconds:
                time.sleep(1)

                write_rate = self.writes_succeeded - last_writes
                read_rate = self.reads_succeeded - last_reads
                last_writes = self.writes_succeeded
                last_reads = self.reads_succeeded

                elapsed = int(time.time() - start_time)
                remaining = duration_seconds - elapsed
                print(f"[{elapsed:3d}s | {remaining:3d}s left] "
                      f"📝 Writes: {write_rate:3d}/s  |  📖 Reads: {read_rate:4d}/s  |  "
                      f"❌ Write errors: {self.writes_failed}  Read errors: {self.reads_failed}")

        except KeyboardInterrupt:
            print("\n⚠️  Interrupted by user")

        self.stop = True
        time.sleep(0.5)  # Let threads finish
        self._print_summary()

    def _print_summary(self):
        """Print final statistics."""
        print("\n" + "="*60)
        print("📊 TRAFFIC SUMMARY")
        print("="*60)
        print(f"✅ Writes succeeded: {self.writes_succeeded}")
        print(f"❌ Writes failed: {self.writes_failed}")

        if self.write_errors:
            print(f"\nWrite error breakdown:")
            for error, count in self.write_errors.most_common():
                print(f"  {error}: {count}")

        print(f"\n📈 Reads succeeded: {self.reads_succeeded}")
        print(f"❌ Reads failed: {self.reads_failed}")

        if self.read_errors:
            print(f"\nRead error breakdown:")
            for error, count in self.read_errors.most_common():
                print(f"  {error}: {count}")

        total = self.writes_succeeded + self.writes_failed + self.reads_succeeded + self.reads_failed
        if total > 0:
            success_rate = (self.writes_succeeded + self.reads_succeeded) / total * 100
            print(f"\n🎯 Overall success rate: {success_rate:.2f}%")

        avg_write_rate = self.writes_succeeded / max(1, (time.time() - self.last_stats))
        avg_read_rate = self.reads_succeeded / max(1, (time.time() - self.last_stats))
        print(f"📊 Actual rates: ~{avg_write_rate:.1f} writes/s, ~{avg_read_rate:.1f} reads/s")

        print("="*60)

        # Exit code based on error rate
        if total > 0:
            error_rate = (self.writes_failed + self.reads_failed) / total
            if error_rate > 0.1:  # More than 10% errors
                print("\n❌ FAIL: High error rate")
                sys.exit(1)
            elif error_rate > 0.01:  # More than 1% errors
                print("\n⚠️  WARNING: Elevated error rate")
                sys.exit(2)
            else:
                print("\n✅ PASS: Acceptable error rate")
                sys.exit(0)


if __name__ == "__main__":
    write_qps = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    read_qps = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    duration = int(sys.argv[3]) if len(sys.argv) > 3 else 60

    sim = TrafficSimulator(
        primary_url=PRIMARY,
        replica_urls=REPLICAS,
        write_qps=write_qps,
        read_qps=read_qps
    )
    sim.start(duration_seconds=duration)
