-- ============================================================
-- Exploration Queries: MultiXact ID Wraparound Lab
-- ============================================================

\echo '=== Explore 1: What is the Current MultiXact Counter? ==='
SELECT
    next_multixact_id::text::bigint AS current_mxid,
    next_xid AS current_xid,
    checkpoint_lsn AS checkpoint_lsn
FROM pg_control_checkpoint();

\echo ''
\echo '=== Explore 2: MultiXact Age Per Database ==='
SELECT
    datname,
    datminmxid AS oldest_unfrozen_mxid,
    mxid_age(datminmxid) AS mxid_age,
    datfrozenxid AS oldest_unfrozen_xid,
    age(datfrozenxid) AS xid_age,
    ROUND(100.0 * mxid_age(datminmxid) / 2147483648, 6) AS pct_mxid_to_limit,
    ROUND(100.0 * age(datfrozenxid) / 2147483648, 6) AS pct_xid_to_limit
FROM pg_database
ORDER BY mxid_age(datminmxid) DESC;

\echo ''
\echo '=== Explore 3: Tables With Highest MultiXact Age ==='
SELECT
    n.nspname AS schema,
    c.relname AS table_name,
    c.relminmxid AS min_mxid,
    mxid_age(c.relminmxid) AS mxid_age,
    c.relfrozenxid AS min_xid,
    age(c.relfrozenxid) AS xid_age,
    pg_size_pretty(pg_relation_size(c.oid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
    AND n.nspname = 'public'
ORDER BY mxid_age(c.relminmxid) DESC;

\echo ''
\echo '=== Explore 4: MultiXact-Related Autovacuum Settings ==='
SELECT
    name,
    setting,
    unit,
    context,
    short_desc
FROM pg_settings
WHERE name LIKE '%multixact%'
    OR name LIKE '%freeze%'
    OR name = 'autovacuum_freeze_max_age'
    OR name = 'autovacuum_freeze_table_age'
    OR name = 'autovacuum_freeze_min_age'
ORDER BY name;

\echo ''
\echo '=== Explore 5: Inspect Tuple Headers for MultiXact Flags ==='
-- Look at the first page of the inventory table for multixact tuples
SELECT
    lp AS line_pointer,
    t_xmin,
    t_xmax,
    t_infomask,
    t_infomask2,
    CASE WHEN t_infomask & 4096 != 0 THEN 'YES' ELSE 'NO' END AS has_multixact,
    CASE WHEN t_infomask & 1024 != 0 THEN 'YES' ELSE 'NO' END AS has_shared_lock,
    CASE WHEN t_infomask & 2048 != 0 THEN 'YES' ELSE 'NO' END AS has_exclusive_lock,
    CASE WHEN t_infomask & 512 != 0 THEN 'YES' ELSE 'NO' END AS has_key_share_lock
FROM heap_page_items(get_raw_page('inventory', 0))
ORDER BY lp;

\echo ''
\echo '=== Explore 6: Active Transaction Locks ==='
SELECT
    locktype,
    database,
    CASE
        WHEN relation IS NOT NULL THEN relation::regclass::text
        ELSE 'N/A'
    END AS table_name,
    pid,
    virtualxid,
    transactionid,
    mode,
    granted,
    fastpath
FROM pg_locks
WHERE locktype IN ('transactionid', 'multixact', 'tuple')
ORDER BY pid, locktype;

\echo ''
\echo '=== Explore 7: Autovacuum Workers (Is One Freezing?) ==='
SELECT
    pid,
    datname,
    relid::regclass AS table_name,
    state,
    NOW() - query_start AS duration,
    LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker'
ORDER BY query_start;

\echo ''
\echo '=== Explore 8: Dead Tuple Accumulation ==='
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
    last_autovacuum,
    last_vacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC;

\echo ''
\echo '=== Explore 9: Check pg_stat_statements for FOR SHARE Queries ==='
-- Requires pg_stat_statements extension
SELECT
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_ms,
    ROUND(mean_exec_time::numeric, 2) AS mean_ms,
    LEFT(query, 100) AS query_preview
FROM pg_stat_statements
WHERE query ILIKE '%FOR SHARE%'
    OR query ILIKE '%FOR KEY SHARE%'
    OR query ILIKE '%FOR UPDATE%'
ORDER BY calls DESC
LIMIT 10;
