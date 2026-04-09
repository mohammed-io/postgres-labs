# Step 2: Detecting and Preventing MultiXact Wraparound

## Goal

Learn how to detect multixact wraparound risk, understand the freeze mechanism, and configure monitoring and prevention.

## The Wraparound Problem

MultiXact IDs are 32-bit unsigned integers, just like regular XIDs. This means they wrap around at approximately **2 billion** (2^31 ≈ 2,147,483,648). The same wraparound mechanics apply:

```
mxid: 0 → 1 → 2 → ... → 2,147,483,647 → 0 → 1 → ...

After wraparound, old multixacts appear to be "in the future."
Rows with old multixact locks become unreadable — the database
cannot determine if the lock is still held.
```

### What Happens at Wraparound

| Age (mxid_age) | What Happens |
|-----------------|-------------|
| 0 – 100M | Normal operation |
| 100M – 150M | WARNING in logs: "database must be vacuumed within N multixacts" |
| 150M – 200M | Aggressive autovacuum triggered automatically |
| 200M+ | ERROR: "database is not accepting commands to avoid multixact wraparound" |
| ~2B | Emergency shutdown to prevent data corruption |

**Critical difference from XID wraparound**: The thresholds are similar, but multixact age grows based on *shared-lock events*, not just transactions. A workload with heavy `SELECT FOR SHARE` usage can push mxid age much faster than XID age.

---

## Detection: Monitoring dat_minmxid

PostgreSQL tracks the oldest multixact ID that has not yet been frozen in `pg_database.dat_minmxid` for each database. The `mxid_age()` function computes how far the current mxid counter has advanced past `dat_minmxid`.

### The Essential Monitoring Query

```sql
SELECT
    datname,
    datminmxid,
    mxid_age(datminmxid) AS mxid_age,
    ROUND(100.0 * mxid_age(datminmxid) / 2147483648, 4) AS pct_to_wraparound,
    CASE
        WHEN mxid_age(datminmxid) > 1500000000 THEN 'CRITICAL: IMMINENT SHUTDOWN'
        WHEN mxid_age(datminmxid) > 150000000 THEN 'CRITICAL'
        WHEN mxid_age(datminmxid) > 100000000 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM pg_database
ORDER BY mxid_age(datminmxid) DESC;
```

### Recommended Alerting Thresholds

| Threshold | Action |
|-----------|--------|
| **100M** (warn) | Investigate. Check autovacuum multixact settings. |
| **150M** (critical) | Immediate action. Run `VACUUM FREEZE` on affected tables. |
| **1.5B** (emergency) | Database may stop accepting commands. Emergency freeze required. |

### Always Monitor Both XID and MXID Together

```sql
SELECT
    datname,
    age(datfrozenxid) AS xid_age,
    mxid_age(datminmxid) AS mxid_age,
    CASE
        WHEN age(datfrozenxid) > 1500000000
            OR mxid_age(datminmxid) > 1500000000 THEN 'CRITICAL'
        WHEN age(datfrozenxid) > 1000000000
            OR mxid_age(datminmxid) > 100000000 THEN 'WARNING'
        ELSE 'OK'
    END AS wraparound_status
FROM pg_database
ORDER BY greatest(age(datfrozenxid), mxid_age(datminmxid)) DESC;
```

---

## Prevention: Autovacuum MultiXact Settings

PostgreSQL has separate autovacuum knobs for multixact freezing. These are **independent** from the regular XID freeze settings:

| Setting | Default | Controls |
|---------|---------|----------|
| `autovacuum_multixact_freeze_max_age` | 400,000,000 | Max mxid age before autovacuum triggers freeze |
| `autovacuum_multixact_freeze_table_age` | 150,000,000 | Table-level mxid age that triggers VACUUM FREEZE |
| `vacuum_multixact_freeze_min_age` | 5,000,000 | mxid age at which individual tuples are frozen |

**Key point**: The default `autovacuum_multixact_freeze_max_age` is 400M — much higher than the 200M warning threshold. If your workload creates multixacts rapidly, consider lowering it:

```sql
-- Lower to trigger autovacuum freeze earlier
ALTER SYSTEM SET autovacuum_multixact_freeze_max_age = 200000000;
ALTER SYSTEM SET autovacuum_multixact_freeze_table_age = 100000000;
SELECT pg_reload_conf();
```

### Per-Table Settings

