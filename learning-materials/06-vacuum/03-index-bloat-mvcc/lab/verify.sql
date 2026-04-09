-- Verify: Index Bloat from MVCC Lab
-- Run each section to validate your understanding

-- =============================================
-- SECTION 1: Initial State
-- =============================================
SELECT '1. Initial State' AS section;

SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT count(*) AS total_rows FROM dashboard_metrics;

-- =============================================
-- SECTION 2: Index Structure Check
-- =============================================
SELECT '2. Index Structure Check' AS section;

SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'dashboard_metrics'
ORDER BY indexname;

-- =============================================
-- SECTION 3: Fragmentation Baseline
-- =============================================
SELECT '3. Fragmentation Baseline' AS section;

SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    coalesce(
        round((pgstatindex(indexrelname)).avg_leaf_density, 1),
        0
    ) AS avg_leaf_density_pct,
    coalesce(
        (pgstatindex(indexrelname)).leaf_pages,
        0
    ) AS leaf_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- =============================================
-- SECTION 4: Table Statistics
-- =============================================
SELECT '4. Table Statistics' AS section;

SELECT
    relname AS table_name,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'dashboard_metrics';

-- =============================================
-- SECTION 5: Health Summary
-- =============================================
SELECT '5. Health Summary' AS section;

SELECT
    'dashboard_metrics' AS table_name,
    pg_size_pretty(pg_total_relation_size('dashboard_metrics')) AS total_size,
    pg_size_pretty(pg_relation_size('dashboard_metrics')) AS table_only_size,
    pg_size_pretty(
        pg_total_relation_size('dashboard_metrics')
        - pg_relation_size('dashboard_metrics')
    ) AS all_indexes_size,
    (SELECT count(*) FROM pg_indexes WHERE tablename = 'dashboard_metrics') AS index_count;
