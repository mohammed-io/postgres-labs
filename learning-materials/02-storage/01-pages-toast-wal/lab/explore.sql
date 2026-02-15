-- Explore Storage Internals

\echo '=== Explore 1: Examine ctid Changes ==='
CREATE TEMP TABLE ctid_tracker AS
SELECT id, ctid AS original_ctid
FROM page_test;

UPDATE page_test SET name = name || '_updated' WHERE id <= 3;

SELECT
    p.id,
    c.original_ctid,
    p.ctid AS current_ctid,
    CASE WHEN c.original_ctid = p.ctid THEN 'Same location' ELSE 'Moved!' END AS status
FROM page_test p
JOIN ctid_tracker c ON p.id = c.id;

\echo ''
\echo '=== Explore 2: Page Bloat Detection ==='
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    n_dead_tup,
    n_live_tup,
    CASE
        WHEN n_live_tup > 0 THEN
            ROUND(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END AS dead_percentage
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY dead_percentage DESC;

\echo ''
\echo '=== Explore 3: TOAST Compression Ratio ==='
INSERT INTO toast_test (name, huge_data, json_data)
VALUES (
    'compressed_test',
    repeat('abcd', 5000),  -- 20KB, compressible
    ('{"data": "' || repeat('xyz', 5000) || '"}')::jsonb
)
ON CONFLICT DO NOTHING;

SELECT
    id,
    pg_size_pretty(pg_column_size(huge_data)) AS on_disk_size,
    pg_size_pretty(length(huge_data)::bigint) AS logical_size,
    pg_size_pretty(pg_column_size(huge_data)) AS actual_size,
    round(100.0 * pg_column_size(huge_data) / length(huge_data)::numeric, 2) AS compression_pct
FROM toast_test
WHERE name = 'compressed_test';

\echo ''
\echo '=== Explore 4: Checkpoint Statistics ==='
SELECT
    checkpoints_timed AS scheduled_checkpoints,
    checkpoints_req AS requested_checkpoints,
    checkpoint_write_time AS write_time_ms,
    checkpoint_sync_time AS sync_time_ms,
    buffers_checkpoint AS buffers_written,
    max_written_clean AS max_clean_hwm_exceeded
FROM pg_stat_bgwriter;

\echo ''
\echo '=== Explore 5: WAL File Information ==='
SELECT
    pg_current_wal_lsn() AS current_lsn,
    pg_walfile_name(pg_current_wal_lsn()) AS current_file,
    pg_size_pretty(pg_wal_file_size()) AS file_size,
    (SELECT count(*) FROM pg_ls_waldir()) AS total_files,
    pg_size_pretty((SELECT count(*) * pg_wal_file_size() FROM pg_ls_waldir())) AS total_wal_size;
