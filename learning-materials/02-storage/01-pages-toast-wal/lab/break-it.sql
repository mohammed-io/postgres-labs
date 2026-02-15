-- Break-it: Storage Issues

\echo '=== Break-it 1: Create Toast Bloat ==='

CREATE TABLE toast_bloat (
    id SERIAL,
    small_data TEXT,
    large_data TEXT
);

-- Insert rows with large data
INSERT INTO toast_bloat (small_data, large_data)
SELECT
    'small',
    repeat('x', 10000)
FROM generate_series(1, 1000);

-- Update (creates dead tuples in TOAST!)
UPDATE toast_bloat SET large_data = repeat('y', 10000);

-- Check TOAST bloat
SELECT
    t.relname,
    pg_size_pretty(pg_total_relation_size(pg_toast.oid::regclass)) AS toast_size,
    (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = t.relname) AS dead_tuples
FROM pg_class t
JOIN pg_class pg_toast ON t.reltoastrelid = pg_toast.oid
WHERE t.relname = 'toast_bloat';

\echo 'Notice: TOAST tables also accumulate dead tuples!'

\echo ''
\echo '=== Break-it 2: Fill pg_wal (archiving not set up) ==='

-- This will generate lots of WAL
CREATE TABLE wal_filler (
    id SERIAL,
    data TEXT
);

-- Generate massive WAL
INSERT INTO wal_filler (data)
SELECT repeat('z', 5000)
FROM generate_series(1, 50000);

-- Check WAL size
SELECT
    pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file,
    pg_size_pretty(pg_wal_file_size()) AS file_size,
    (SELECT count(*) FROM pg_ls_waldir()) AS total_files;

\echo ''
\echo '=== Cleanup ==='
DROP TABLE IF EXISTS toast_bloat;
DROP TABLE IF EXISTS wal_filler;
