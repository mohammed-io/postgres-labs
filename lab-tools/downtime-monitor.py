#!/usr/bin/env python3
"""
Downtime Monitor - Simulates a live app connection to Postgres.
Reports any downtime with millisecond precision.

Usage:
    python lab-tools/downtime-monitor.py "postgres://user:pass@localhost:5432/mydb"
"""
import sys
import time
from datetime import datetime, timedelta

try:
    import psycopg
except ImportError:
    print("Installing psycopg...")
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "psycopg[binary]"], check=True)
    import psycopg

DOWNTIME_THRESHOLD = 1.0
CHECK_INTERVAL = 0.1


class DowntimeMonitor:
    def __init__(self, conn_string, app_name="downtime_monitor"):
        self.conn_string = conn_string
        self.app_name = app_name
        self.downtime_events = []
        self.last_success = None
        self.downtime_start = None
        self.running = True
        self.total_checks = 0
        self.failed_checks = 0

    def check_connection(self):
        """Attempt connection + simple query."""
        try:
            conn = psycopg.connect(self.conn_string)
            conn.execute("SET application_name = %s", (self.app_name,))
            result = conn.execute("SELECT version(), NOW()").fetchone()
            conn.close()
            return True, result[0][:30]
        except Exception as e:
            return False, str(e)[:100]

    def start(self):
        """Start monitoring loop."""
        print(f"\n{'='*60}")
        print(f"🔍 DOWNTIME MONITOR STARTED")
        print(f"{'='*60}")
        print(f"Connection: {self.conn_string[:50]}...")
        print(f"Check interval: {CHECK_INTERVAL}s")
        print(f"Downtime threshold: {DOWNTIME_THRESHOLD}s")
        print(f"Press Ctrl+C to stop and view report\n")

        try:
            while self.running:
                self.total_checks += 1
                success, info = self.check_connection()
                now = datetime.now()

                if success:
                    if self.last_success is None:
                        print(f"[{self._now()}] 🟢 First successful connection")
                        self.last_success = now
                    elif self.downtime_start:
                        # Connection restored
                        duration = now - self.downtime_start
                        self.downtime_events.append({
                            'start': self.downtime_start,
                            'end': now,
                            'duration': duration
                        })
                        print(f"\n[{self._now()}] ✅ CONNECTION RESTORED after {self._fmt_duration(duration)}\n")
                        self.downtime_start = None
                        self.last_success = now
                    else:
                        gap = (now - self.last_success).total_seconds()
                        print(f"[{self._now()}] 🟢 OK (gap: {gap:.1f)s)", end='\r')
                        self.last_success = now
                else:
                    self.failed_checks += 1
                    if self.last_success and self.downtime_start is None:
                        # Downtime started
                        self.downtime_start = now
                        print(f"\n[{self._now()}] 🔴 CONNECTION LOST: {info}\n")
                    elif self.downtime_start:
                        duration = now - self.downtime_start
                        print(f"[{self._now()}] 🔴 Still down... {self._fmt_duration(duration)}", end='\r')

                time.sleep(CHECK_INTERVAL)

        except KeyboardInterrupt:
            self.stop()

    def stop(self):
        """Stop monitoring and report."""
        self.running = False
        print("\n\n" + "="*60)
        self._print_summary()
        print("="*60)

    def _print_summary(self):
        """Print final downtime report."""
        print("📊 DOWNTIME SUMMARY")
        print("="*60)

        if not self.downtime_events:
            print("✅ ZERO DOWNTIME DETECTED!")
        else:
            total_downtime = sum((e['end'] - e['start']) for e in self.downtime_events, timedelta())
            print(f"⚠️  {len(self.downtime_events)} downtime event(s)")
            print(f"⏱️  Total downtime: {self._fmt_duration(total_downtime)}")
            print("\nDowntime events:")
            for i, event in enumerate(self.downtime_events, 1):
                print(f"  {i}. {event['start'].strftime('%H:%M:%S')} → {event['end'].strftime('%H:%M:%S')}")
                print(f"     Duration: {self._fmt_duration(event['duration'])}")

        print(f"\n📈 Statistics:")
        print(f"   Total checks: {self.total_checks}")
        print(f"   Failed checks: {self.failed_checks}")
        if self.total_checks > 0:
            success_rate = (self.total_checks - self.failed_checks) / self.total_checks * 100
            print(f"   Success rate: {success_rate:.2f}%")

        # Return exit code based on downtime
        if self.downtime_events:
            total_downtime = sum((e['end'] - e['start']) for e in self.downtime_events, timedelta())
            if total_downtime.total_seconds() > 5:
                print(f"\n❌ FAIL: Downtime exceeded 5 seconds")
                sys.exit(1)
            else:
                print(f"\n⚠️  WARNING: Downtime detected but under 5 seconds")
                sys.exit(2)
        else:
            print(f"\n✅ PASS: Zero downtime")
            sys.exit(0)

    @staticmethod
    def _now():
        return datetime.now().strftime('%H:%M:%S.%f')[:-3]

    @staticmethod
    def _fmt_duration(td):
        seconds = td.total_seconds()
        if seconds < 60:
            return f"{seconds:.3f}s"
        mins = int(seconds // 60)
        secs = seconds % 60
        return f"{mins}m {secs:05.2f}s"


if __name__ == "__main__":
    conn_string = sys.argv[1] if len(sys.argv) > 1 else "postgres://postgres:postgres@localhost:5432/postgres"
    app_name = sys.argv[2] if len(sys.argv) > 2 else "downtime_monitor"

    monitor = DowntimeMonitor(conn_string, app_name)
    monitor.start()
