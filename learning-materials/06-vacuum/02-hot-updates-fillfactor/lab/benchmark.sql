-- ============================================================
-- Benchmark: Measure UPDATE throughput at different fillfactor values
-- Compares fillfactor 100, 90, and 80 on identical workloads.
-- ============================================================

\timing on

-- ============================================================
-- Section 0: Prepare benchmark tables
-- ============================================================

\echo '>>> Preparing benchmark tables...'

DROP TABLE IF EXISTS bench_ff100 CASCADE;
DROP TABLE IF EXISTS bench_ff90 CASCADE;
DROP TABLE IF EXISTS bench_ff80 CASCADE;

-- Create three identical tables with different fillfactors
CREATE TABLE bench_ff100 (LIKE user_sessions INCLUDING ALL);
ALTER TABLE bench_ff100 SET (fillfactor = 100);

CREATE TABLE bench_ff90 (LIKE user_sessions INCLUDING ALL);
ALTER TABLE bench_ff90 SET (fillfactor = 90);

CREATE TABLE bench_ff80 (LIKE user_sessions INCLUDING ALL);
ALTER TABLE bench_ff80 SET (fillfactor = 80);

-- Populate all three with identical data
INSERT INTO bench_ff100 SELECT * FROM user_sessions;
INSERT INTO bench_ff90 SELECT * FROM user_sessions;
INSERT INTO bench_ff80 SELECT * FROM user_sessions;

-- Rebuild ff90 and ff80 to apply fillfactor
-- (ff100 is already at 100, no rebuild needed)
VACUUM FULL bench_ff90;
VACUUM FULL bench_ff80;

-- Analyze all
ANALYZE bench_ff100;
ANALYZE bench_ff90;
ANALYZE bench_ff80;

-- Verify sizes differ
\echo '>>> Table sizes by fillfactor:'
SELECT
    'bench_ff100' AS label,
    pg_size_pretty(pg_relation_size('bench_ff100')) AS heap,
    pg_size_pretty(pg_total_relation_size('bench_ff100')) AS total
UNION ALL
SELECT
    'bench_ff90',
    pg_size_pretty(pg_relation_size('bench_ff90')),
    pg_size_pretty(pg_total_relation_size('bench_ff90'))
UNION ALL
SELECT
    'bench_ff80',
    pg_size_pretty(pg_relation_size('bench_ff80')),
    pg_size_pretty(pg_total_relation_size('bench_ff80'));


-- ============================================================
-- Section 1: Benchmark — Update Non-Indexed Column
-- ============================================================

\echo ''
\echo '>>> Benchmark 1: UPDATE on non-indexed column (last_active)'
\echo '>>> This column is NOT indexed → HOT eligible if space available'

-- Reset all stats
SELECT pg_stat_reset();

-- Benchmark ff100
\echo '--- fillfactor=100 ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
UPDATE bench_ff100 SET last_active = NOW() WHERE id % 10 = 0;

-- Benchmark ff90
\echo '--- fillfactor=90 ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
UPDATE bench_ff90 SET last_active = NOW() WHERE id % 10 = 0;

-- Benchmark ff80
\echo '--- fillfactor=80 ---'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
UPDATE bench_ff80 SET last_active = NOW() WHERE id % 10 = 0;

-- Compare HOT ratios
\echo ''
\echo '>>> HOT Ratio Comparison:'
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname LIKE 'bench_ff%'
ORDER BY relname;


-- ============================================================
-- Section 2: Throughput Test — Batch Updates
-- ============================================================

\echo ''
\echo '>>> Benchmark 2: Batch throughput (10 rounds of 10K updates)'

-- Create a results table
CREATE TABLE IF NOT EXISTS bench_results (
    test_name TEXT,
    fillfactor INTEGER,
    round_num INTEGER,
    duration_ms NUMERIC,
    hot_ratio_pct NUMERIC
);

-- Run 10 rounds of updates per fillfactor
DO $$
DECLARE
    round_idx INTEGER;
    start_t TIMESTAMPTZ;
    dur_ms NUMERIC;
    hot_pct NUMERIC;
