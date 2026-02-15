-- Exploration queries for Process Model & MVCC lab

\echo '=== Explore 1: See All Process Details ==='
SELECT
    pid,
    backend_type,
    CASE
        WHEN backend_type = 'client backend' THEN 'Connection from: ' || COALESCE(client_addr::text, 'local')
        ELSE 'Background process'
    END AS description,
    state,
    query_start
FROM pg_stat_activity
ORDER BY backend_type, pid;

\echo ''
\echo '=== Explore 2: Find Long-Running Transactions ==='
SELECT
    pid,
    usename,
    state,
    NOW() - query_start AS duration,
    LEFT(query, 50) AS query_preview
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
    AND query_start IS NOT NULL
    AND NOW() - query_start > INTERVAL '5 seconds'
ORDER BY duration DESC;

\echo ''
\echo '=== Explore 3: Check for Table Bloat ==='
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size,
    n_dead_tup,
    n_live_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_ratio_pct
FROM pg_stat_user_tables
WHERE n_live_tup > 0
ORDER BY dead_ratio_pct DESC;

\echo ''
\echo '=== Explore 4: Check autovacuum Configuration ==='
SELECT
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE '%autovacuum%'
ORDER BY name;

\echo ''
\echo '=== Explore 5: WAL Information ==='
SELECT
    pg_current_wal_lsn() AS current_lsn,
    pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file,
    pg_size_pretty(pg_wal_file_size()) AS wal_file_size,
    (SELECT count(*) FROM pg_ls_waldir()) AS total_wal_files;
