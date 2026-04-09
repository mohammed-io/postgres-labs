-- Benchmark: Measure Visibility Check Overhead With/Without Hint Bits

\timing on

\echo '=== Benchmark 1: Cold Read - No Hint Bits (Simulated) ==='
\echo 'Creating a table with fresh data that has no hint bits set...'

DROP TABLE IF EXISTS bench_cold;
CREATE TABLE bench_cold (
    id serial PRIMARY KEY,
    data text NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- Insert all rows in a single transaction
-- All rows share the same t_xmin, but hint bits are still NOT set until first read
-- (One CLOG lookup is cached, but every data page still gets dirtied)
DO $$
BEGIN
    FOR i IN 1..200 LOOP
        INSERT INTO bench_cold (data)
        SELECT 'row-' || i || '-' || repeat('x', 80)
        FROM generate_series(1, 50);
    END LOOP;
END $$;

-- Reset I/O stats tracking
SELECT pg_stat_reset();

\echo ''
\echo '--- First scan: setting hint bits + CLOG lookups ---'
EXPLAIN (ANALYZE, BUFFERS, TIMING, FORMAT TEXT)
SELECT count(*) FROM bench_cold;

\echo ''
\echo '--- I/O stats after first scan ---'
SELECT
    relname,
    heap_blks_read,
    heap_blks_hit,
    CASE WHEN heap_blks_read + heap_blks_hit > 0
        THEN round(heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 2)
        ELSE 0
    END AS cache_hit_pct
FROM pg_statio_user_tables
WHERE relname = 'bench_cold';

\echo ''
\echo '=== Benchmark 2: Warm Read - Hint Bits Already Set ==='
\echo 'Running the same scan again (hint bits now cached on pages)...'

EXPLAIN (ANALYZE, BUFFERS, TIMING, FORMAT TEXT)
SELECT count(*) FROM bench_cold;

\echo ''
\echo '--- I/O stats after second scan ---'
SELECT
    relname,
    heap_blks_read,
    heap_blks_hit,
    CASE WHEN heap_blks_read + heap_blks_hit > 0
        THEN round(heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 2)
        ELSE 0
    END AS cache_hit_pct
FROM pg_statio_user_tables
WHERE relname = 'bench_cold';

\timing off

\echo ''
\echo '=== Benchmark 3: Hint Bit Coverage Analysis ==='
\timing on

-- Check how many tuples on the first few pages had hint bits before vs after
SELECT
    'bench_cold page 0' AS source,
    count(*) AS tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS hints_missing
FROM heap_page_items(get_raw_page('bench_cold', 0))
WHERE t_xmin IS NOT NULL;

\timing off

\echo ''
\echo '=== Benchmark 4: VACUUM Hint Bit Setting Speed ==='
\timing on

-- Create another table to measure vacuum hint bit setting
DROP TABLE IF EXISTS bench_vacuum;
CREATE TABLE bench_vacuum (
    id serial PRIMARY KEY,
    data text NOT NULL
);

DO $$
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO bench_vacuum (data) VALUES (repeat('v', 100));
    END LOOP;
END $$;

-- Check hint bits before vacuum
\echo '--- Before VACUUM ---'
SELECT
    count(*) AS total,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS pct
FROM heap_page_items(get_raw_page('bench_vacuum', 0))
WHERE t_xmin IS NOT NULL;

-- Run vacuum (sets hint bits as side effect)
\echo '--- Running VACUUM ---'
VACUUM bench_vacuum;

-- Check hint bits after vacuum
\echo '--- After VACUUM ---'
SELECT
    count(*) AS total,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS pct
FROM heap_page_items(get_raw_page('bench_vacuum', 0))
WHERE t_xmin IS NOT NULL;

\timing off

\echo ''
\echo '=== Analysis ==='
\echo 'Compare the "shared read" and "shared dirtied" values between Benchmark 1 and 2.'
\echo 'The first scan dirties pages (setting hint bits). The second scan does not.'
\echo 'The execution time difference shows the cost of missing hint bits.'
\echo ''
\echo 'Key insight: The FIRST read after commit is always slower because it:'
\echo '  1. Looks up t_xmin in CLOG (I/O if not cached)'
\echo '  2. Sets the HEAP_XMIN_COMMITTED hint bit on the data page'
\echo '  3. Dirties the page (will need to be written to disk)'
\echo 'All subsequent reads skip steps 1-3 entirely.'

DROP TABLE IF EXISTS bench_cold;
DROP TABLE IF EXISTS bench_vacuum;
