-- Benchmark: Index Bloat from MVCC Lab
-- Compare query performance before and after REINDEX CONCURRENTLY
-- Run with: \timing on

\timing on

-- =============================================
-- STEP 1: Record Baseline Performance
-- =============================================
SELECT 'STEP 1: Baseline Performance (before bloat)' AS step;

-- Benchmark 1: Index-only scan on status
SELECT '--- Benchmark 1: Index-Only Scan (status) ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'active'
GROUP BY status;

-- Benchmark 2: Range scan on recorded_at
SELECT '--- Benchmark 2: Range Scan (recorded_at) ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, metric_name, metric_value, recorded_at
FROM dashboard_metrics
WHERE recorded_at > NOW() - INTERVAL '7 days'
ORDER BY recorded_at DESC
LIMIT 500;

-- Benchmark 3: Composite index scan (source + recorded_at)
SELECT '--- Benchmark 3: Composite Index (source, recorded_at) ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT source, count(*), avg(metric_value)
FROM dashboard_metrics
WHERE source = 'prod-api-01'
    AND recorded_at > NOW() - INTERVAL '30 days'
GROUP BY source;

-- Benchmark 4: Point lookup on metric_value
SELECT '--- Benchmark 4: Point Lookup (metric_value) ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, metric_name, metric_value
FROM dashboard_metrics
WHERE metric_value BETWEEN 50 AND 50.01
LIMIT 100;

-- =============================================
-- STEP 2: Generate Index Bloat
-- =============================================
SELECT 'STEP 2: Generating index bloat...' AS step;

-- Record pre-bloat sizes
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS pre_bloat_size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Mass update: changes status (indexed) and metric_value (indexed)
-- Creates dead entries in ALL 5 indexes
UPDATE dashboard_metrics
SET status = 'archived',
    metric_value = metric_value + (random() * 10),
    updated_at = NOW();

-- VACUUM cleans heap but NOT indexes
VACUUM dashboard_metrics;

-- Show post-bloat sizes
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS post_bloat_size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Show fragmentation
SELECT
    indexrelname AS index_name,
    round((pgstatindex(indexrelname)).avg_leaf_density, 1) AS leaf_density_pct,
    (pgstatindex(indexrelname)).leaf_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY (pgstatindex(indexrelname)).avg_leaf_density;

-- =============================================
-- STEP 3: Measure Performance With Bloat
-- =============================================
SELECT 'STEP 3: Performance WITH bloat' AS step;

-- Same 4 benchmarks, now with bloated indexes
SELECT '--- Benchmark 1: Index-Only Scan (status) WITH BLOAT ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'archived'
GROUP BY status;

SELECT '--- Benchmark 2: Range Scan (recorded_at) WITH BLOAT ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, metric_name, metric_value, recorded_at
FROM dashboard_metrics
WHERE recorded_at > NOW() - INTERVAL '7 days'
ORDER BY recorded_at DESC
LIMIT 500;

SELECT '--- Benchmark 3: Composite Index (source, recorded_at) WITH BLOAT ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT source, count(*), avg(metric_value)
FROM dashboard_metrics
WHERE source = 'prod-api-01'
    AND recorded_at > NOW() - INTERVAL '30 days'
GROUP BY source;

SELECT '--- Benchmark 4: Point Lookup (metric_value) WITH BLOAT ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, metric_name, metric_value
FROM dashboard_metrics
WHERE metric_value BETWEEN 50 AND 50.01
LIMIT 100;

-- =============================================
-- STEP 4: REINDEX CONCURRENTLY (No Write Lock)
-- =============================================
SELECT 'STEP 4: REINDEX CONCURRENTLY' AS step;

REINDEX INDEX CONCURRENTLY idx_dashboard_metric_name;
REINDEX INDEX CONCURRENTLY idx_dashboard_status;
REINDEX INDEX CONCURRENTLY idx_dashboard_source;
REINDEX INDEX CONCURRENTLY idx_dashboard_recorded_at;
REINDEX INDEX CONCURRENTLY idx_dashboard_value;

-- Show post-REINDEX sizes
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS post_reindex_size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Verify fragmentation is resolved
SELECT
    indexrelname AS index_name,
    round((pgstatindex(indexrelname)).avg_leaf_density, 1) AS leaf_density_pct,
    (pgstatindex(indexrelname)).leaf_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY (pgstatindex(indexrelname)).avg_leaf_density;

-- =============================================
-- STEP 5: Measure Performance After REINDEX
-- =============================================
SELECT 'STEP 5: Performance AFTER REINDEX' AS step;

SELECT '--- Benchmark 1: Index-Only Scan (status) AFTER REINDEX ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'archived'
GROUP BY status;

SELECT '--- Benchmark 2: Range Scan (recorded_at) AFTER REINDEX ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, metric_name, metric_value, recorded_at
FROM dashboard_metrics
WHERE recorded_at > NOW() - INTERVAL '7 days'
ORDER BY recorded_at DESC
LIMIT 500;

SELECT '--- Benchmark 3: Composite Index (source, recorded_at) AFTER REINDEX ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT source, count(*), avg(metric_value)
FROM dashboard_metrics
WHERE source = 'prod-api-01'
    AND recorded_at > NOW() - INTERVAL '30 days'
GROUP BY source;

SELECT '--- Benchmark 4: Point Lookup (metric_value) AFTER REINDEX ---' AS benchmark;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, metric_name, metric_value
FROM dashboard_metrics
WHERE metric_value BETWEEN 50 AND 50.01
LIMIT 100;

-- =============================================
-- STEP 6: Summary Comparison
-- =============================================
SELECT 'STEP 6: Key Observations' AS step;

SELECT '
Compare the results:
1. Index sizes: Should shrink significantly after REINDEX (40-60% reduction)
2. Leaf density: Should go from ~50% to ~90%+
3. Leaf pages: Should roughly halve
4. Execution times: Should improve noticeably
5. Heap Fetches in index-only scans: Should decrease
6. Buffer reads: Fewer shared blocks read = less I/O

Key insight: REINDEX CONCURRENTLY rebuilds each index without
blocking reads or writes. The old index is kept until the new
one is fully built, then they are atomically swapped.
' AS observations;

\timing off
