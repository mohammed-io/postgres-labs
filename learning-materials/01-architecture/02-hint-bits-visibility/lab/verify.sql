-- Verification queries for Hint Bits & Page-Level Visibility lab

\echo '=== 1. Extension Check ==='
SELECT
    extname,
    extversion
FROM pg_extension
WHERE extname = 'pageinspect';

\echo ''
\echo '=== 2. Table Overview ==='
SELECT
    relname,
    n_live_tup AS live_rows,
    n_dead_tup AS dead_rows,
    last_vacuum,
    last_autovacuum,
    autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;

\echo ''
\echo '=== 3. Hint Bit Status on orders Page 0 ==='
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS xmin_committed,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS xmin_unknown,
    count(*) FILTER (WHERE t_infomask & 512 = 512) AS xmin_invalid,
    count(*) FILTER (WHERE t_infomask & 2048 = 2048) AS xmax_invalid,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS hint_pct
FROM heap_page_items(get_raw_page('orders', 0))
WHERE t_xmin IS NOT NULL;

\echo ''
\echo '=== 4. Hint Bit Status on hint_bit_demo Page 0 ==='
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS xmin_committed,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS xmin_unknown,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS hint_pct
FROM heap_page_items(get_raw_page('hint_bit_demo', 0))
WHERE t_xmin IS NOT NULL;

\echo ''
\echo '=== 5. CLOG-Related Configuration ==='
SELECT
    name,
    setting,
    short_desc
FROM pg_settings
WHERE name IN ('wal_log_hints', 'autovacuum_naptime', 'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor')
ORDER BY name;

\echo ''
\echo '=== 6. I/O Statistics (Per Table) ==='
SELECT
    relname,
    heap_blks_read,
    heap_blks_hit,
    CASE WHEN heap_blks_read + heap_blks_hit > 0
        THEN round(heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 2)
        ELSE 0
    END AS cache_hit_pct
FROM pg_statio_user_tables
ORDER BY heap_blks_read DESC;

\echo ''
\echo '=== 7. Transaction ID State ==='
SELECT
    txid_current() AS current_xid,
    age(txid_current()) AS xid_age,
    (SELECT setting::int FROM pg_settings WHERE name = 'autovacuum_freeze_max_age') AS freeze_threshold;

\echo ''
\echo '=== 8. Health Summary ==='
SELECT
    CASE
        WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pageinspect')
        THEN 'OK: pageinspect installed'
        ELSE 'MISSING: pageinspect not installed'
    END AS extension_check,
    CASE
        WHEN (SELECT setting FROM pg_settings WHERE name = 'wal_log_hints') = 'on'
        THEN 'OK: wal_log_hints enabled'
        ELSE 'WARNING: wal_log_hints disabled (pg_rewind will fail)'
    END AS wal_log_hints_check,
    (SELECT count(*) FROM pg_stat_user_tables WHERE schemaname = 'public') AS user_tables;
