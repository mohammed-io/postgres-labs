# Step 2: Measuring and Understanding Bloat

## What is Bloat?

Bloat = Dead tuples + Empty space in pages

```
Page 1 (8KB):
┌────────────────────────────────┐
│ Live row  (2KB)               │
│ DEAD tuple (2KB) - can't reuse │
│ Live row  (2KB)               │
│ DEAD tuple (2KB) - can't reuse │
│ Empty     (0KB)                │
└────────────────────────────────┘
Total: 4KB used, 4KB wasted = 50% bloat!
```

---

## Investigation

### 1. Measure Table Bloat

```sql
docker exec -it postgres-vacuum psql -U postgres

-- Quick bloat check
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    n_dead_tup,
    n_live_tup,
    CASE
        WHEN n_live_tup > 0 THEN
            round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END AS dead_ratio_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND n_live_tup > 0
ORDER BY dead_ratio_pct DESC;
```

### 2. Measure Actual Disk Bloat

This estimates wasted space from dead tuples and empty space:

```sql
-- Detailed bloat analysis
CREATE EXTENSION IF NOT EXISTS pgstattuple;

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(
        (pg_total_relation_size(schemaname||'.'||tablename) *
         (pgstattuple_approx(schemaname||'.'||tablename)).free_percent / 100)::bigint
    ) AS free_space,
    (pgstattuple_approx(schemaname||'.'||tablename)).free_percent AS free_pct,
    (pgstattuple_approx(schemaname||'.'||tablename)).dead_tuple_percent AS dead_pct
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY (pgstattuple_approx(schemaname||'.'||tablename)).dead_tuple_percent DESC;
```

### 3. Understand Visibility Map

```sql
-- Check visibility map
SELECT
    schemaname,
    tablename,
    heap_blks_scanned AS blocks_scanned,
    heap_blks_vacuumed AS blocks_all_visible,
    round(100.0 * heap_blks_vacuumed / NULLIF(heap_blks_scanned, 0), 2) AS vm_coverage_pct
FROM pg_stat_user_tables
WHERE heap_blks_scanned > 0
ORDER BY vm_coverage_pct;
```

**Visibility Map** = Tracks which pages have only visible tuples (no dead tuples).
- High VM coverage = Faster index-only scans
- Autovacuum updates VM after cleaning

### 4. Trigger Manual Vacuum

```sql
-- Regular vacuum (doesn't lock table)
VACUUM user_sessions;

-- Full vacuum (locks table, rewrites file)
-- Only use on maintenance windows!
VACUUM FULL user_sessions;

-- Analyze (update statistics for planner)
ANALYZE user_sessions;
```

**VACUUM vs VACUUM FULL**:

| | VACUUM | VACUUM FULL |
|---|--------|-------------|
| Locks table | No | Yes (exclusive) |
| Reclaims space | Reuses internally | Returns to OS |
| Duration | Fast | Slow (rewrites table) |
| Safe for prod | Yes | No |

---

## Real-World Example

**Scenario**: `events` table after bulk update

```sql
-- Before cleanup
SELECT
    pg_size_pretty(pg_total_relation_size('events')) AS size,
    n_dead_tup,
    n_live_tup;
-- size: 2GB, dead: 900K, live: 100K = 90% bloat!

-- After VACUUM
VACUUM events;

-- After cleanup
-- size: 2GB (file size same), dead: 0, live: 100K
-- Space is reusable but not returned to OS

-- After VACUUM FULL (maintenance window)
-- size: 200MB, dead: 0, live: 100K
-- Space returned to OS!
```

See solution.md for production bloat management strategies.