BEGIN
    FOR round_idx IN 1..10 LOOP
        -- ff100
        start_t := clock_timestamp();
        EXECUTE 'UPDATE bench_ff100 SET last_active = NOW() WHERE id <= 10000';
        dur_ms := extract(epoch from (clock_timestamp() - start_t)) * 1000;
        SELECT round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1)
        INTO hot_pct
        FROM pg_stat_user_tables WHERE relname = 'bench_ff100';
        INSERT INTO bench_results VALUES ('non_indexed_update', 100, round_idx, dur_ms, hot_pct);

        -- ff90
        start_t := clock_timestamp();
        EXECUTE 'UPDATE bench_ff90 SET last_active = NOW() WHERE id <= 10000';
        dur_ms := extract(epoch from (clock_timestamp() - start_t)) * 1000;
        SELECT round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1)
        INTO hot_pct
        FROM pg_stat_user_tables WHERE relname = 'bench_ff90';
        INSERT INTO bench_results VALUES ('non_indexed_update', 90, round_idx, dur_ms, hot_pct);

        -- ff80
        start_t := clock_timestamp();
        EXECUTE 'UPDATE bench_ff80 SET last_active = NOW() WHERE id <= 10000';
        dur_ms := extract(epoch from (clock_timestamp() - start_t)) * 1000;
        SELECT round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1)
        INTO hot_pct
        FROM pg_stat_user_tables WHERE relname = 'bench_ff80';
        INSERT INTO bench_results VALUES ('non_indexed_update', 80, round_idx, dur_ms, hot_pct);

        -- VACUUM between rounds to clear dead tuples
        EXECUTE 'VACUUM bench_ff100';
        EXECUTE 'VACUUM bench_ff90';
        EXECUTE 'VACUUM bench_ff80';
    END LOOP;
END $$;

-- Results summary
\echo ''
\echo '>>> Throughput Summary:'
SELECT
    fillfactor,
    count(*) AS rounds,
    round(avg(duration_ms), 1) AS avg_ms_per_10k,
    round(min(duration_ms), 1) AS min_ms,
    round(max(duration_ms), 1) AS max_ms,
    round(avg(hot_ratio_pct), 1) AS avg_hot_ratio
FROM bench_results
WHERE test_name = 'non_indexed_update'
GROUP BY fillfactor
ORDER BY fillfactor;


-- ============================================================
-- Section 3: Indexed Column Update (Negative Control)
-- ============================================================

\echo ''
\echo '>>> Benchmark 3: UPDATE on indexed column (status) — HOT impossible'

SELECT pg_stat_reset();

-- All three tables: update an indexed column
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
UPDATE bench_ff80 SET status = 'idle' WHERE id % 10 = 0;

-- Verify: HOT ratio is 0% even with fillfactor=80
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'bench_ff80';

-- Expected: 0.0% — indexed column change means NO HOT regardless of fillfactor


-- ============================================================
-- Section 4: Space Overhead Comparison
-- ============================================================

\echo ''
\echo '>>> Space Overhead Summary:'
SELECT
    relname,
    substring(relname from 'ff(\d+)') AS fillfactor,
    relpages AS pages,
    pg_size_pretty(pg_relation_size(oid)) AS heap_size,
    CASE WHEN (SELECT relpages FROM pg_class WHERE relname = 'bench_ff100') > 0
        THEN round(100.0 * relpages /
            (SELECT relpages FROM pg_class WHERE relname = 'bench_ff100'), 1)
        ELSE 0
    END AS size_vs_ff100_pct
FROM pg_class
WHERE relname LIKE 'bench_ff%'
ORDER BY relname;


-- ============================================================
-- Cleanup
-- ============================================================

-- Uncomment to clean up benchmark tables:
-- DROP TABLE IF EXISTS bench_ff100 CASCADE;
-- DROP TABLE IF EXISTS bench_ff90 CASCADE;
-- DROP TABLE IF EXISTS bench_ff80 CASCADE;
-- DROP TABLE IF EXISTS bench_results;
