-- Benchmark: WAL Settings Impact

\echo '=== Benchmark: WAL Performance ==='
\timing on

-- Baseline: Default settings
DROP TABLE IF EXISTS wal_benchmark;
CREATE TABLE wal_benchmark (
    id SERIAL,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

\echo 'Inserting 10,000 rows with default settings...'
INSERT INTO wal_benchmark (data)
SELECT repeat('x', 1000) FROM generate_series(1, 10000);

-- Faster: Disable synchronous commit
SET synchronous_commit = off;

DROP TABLE IF EXISTS wal_benchmark_fast;
CREATE TABLE wal_benchmark_fast (
    id SERIAL,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

\echo 'Inserting 10,000 rows with synchronous_commit=off...'
INSERT INTO wal_benchmark_fast (data)
SELECT repeat('x', 1000) FROM generate_series(1, 10000);

SET synchronous_commit = on;

\timing off

\echo ''
\echo '=== Compare ==='
SELECT
    'Default' AS setting,
    pg_size_pretty(pg_total_relation_size('wal_benchmark')) AS table_size
UNION ALL
SELECT
    'synchronous_commit=off',
    pg_size_pretty(pg_total_relation_size('wal_benchmark_fast'));
