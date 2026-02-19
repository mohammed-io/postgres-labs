---
name: "Read Replicas & Failover (Zero Downtime)"
category: "07-replication"
difficulty: "advanced"
time: "90 minutes"
concepts: ["streaming replication", "read replicas", "failover", "promotion"]
---

# Read Replicas & Failover

## Scenario

- Primary: Handles writes
- Need: 2 read replicas for analytics
- Goal: Zero-downtime failover if primary dies

## Architecture

```
          [App]
            |
      +-----+-----+
      |     |     |
   [Primary] [Replica 1]
   writes    reads
      |
      +---> [Replica 2]
            reads
```

## Your Tasks

1. Setup streaming replication (physical)
2. Monitor replication lag
3. Test read queries on replicas
4. Practice failover (promote replica to primary)
5. Use downtime monitor to verify zero downtime

## Quick Start

```bash
cd lab
docker-compose up -d

# Monitor downtime
python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5435/appdb" &

# Simulate traffic
python3 ../../../lab-tools/traffic-simulator.py 10 100 120 &
```

## Key Commands

```sql
-- Primary: Check replication status
SELECT * FROM pg_stat_replication;

-- Replica: Check lag
SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;

-- Failover: Promote replica
docker exec pg-replica-1 pg_ctl promote -D /var/lib/postgresql/data;
```
