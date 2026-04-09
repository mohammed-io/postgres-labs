-- Exploration queries for Hint Bits & Page-Level Visibility lab

\echo '=== Explore 1: Inspect Raw Tuple Headers on orders ==='
SELECT
    lp AS tuple_offset,
    t_xmin,
    t_xmax,
    t_infomask,
    t_infomask2,
    CASE WHEN t_infomask & 256 = 256 THEN 'SET' ELSE 'MISSING' END AS xmin_committed,
    CASE WHEN t_infomask & 512 = 512 THEN 'SET' ELSE 'NOT SET' END AS xmin_invalid,
    CASE WHEN t_infomask & 1024 = 1024 THEN 'SET' ELSE 'NOT SET' END AS xmax_committed,
    CASE WHEN t_infomask & 2048 = 2048 THEN 'SET' ELSE 'NOT SET' END AS xmax_invalid
FROM heap_page_items(get_raw_page('orders', 0))
WHERE t_xmin IS NOT NULL
LIMIT 20;

\echo ''
\echo '=== Explore 2: Compare Hint Bits Across Pages ==='
SELECT
    page_num,
    count(*) AS tuples_on_page,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS hints_missing,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / count(*), 1) AS hint_pct
FROM (
    SELECT 0 AS page_num, lp, t_xmin, t_infomask FROM heap_page_items(get_raw_page('orders', 0))
    UNION ALL
    SELECT 1, lp, t_xmin, t_infomask FROM heap_page_items(get_raw_page('orders', 1))
    UNION ALL
    SELECT 2, lp, t_xmin, t_infomask FROM heap_page_items(get_raw_page('orders', 2))
    UNION ALL
    SELECT 3, lp, t_xmin, t_infomask FROM heap_page_items(get_raw_page('orders', 3))
    UNION ALL
    SELECT 4, lp, t_xmin, t_infomask FROM heap_page_items(get_raw_page('orders', 4))
) sub
WHERE t_xmin IS NOT NULL
GROUP BY page_num
ORDER BY page_num;

\echo ''
\echo '=== Explore 3: See Transaction Status in CLOG ==='
-- For the first few tuples, check what CLOG would return
SELECT
    lp AS offset,
    t_xmin,
    CASE
        WHEN t_infomask & 256 = 256 THEN 'committed (hint bit)'
        WHEN t_infomask & 512 = 512 THEN 'aborted (hint bit)'
        ELSE pg_xact_status(t_xmin::text::bigint)::text || ' (from CLOG)'
    END AS tx_status
FROM heap_page_items(get_raw_page('orders', 0))
WHERE t_xmin IS NOT NULL
LIMIT 10;

\echo ''
\echo '=== Explore 4: CLOG Directory and Files ==='
-- CLOG files live in pg_xact/ directory
-- File naming: 0000, 0001, etc. Each file covers a range of transaction IDs
SELECT *
FROM pg_ls_dir('pg_xact') AS files(name)
ORDER BY name;

\echo ''
\echo '=== Explore 5: Visibility Map Overview ==='
-- The visibility map tracks which pages are "all-visible"
-- VACUUM sets visibility map bits after confirming all tuples visible
-- pg_visibility extension was installed by setup.sql
SELECT
    blkno AS page_number,
    all_visible,
    all_frozen
FROM pg_visibility_map('orders')
LIMIT 20;

\echo ''
\echo '=== Explore 5b: Visibility Map Summary ==='
SELECT
    count(*) AS total_pages,
    count(*) FILTER (WHERE all_visible) AS all_visible_pages,
    count(*) FILTER (WHERE all_frozen) AS all_frozen_pages,
    round(100.0 * count(*) FILTER (WHERE all_visible) / count(*), 1) AS visible_pct
FROM pg_visibility_map('orders');

\echo ''
\echo '=== Explore 6: Autovacuum Activity and Hint Bit Setting ==='
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    last_autovacuum,
    last_vacuum,
    autovacuum_count,
    vacuum_count,
    round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;

\echo ''
\echo '=== Explore 7: Check wal_log_hints Impact ==='
-- With wal_log_hints=on, hint bit changes generate WAL records
-- Check current WAL generation rate
SELECT
    pg_current_wal_lsn() AS current_lsn,
    pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) AS total_wal_generated;
