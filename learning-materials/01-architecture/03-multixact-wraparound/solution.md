# Solution: MultiXact ID Wraparound

## Complete Reference

### Task 1: Observe Multixact Creation

**Understanding the mechanism**:

```sql
-- Enable the pageinspect extension for tuple-level inspection
CREATE EXTENSION IF NOT EXISTS pageinspect;

-- Check current mxid counter
SELECT next_multixact_id::text::bigint AS next_mxid FROM pg_control_checkpoint();
```

**Creating a multixact with two sessions**:

```sql
-- Session 1: Lock a row
BEGIN;
SELECT * FROM inventory WHERE product_id = 1 FOR SHARE;
-- xmax now holds the session's XID

-- Session 2: Lock the SAME row (while Session 1 still holds lock)
BEGIN;
SELECT * FROM inventory WHERE product_id = 1 FOR SHARE;
-- xmax converted to a multixact ID containing [Session1_XID, Session2_XID]
COMMIT;

-- Session 1: Inspect the tuple header
SELECT
    lp,
    t_xmin,
    t_xmax,
    t_infomask,
    CASE WHEN t_infomask & 4096 != 0 THEN 'YES' ELSE 'NO' END AS is_multixact,
    CASE WHEN t_infomask & 1024 != 0 THEN 'YES' ELSE 'NO' END AS is_shared_lock
FROM heap_page_items(get_raw_page('inventory', 0))
WHERE lp = 1;
COMMIT;
```

**Expected output**:
- `t_xmax` will show a small number (the multixact ID)
- `is_multixact` = YES (infomask bit 0x1000 set)
- `is_shared_lock` = YES (infomask bit 0x0400 set)

### Task 2: Monitor MultiXact Age

**Comprehensive monitoring query**:

```sql
SELECT
    datname,
    datminmxid,
    mxid_age(datminmxid) AS mxid_age,
    age(datfrozenxid) AS xid_age,
    ROUND(100.0 * mxid_age(datminmxid) / 2147483648, 6) AS pct_mxid_wrap,
    ROUND(100.0 * age(datfrozenxid) / 2147483648, 6) AS pct_xid_wrap,
    CASE
        WHEN mxid_age(datminmxid) > 1500000000 THEN 'MXID CRITICAL: SHUTDOWN IMMINENT'
        WHEN age(datfrozenxid) > 1500000000 THEN 'XID CRITICAL: SHUTDOWN IMMINENT'
        WHEN mxid_age(datminmxid) > 150000000 THEN 'MXID CRITICAL'
        WHEN age(datfrozenxid) > 1500000000 THEN 'XID CRITICAL'
        WHEN mxid_age(datminmxid) > 100000000 THEN 'MXID WARNING'
        WHEN age(datfrozenxid) > 1000000000 THEN 'XID WARNING'
        ELSE 'OK'
    END AS status
FROM pg_database
ORDER BY greatest(mxid_age(datminmxid), age(datfrozenxid)) DESC;
```

**Per-table multixact age**:

```sql
SELECT
    schemaname,
    relname,
    relminmxid,
    mxid_age(relminmxid) AS mxid_age,
    relfrozenxid,
    age(relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || relname)) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
    AND n.nspname = 'public'
ORDER BY mxid_age(c.relminmxid) DESC;
```

### Task 3: Simulate Rapid Accumulation

**Using break-it.sql Scenario 1** — rapid multixact creation:

```sql
-- Create many multixacts by locking different rows from concurrent sessions
-- The break-it.sql script automates this with DO blocks

-- Before: check baseline
SELECT mxid_age(datminmxid) AS before_age FROM pg_database WHERE datname = 'labdb';

-- Run break-it.sql
-- docker exec pg-multixact psql -U postgres -d labdb -f lab/break-it.sql

-- After: check how much the age grew
SELECT mxid_age(datminmxid) AS after_age FROM pg_database WHERE datname = 'labdb';
```

**Using break-it.sql Scenario 2** — disable autovacuum:

```sql
-- Disable autovacuum so multixacts are never frozen
ALTER TABLE inventory SET (autovacuum_enabled = false);

-- Now every multixact created stays "unfrozen" — age grows unbounded
-- In production, this is how you end up in an emergency

-- Re-enable for cleanup
ALTER TABLE inventory SET (autovacuum_enabled = true);
```

### Task 4: Fix and Prevent

