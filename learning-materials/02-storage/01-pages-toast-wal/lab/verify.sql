-- Verification for Storage lab

\echo '=== 1. Page Information ==='
SELECT
    relname,
    relpages AS page_count,
    reltuples AS approx_row_count,
    pg_size_pretty(pg_relation_size(relname::regclass)) AS table_size
FROM pg_class
WHERE relname IN ('page_test', 'toast_test', 'wal_test')
ORDER BY relname;

\echo ''
\echo '=== 2. TOAST Tables ==='
SELECT
    t.relname AS main_table,
    pg_toast.relname AS toast_table,
    pg_size_pretty(pg_total_relation_size(t.oid::regclass)) AS main_size,
    pg_size_pretty(pg_total_relation_size(pg_toast.oid::regclass)) AS toast_size
FROM pg_class t
JOIN pg_class pg_toast ON t.reltoastrelid = pg_toast.oid
WHERE t.relname IN ('toast_test', 'page_test');

\echo ''
\echo '=== 3. WAL Settings ==='
SELECT
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE '%wal%'
   OR name = 'synchronous_commit'
   OR name LIKE '%checkpoint%'
ORDER BY name;

\echo ''
\echo '=== 4. Block Size ==='
SHOW block_size;
