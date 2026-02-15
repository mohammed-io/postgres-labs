-- Verification for Caching lab

\echo '=== 1. Cache Settings ==='
SELECT
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE '%cache%' OR name LIKE '%buffer%'
ORDER BY name;

\echo ''
\echo '=== 2. Cache Hit Ratios ==='
SELECT
    schemaname,
    tablename,
    heap_blks_read AS disk_reads,
    heap_blks_hit AS cache_hits,
    round(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 2) AS hit_ratio_pct
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 0
ORDER BY hit_ratio_pct;

\echo ''
\echo '=== 3. Index Cache Hit Ratios ==='
SELECT
    schemaname,
    tablename,
    indexrelname AS index_name,
    idx_blks_read AS disk_reads,
    idx_blks_hit AS cache_hits,
    round(100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0), 2) AS hit_ratio_pct
FROM pg_statio_user_indexes
WHERE idx_blks_hit + idx_blks_read > 0
ORDER BY hit_ratio_pct;