**Step 1: Check current settings**:

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE '%multixact%'
ORDER BY name;
```

**Step 2: Tune autovacuum for multixact freeze**:

```sql
-- Lower the max age to trigger autovacuum earlier
ALTER SYSTEM SET autovacuum_multixact_freeze_max_age = 200000000;
ALTER SYSTEM SET autovacuum_multixact_freeze_table_age = 100000000;
SELECT pg_reload_conf();
```

**Step 3: Run manual freeze on affected tables**:

```sql
-- Freeze specific tables
VACUUM FREEZE inventory;
VACUUM FREEZE order_locks;
VACUUM FREEZE shared_resources;

-- Or freeze everything
VACUUM FREEZE ANALYZE;
```

**Step 4: Verify the freeze worked**:

```sql
SELECT
    datname,
    mxid_age(datminmxid) AS mxid_age_after_freeze,
    age(datfrozenxid) AS xid_age_after_freeze
FROM pg_database
WHERE datname = 'labdb';
-- Both should be much lower now
```

**Step 5: Check pg_multixact directory size**:

```bash
docker exec pg-multixact bash -c "du -sh /var/lib/postgresql/data/pg_multixact/"
# Should be small after freeze + truncation
```

---

## Production Monitoring Setup

### Recommended Cron Job (every 5 minutes)

```sql
-- Save this as a monitoring query and alert on WARNING/CRITICAL status
SELECT
    datname,
    mxid_age(datminmxid) AS mxid_age,
    age(datfrozenxid) AS xid_age,
    CASE
        WHEN mxid_age(datminmxid) > 150000000
            OR age(datfrozenxid) > 1500000000 THEN 'CRITICAL'
        WHEN mxid_age(datminmxid) > 100000000
            OR age(datfrozenxid) > 1000000000 THEN 'WARNING'
        ELSE 'OK'
    END AS wraparound_status
FROM pg_database
ORDER BY greatest(mxid_age(datminmxid), age(datfrozenxid)) DESC;
```

### Prometheus / Grafana Metric

```
pg_database_mxid_age{datname="production"} > 100000000  → Alert
pg_database_mxid_age{datname="production"} > 150000000  → Page
```

---

## Key Takeaways

| Concept | Production Impact |
|---------|-------------------|
| **MultiXact IDs** | Created when multiple transactions lock the same row via FOR SHARE/KEY SHARE |
| **32-bit limit** | Same wraparound problem as XIDs at ~2 billion |
| **Less monitored** | Most teams track XID age but not mxid age — dangerous blind spot |
| **Separate settings** | `autovacuum_multixact_freeze_max_age` is independent from XID freeze settings |
| **pg_multixact/** | Stores member data on disk; grows without freeze; truncates after freeze |
| **Long transactions** | Block multixact freeze just like they block XID freeze |
| **Recovery** | Single-user mode `VACUUM FREEZE` — hours of downtime for large databases |

---

## Troubleshooting Table

| Symptom | Likely Cause | Diagnostic | Fix |
|---------|-------------|------------|-----|
| "database must be vacuumed" warnings in logs | mxid age > 100M | `SELECT mxid_age(datminmxid) FROM pg_database;` | Run `VACUUM FREEZE` on affected tables |
| "database is not accepting commands" | mxid age near 2B | Check `pg_controldata` for next_mxid | Start in single-user mode; run `VACUUM FREEZE` |
| mxid age keeps growing despite autovacuum | Long-running transaction blocking freeze | `SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction';` | Terminate the blocking transaction |
| `pg_multixact/` directory very large | Members not truncated after freeze | `du -sh $PGDATA/pg_multixact/` | Run `VACUUM FREEZE` to allow truncation |
| Autovacuum not triggering for multixacts | `autovacuum_multixact_freeze_max_age` too high | Check `pg_settings` | Lower the setting |
| `ERROR: out of shared memory` | Too many lock objects per transaction | Check `max_locks_per_transaction` | Increase the setting and restart |

---

## Cleanup / Reset Instructions

To re-run this lab from scratch:

```bash
# Stop and remove the container and volume
docker compose down -v

# Start fresh
docker compose up -d

# Wait for healthcheck
docker exec pg-multixact pg_isready -U postgres

# Re-run setup
docker exec pg-multixact psql -U postgres -d labdb -f /docker-entrypoint-initdb.d/01-setup.sql
```