You can also set multixact freeze age per table, which is useful for tables with heavy shared locking:

```sql
ALTER TABLE inventory SET (
    autovacuum_multixact_freeze_min_age = 1000000,
    autovacuum_multixact_freeze_max_age = 100000000
);
```

---

## The Freeze Mechanism

When autovacuum (or manual `VACUUM FREEZE`) processes a table, it replaces old multixact IDs with a special "frozen" marker. After freezing:

1. The multixact members are no longer needed for those tuples
2. The `pg_multixact/members` and `pg_multixact/offsets` files can be truncated
3. `dat_minmxid` advances forward, reducing the mxid age

### Manual Freeze

If autovacuum can't keep up, run a manual freeze:

```sql
-- Freeze a specific table
VACUUM FREEZE inventory;

-- Freeze all tables in the database
-- (Use with caution on large databases — can take a long time)
VACUUM FREEZE ANALYZE;
```

### Why Freeze Can Be Blocked

MultiXact freeze requires that **no open transaction** still needs to see the old multixact members. A long-running transaction (even an idle one) can prevent freeze:

```sql
-- Find transactions blocking multixact freeze
SELECT
    pid,
    NOW() - xact_start AS transaction_duration,
    state,
    LEFT(query, 80) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
    AND NOW() - xact_start > INTERVAL '5 minutes'
ORDER BY xact_start;
```

If a transaction has been open for hours, autovacuum cannot advance `dat_minmxid` past the multixacts it might still need to resolve. This is the same problem as long-running transactions blocking regular XID freeze.

---

## Your Investigation

### 1. Check Current MultiXact Settings

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE '%multixact%'
ORDER BY name;
```

### 2. Check MultiXact Statistics

```sql
SELECT * FROM pg_stat_activity WHERE backend_type = 'autovacuum worker';

-- Check if any autovacuum is working on multixact freeze
SELECT
    relid::regclass,
    age(relfrozenxid) AS xid_age,
    relminmxid,
    mxid_age(relminmxid) AS mxid_age
FROM pg_class
WHERE relkind IN ('r', 'm', 't')
ORDER BY mxid_age(relminmxid) DESC
LIMIT 10;
```

### 3. Simulate and Monitor

After running `break-it.sql`, re-run the monitoring query to see how the mxid age has changed. Then run `VACUUM FREEZE` and watch it drop.

---

## Troubleshooting Tips

| Symptom | Cause | Fix |
|---------|-------|-----|
| Warning in logs about multixact wraparound | mxid age > 100M | Run `VACUUM FREEZE` on affected tables |
| `database is not accepting commands` | mxid age near 2B | Start in single-user mode, run `VACUUM FREEZE` |
| Autovacuum running constantly on one table | Table has high mxid age + active locking workload | Lower `autovacuum_multixact_freeze_max_age` for that table |
| mxid age keeps growing despite autovacuum | Long-running transaction blocking freeze | Kill the long-running transaction |
| `pg_multixact/` directory very large | Old multixact members not truncated | Run `VACUUM FREEZE` to allow truncation |
| `ERROR: out of shared memory` during heavy locking | `max_locks_per_transaction` too low | Increase `max_locks_per_transaction` |

---

## Mini-Challenge

**Predict**: If you disable autovacuum on a table and run `SELECT FOR SHARE` from 100 concurrent sessions on the same row every second, how long until mxid age reaches 100M?

Hint: Each `SELECT FOR SHARE` event that creates a new multixact increments the mxid counter. But multixacts are only created when the lock state changes (new member added). With 100 sessions locking the same row simultaneously, only 1 multixact is created per "batch." The real danger is when many *different rows* are locked concurrently across many transactions.

```sql
-- After running break-it.sql, check:
SELECT mxid_age(datminmxid) FROM pg_database WHERE datname = 'labdb';

-- Then freeze and verify:
VACUUM FREEZE ANALYZE;
SELECT mxid_age(datminmxid) FROM pg_database WHERE datname = 'labdb';
```

<hr>

**Answer**: It depends on how many *distinct* multixacts are created, not how many sessions participate. Each row that gets shared-locked by 2+ transactions creates 1 mxid. With 1000 rows being locked concurrently by different session pairs, you'd create ~1000 mxids per batch. At that rate, 100M mxids takes about 100K batches — hours to days depending on frequency. But a poorly designed application could do it much faster.
