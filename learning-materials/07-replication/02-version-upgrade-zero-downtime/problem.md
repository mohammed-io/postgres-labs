---
name: "PostgreSQL 17 → 18 Upgrade (Zero Downtime)"
category: "07-replication"
difficulty: "advanced"
time: "90 minutes"
concepts: ["version upgrade", "logical replication", "zero downtime", "cutover"]
---

# PostgreSQL 17 → 18 Upgrade (Zero Downtime)

## Scenario

Production database is running PostgreSQL 17. You need to upgrade to 18, but you cannot accept any downtime. Users are actively using the application 24/7.

Your job is to perform a zero-downtime upgrade using logical replication.

## Why This Lab Exists

Version upgrades are necessary but risky. Common approaches:

| Approach | Downtime | Complexity | When to Use |
|----------|----------|------------|-------------|
| **pg_upgrade** | ~30 seconds | Low | Maintenance windows OK |
| **Logical Replication** | Zero | High | 24/7 operations required |

Most production databases cannot accept 30 seconds of downtime. This lab teaches the logical replication approach for zero-downtime upgrades.

## Real-World Example

### Production Upgrade Scenarios

**Scenario 1: 24/7 E-commerce Site**
- **Problem:** Daily sales run through at midnight. Cannot stop for upgrade.
- **Solution:** Use logical replication to create standby on PostgreSQL 18, swap connection strings.

**Scenario 2: Financial Systems**
- **Problem:** Regulatory requirements prohibit data loss or downtime.
- **Solution:** Full test environment, staged cutover with data validation.

**Scenario 3: Global Applications**
- **Problem:** Users in multiple time zones, cannot coordinate maintenance.
- **Solution:** Cutover during least active period (e.g., 3 AM local time).

**What this teaches:** Zero-downtime upgrades are possible but require careful planning and testing. They're not "set and forget" - they're complex operations.

## What You Will Build

```
Phase 1: [WAL Configuration] - Enable logical WAL for replication
Phase 2: [Publication Setup] - Create publication on PostgreSQL 17
Phase 3: [Schema Sync] - Copy schema to PostgreSQL 18
Phase 4: [Subscription Setup] - Create subscription on PostgreSQL 18
Phase 5: [Cutover] - Swap connection strings with zero downtime
Phase 6: [Verification] - Verify data integrity and monitor
```

## Quick Start

```bash
cd lab
docker-compose up -d

# Terminal 1: Start downtime monitor
python downtime-monitor.py "postgres://postgres:postgres@localhost:5433/appdb" &

# Terminal 2: Start traffic simulator
python traffic-simulator.py 10 100 300 &

# Terminal 3: Perform upgrade
# Follow steps...
```

## Lab Flow

1. Read `step-01.md`: WAL Configuration - enable logical WAL for replication
2. Read `step-02.md`: Publication Setup - create publication on PostgreSQL 17
3. Read `step-03.md`: Schema Sync - copy schema to PostgreSQL 18
4. Read `step-04.md`: Subscription Setup - create subscription on PostgreSQL 18
5. Read `step-05.md`: Wait for Catch-up - monitor replication lag
6. Read `step-06.md`: Cutover - swap connection strings with zero downtime
7. Run `lab/verify.sql` throughout to validate your understanding
8. Try `lab/break-it.sql` - see what happens with various upgrade scenarios

## Learning Objectives

Perform a zero-downtime PostgreSQL upgrade using logical replication.

## Key Learning Steps

### Step 1: Enable WAL

```sql
-- On PostgreSQL 17
ALTER SYSTEM SET wal_level = 'logical';
SELECT pg_reload_conf();  -- Won't work, needs restart
```

### Step 2: Create Publication

```sql
-- On PostgreSQL 17
CREATE PUBLICATION upgrade_pub FOR ALL TABLES;
```

### Step 3: Initialize PostgreSQL 18

```sql
-- Copy schema (no data yet)
pg_dump -h pg-upgrade-17 -U postgres --schema-only appdb | psql -h pg-upgrade-18 -U postgres appdb
```

### Step 4: Create Subscription

```sql
-- On PostgreSQL 18
CREATE SUBSCRIPTION upgrade_sub
CONNECTION 'host=pg-upgrade-17 port=5432 user=postgres dbname=appdb'
PUBLICATION upgrade_pub
WITH (copy_data = true);
```

### Step 5: Wait for Catch-up

```sql
-- On PostgreSQL 18, monitor lag
SELECT
    subname,
    EXTRACT(EPOCH FROM latest_end_time - last_msg_send_time)::int AS lag_seconds
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

## Real-World Gotchas

| Issue | Symptom | Solution |
|-------|---------|----------|
| Schema changes between setup and cutover | Subscription fails or diverges | Run schema sync just before cutover |
| Long-running transactions | Catch-up takes hours | Decommit old transactions |
| Large datasets | Slow initial sync | Use `copy_data = true` to sync once, then change to `copy_data = false` |
| Data type incompatibilities | Subscription error | Upgrade schema first, test thoroughly |

## Your Tasks

1. Understand WAL levels for logical replication
2. Create publication on PostgreSQL 17
3. Create subscription on PostgreSQL 18
4. Monitor replication lag
5. Execute zero-downtime cutover
6. Verify with downtime monitor
