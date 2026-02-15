---
name: "PostgreSQL 17 → 18 Upgrade (Zero Downtime)"
category: "07-replication"
difficulty: "advanced"
time: "90 minutes"
concepts: ["version upgrade", "logical replication", "zero downtime", "cutover"]
---

# PostgreSQL 17 → 18 Upgrade (Zero Downtime)

## Scenario

Production database on Postgres 17. Need to upgrade to 18. **Cannot accept downtime.**

## Two Approaches

| Approach | Downtime | Complexity | When to Use |
|----------|----------|------------|-------------|
| **pg_upgrade** | ~30 seconds | Low | Maintenance windows OK |
| **Logical Replication** | Zero | High | 24/7 operations required |

## Your Tasks

1. Understand WAL levels for logical replication
2. Create publication on Postgres 17
3. Create subscription on Postgres 18
4. Monitor replication lag
5. Execute zero-downtime cutover
6. Verify with downtime monitor

## Quick Start

```bash
cd lab
docker-compose up -d

# Terminal 1: Start downtime monitor
python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5433/appdb" &

# Terminal 2: Start traffic simulator
python3 ../../../lab-tools/traffic-simulator.py 10 100 300 &

# Terminal 3: Perform upgrade
# Follow steps...
```

## Key Learning Steps

### Step 1: Enable WAL

```sql
-- On Postgres 17
ALTER SYSTEM SET wal_level = 'logical';
SELECT pg_reload_conf();  -- Won't work, needs restart
```

### Step 2: Create Publication

```sql
-- On Postgres 17
CREATE PUBLICATION upgrade_pub FOR ALL TABLES;
```

### Step 3: Initialize Postgres 18

```sql
-- Copy schema (no data yet)
pg_dump -h pg-17 -U postgres --schema-only appdb | psql -h pg-18 -U postgres appdb
```

### Step 4: Create Subscription

```sql
-- On Postgres 18
CREATE SUBSCRIPTION upgrade_sub
CONNECTION 'host=pg-17 port=5432 user=postgres dbname=appdb'
PUBLICATION upgrade_pub
WITH (copy_data = true);
```

### Step 5: Wait for Catch-up

```sql
-- On Postgres 18, monitor lag
SELECT
    subname,
    EXTRACT(EPOCH FROM (now() - replay_lag))::int AS lag_seconds
FROM pg_stat_subscription;
-- Wait until lag = 0 or 1
```

### Step 6: Cutover

```bash
# Only change app's DATABASE_URL
# No databases stop!
# Downtime should be 0 seconds
```

## Verification

After cutover, check downtime monitor output. Should show:
```
✅ PASS: Zero downtime
```
