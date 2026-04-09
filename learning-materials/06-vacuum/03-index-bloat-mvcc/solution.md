# Solution: Index Bloat from MVCC

## Complete Reference

### Baseline Check (Before Any Changes)

```sql
-- Record initial index sizes and health
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Step 1: Generate Index Bloat

```sql
-- Baseline sizes
CREATE TABLE baseline_sizes AS
SELECT
    indexrelname,
    pg_relation_size(indexrelid) AS size_bytes
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics';

-- Mass UPDATE: changes 'status' (indexed) and 'metric_value' (indexed)
-- This creates dead entries in ALL 5 indexes, not just the 2 changed columns
UPDATE dashboard_metrics
SET status = 'archived',
    metric_value = metric_value + 1,
    updated_at = NOW();

-- VACUUM cleans the heap but does NOT compact indexes
VACUUM dashboard_metrics;

-- Compare sizes
SELECT
    b.indexrelname AS index_name,
    pg_size_pretty(b.size_bytes) AS before_size,
    pg_size_pretty(pg_relation_size(c.oid)) AS after_size,
    round(
        100.0 * (pg_relation_size(c.oid) - b.size_bytes) / b.size_bytes,
        1
    ) AS growth_pct
FROM baseline_sizes b
JOIN pg_class c ON c.relname = b.indexrelname
ORDER BY (pg_relation_size(c.oid) - b.size_bytes) DESC;
```

**Expected result:** All indexes roughly double in size. The `idx_dashboard_status` and `idx_dashboard_value` indexes grow the most because their key distribution changed significantly.

### Step 2: Measure Fragmentation

```sql
-- Check fragmentation for each index
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    (pgstatindex(indexrelname)).avg_leaf_density AS leaf_density_pct,
    (pgstatindex(indexrelname)).leaf_pages,
    (pgstatindex(indexrelname)).internal_pages,
    (pgstatindex(indexrelname)).empty_pages,
    (pgstatindex(indexrelname)).deleted_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY (pgstatindex(indexrelname)).avg_leaf_density;
```

**Expected result:** `avg_leaf_density` around 50% or lower for updated indexes. `leaf_pages` roughly doubled compared to optimal.

### Step 3: Measure Performance Degradation

```sql
-- Index-only scan on status (should show high Heap Fetches)
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'archived'
GROUP BY status;
```

**Expected:** `Index Only Scan` with significant `Heap Fetches` count. On a healthy index with good visibility map coverage, Heap Fetches should be near 0.

```sql
-- Regular index scan performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM dashboard_metrics
WHERE metric_name = 'cpu_usage'
ORDER BY recorded_at DESC
LIMIT 100;
```

**Expected:** Slower than optimal due to extra page reads from bloated `idx_dashboard_source` and `idx_dashboard_metric_name`.

### Step 4: Fix with REINDEX CONCURRENTLY

```sql
-- Record pre-REINDEX sizes
CREATE TABLE pre_reindex_sizes AS
SELECT
    indexrelname,
    pg_relation_size(indexrelid) AS size_bytes
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics';

-- Rebuild each bloated index without blocking writes
REINDEX INDEX CONCURRENTLY idx_dashboard_metric_name;
REINDEX INDEX CONCURRENTLY idx_dashboard_status;
REINDEX INDEX CONCURRENTLY idx_dashboard_source;
REINDEX INDEX CONCURRENTLY idx_dashboard_recorded_at;
REINDEX INDEX CONCURRENTLY idx_dashboard_value;

-- Compare post-REINDEX sizes
SELECT
    p.indexrelname AS index_name,
    pg_size_pretty(p.size_bytes) AS before_reindex,
    pg_size_pretty(pg_relation_size(c.oid)) AS after_reindex,
    round(
        100.0 * (pg_relation_size(c.oid) - p.size_bytes) / p.size_bytes,
        1
    ) AS change_pct
FROM pre_reindex_sizes p
JOIN pg_class c ON c.relname = p.indexrelname
ORDER BY p.size_bytes DESC;
```

**Expected result:** Index sizes shrink significantly (often 40-60% reduction). `avg_leaf_density` returns to 90%+.

### Step 5: Verify Performance Improvement

```sql
-- Same index-only scan — Heap Fetches should drop dramatically
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'archived'
GROUP BY status;

-- Verify fragmentation is gone
SELECT
    indexrelname,
    (pgstatindex(indexrelname)).avg_leaf_density AS leaf_density_pct
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics';
```

**Expected:** Heap Fetches near 0 (or matching actual live tuple count). `avg_leaf_density` at 90%+. Execution time significantly improved.

### Step 6: Ongoing Monitoring

```sql
-- Save this as a scheduled monitoring query
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    CASE
        WHEN idx_tup_read > 0
        THEN round(100.0 * idx_tup_fetch / idx_tup_read, 1)
        ELSE NULL
    END AS fetch_pct,
    coalesce(
        (pgstatindex(indexrelname)).avg_leaf_density,
        0
    )::numeric(5,1) AS leaf_density_pct,
    CASE
        WHEN coalesce((pgstatindex(indexrelname)).avg_leaf_density, 100) < 50
        THEN 'CRITICAL'
        WHEN coalesce((pgstatindex(indexrelname)).avg_leaf_density, 100) < 70
        THEN 'WARNING'
        ELSE 'OK'
    END AS health
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
    AND pg_relation_size(indexrelid) > 1024 * 1024
ORDER BY coalesce((pgstatindex(indexrelname)).avg_leaf_density, 100);
```

---

## Prevention Configuration

```sql
-- For the dashboard_metrics table (heavy updates)
ALTER TABLE dashboard_metrics SET (
    fillfactor = 75,
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_scale_factor = 0.01,
    autovacuum_analyze_threshold = 1000
);

-- Verify settings
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'dashboard_metrics';
```

---

## Decision Matrix

| Situation | Best Action | Why |
|-----------|-------------|-----|
| Single index bloated, maintenance window | `REINDEX INDEX name` | Fastest, simplest |
| Single index bloated, 24/7 system | `REINDEX INDEX CONCURRENTLY name` | No write lock |
| All indexes bloated, maintenance window | `REINDEX TABLE name` | Rebuilds all at once |
| Table + all indexes bloated | `VACUUM FULL name` | Rebuilds everything |
| Recurring bloat on non-indexed columns | Lower `fillfactor` to 75 | Enables HOT updates |
| Recurring bloat on indexed columns | More aggressive autovacuum | Cleans dead entries sooner |
| Very large index (>10GB) | `REINDEX CONCURRENTLY` + monitor disk | Needs 2x space during rebuild |

---

## Cleanup

```sql
DROP TABLE IF EXISTS baseline_sizes;
DROP TABLE IF EXISTS pre_reindex_sizes;
```
