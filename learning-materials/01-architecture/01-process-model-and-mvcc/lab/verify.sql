-- Verification queries for Process Model & MVCC lab

\echo '=== 1. Background Processes ==='
SELECT
    backend_type,
    COUNT(*) AS process_count
FROM pg_stat_activity
GROUP BY backend_type
ORDER BY process_count DESC;

\echo ''
\echo '=== 2. Backend Connections ==='
SELECT
    COUNT(*) FILTER (WHERE backend_type = 'client backend') AS active_connections,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') -
        COUNT(*) FILTER (WHERE backend_type = 'client backend') AS available_connections
FROM pg_stat_activity;

\echo ''
\echo '=== 3. Memory Settings ==='
SELECT
    name,
    setting,
    unit,
    CASE
        WHEN unit = '8kB' THEN pg_size_pretty((setting::int8 * 8192)::bigint)
        WHEN unit = 'kB' THEN pg_size_pretty((setting::int8 * 1024)::bigint)
        ELSE setting || ' ' || COALESCE(unit, '')
    END AS human_value
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'max_connections')
ORDER BY name;

\echo ''
\echo '=== 4. MVCC Status ==='
SELECT
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    last_autovacuum,
    last_vacuum,
    last_analyze,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY tablename;

\echo ''
\echo '=== 5. Transaction ID Status ==='
SELECT
    txid_current() AS current_xid,
    age(txid_current()) AS transaction_age,
    (SELECT setting::int FROM pg_settings WHERE name = 'autovacuum_freeze_max_age') AS freeze_max_age;
