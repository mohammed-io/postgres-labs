-- ============================================================
-- Verification Queries: MultiXact ID Wraparound Lab
-- ============================================================

\echo '=== 1. MultiXact Status Across All Databases ==='
SELECT * FROM v_mxid_status;

\echo ''
\echo '=== 2. Per-Table MultiXact Age ==='
SELECT * FROM v_table_mxid_age;

\echo ''
\echo '=== 3. MultiXact Configuration Settings ==='
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE '%multixact%'
ORDER BY name;

\echo ''
\echo '=== 4. Current MultiXact Counter ==='
SELECT
    next_multixact_id::text::bigint AS next_mxid,
    next_xid AS next_xid
FROM pg_control_checkpoint();

\echo ''
\echo '=== 5. Table Row Statistics ==='
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    last_autovacuum,
    last_vacuum,
    autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;

\echo ''
\echo '=== 6. Active Locks (Current Session) ==='
SELECT
    locktype,
    database,
    relation::regclass AS table_name,
    pid,
    mode,
    granted
FROM pg_locks
WHERE locktype = 'transactionid'
    OR locktype = 'multixact'
ORDER BY pid;

\echo ''
\echo '=== 7. pg_multixact Directory Size ==='
\echo 'Run in the container shell for accurate results:'
\echo '  docker exec pg-multixact du -sh /var/lib/postgresql/data/pg_multixact/'
\echo ''
SELECT pg_size_pretty(
    (SELECT sum((pg_stat_file('pg_multixact/' || f)).size)::bigint
     FROM pg_ls_dir('pg_multixact') AS f)
) AS multixact_files_size;

\echo ''
\echo '=== 8. Long-Running Transactions (Block Freeze Risk) ==='
SELECT
    pid,
    usename,
    state,
    NOW() - xact_start AS duration,
    LEFT(query, 80) AS query_preview
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
    AND NOW() - xact_start > INTERVAL '10 seconds'
    AND pid != pg_backend_pid()
ORDER BY xact_start;

\echo ''
\echo '=== Health Summary ==='
SELECT
    CASE
        WHEN max_mxid_age > 150000000 THEN 'CRITICAL: mxid age > 150M — immediate action required'
        WHEN max_xid_age > 1500000000 THEN 'CRITICAL: xid age > 1.5B — immediate action required'
        WHEN max_mxid_age > 100000000 THEN 'WARNING: mxid age > 100M — investigate multixact accumulation'
        WHEN max_xid_age > 1000000000 THEN 'WARNING: xid age > 1B — investigate transaction freeze'
        ELSE 'OK: All wraparound metrics within safe range'
    END AS overall_status,
    max_mxid_age,
    max_xid_age
FROM (
    SELECT
        max(mxid_age(datminmxid)) AS max_mxid_age,
        max(age(datfrozenxid)) AS max_xid_age
    FROM pg_database
) sub;
