-- Explore: Index Bloat from MVCC Lab
-- Discovery queries to understand index health

-- =============================================
-- 1. pgstatindex Deep Dive: Per-Index Fragmentation
-- =============================================
SELECT '1. pgstatindex Deep Dive' AS section;

-- Detailed fragmentation for the status index
SELECT * FROM pgstatindex('idx_dashboard_status');

-- Detailed fragmentation for the value index
SELECT * FROM pgstatindex('idx_dashboard_value');

-- Compare all indexes side by side
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    (pgstatindex(indexrelname)).avg_leaf_density,
    (pgstatindex(indexrelname)).leaf_pages,
    (pgstatindex(indexrelname)).internal_pages,
    (pgstatindex(indexrelname)).empty_pages,
    (pgstatindex(indexrelname)).deleted_pages,
    (pgstatindex(indexrelname)).free_space
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY (pgstatindex(indexrelname)).avg_leaf_density;

-- =============================================
-- 2. pg_stat_user_indexes: Scan Patterns
-- =============================================
SELECT '2. Index Scan Patterns' AS section;

SELECT
    indexrelname AS index_name,
    idx_scan AS total_index_scans,
    idx_tup_read AS index_entries_read,
    idx_tup_fetch AS heap_tuples_fetched,
    CASE
        WHEN idx_tup_read > 0
        THEN round(100.0 * idx_tup_fetch / idx_tup_read, 1)
        ELSE NULL
    END AS fetch_to_read_pct,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY idx_tup_read DESC;

-- =============================================
-- 3. Index-Only Scan Feasibility Check
-- =============================================
SELECT '3. Index-Only Scan Feasibility' AS section;

-- Check visibility map coverage for the table
SELECT
    relname,
    heap_blks_scanned,
    heap_blks_vacuumed,
    CASE
        WHEN heap_blks_scanned > 0
        THEN round(100.0 * heap_blks_vacuumed / heap_blks_scanned, 1)
        ELSE 0
    END AS visibility_map_pct
FROM pg_stat_user_tables
WHERE relname = 'dashboard_metrics';

-- Test index-only scan and check Heap Fetches
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'active'
GROUP BY status;

-- =============================================
-- 4. Index Size Relative to Table
-- =============================================
SELECT '4. Index Size Ratio' AS section;

SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    round(
        100.0 * pg_relation_size(indexrelid)
        / pg_relation_size('dashboard_metrics'),
        1
    ) AS pct_of_table_size,
    (SELECT count(DISTINCT metric_name) FROM dashboard_metrics) AS metric_name_cardinality,
    (SELECT count(DISTINCT status) FROM dashboard_metrics) AS status_cardinality
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- =============================================
-- 5. Correlation Between Index Order and Heap Order
-- =============================================
SELECT '5. Physical Correlation' AS section;

-- Low correlation means index scans are less efficient (more random I/O)
SELECT
    attname AS column_name,
    correlation
FROM pg_stats
WHERE tablename = 'dashboard_metrics'
    AND attname IN ('metric_name', 'status', 'source', 'recorded_at', 'metric_value')
ORDER BY abs(correlation);

-- =============================================
-- 6. HOT Update Potential Assessment
-- =============================================
SELECT '6. HOT Update Assessment' AS section;

SELECT
    relname AS table_name,
    reloptions,
    CASE
        WHEN reloptions @> '{fillfactor=100}' OR reloptions IS NULL
        THEN 'Default (100%) - No room for HOT'
        ELSE 'Custom fillfactor set'
    END AS hot_eligibility
FROM pg_class
WHERE relname = 'dashboard_metrics';

-- =============================================
-- 7. Comprehensive Index Health Report
-- =============================================
SELECT '7. Comprehensive Health Report' AS section;

SELECT
    i.indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
    i.idx_scan AS scans,
    coalesce(
        round((pgstatindex(i.indexrelname)).avg_leaf_density, 1),
        0
    ) AS leaf_density_pct,
    CASE
        WHEN coalesce((pgstatindex(i.indexrelname)).avg_leaf_density, 100) < 50
        THEN 'CRITICAL - REINDEX needed'
        WHEN coalesce((pgstatindex(i.indexrelname)).avg_leaf_density, 100) < 70
        THEN 'WARNING - Monitor closely'
        ELSE 'OK'
    END AS health_status
FROM pg_stat_user_indexes i
WHERE i.relname = 'dashboard_metrics'
ORDER BY coalesce((pgstatindex(i.indexrelname)).avg_leaf_density, 100);
