-- ============================================================
-- Break-It: Intentionally break HOT updates to understand limits
-- Each scenario demonstrates a different failure mode.
-- Run each section independently or all together.
-- ============================================================

\timing on

-- ============================================================
-- Scenario 1: Update an INDEXED column → HOT ratio drops to 0%
-- ============================================================

\echo '>>> SCENARIO 1: Indexed Column Update Kills HOT'
\echo '>>> Expected: HOT ratio drops to 0% even with fillfactor=80'

-- Make sure we have fillfactor=80 applied
ALTER TABLE user_sessions SET (fillfactor = 80);
VACUUM FULL user_sessions;
ANALYZE user_sessions;

-- Reset statistics
SELECT pg_stat_reset();

-- First: update a NON-indexed column (should be HOT)
UPDATE user_sessions SET last_active = NOW() WHERE id % 10 = 0;

-- Check: HOT should be high
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    'before indexed update' AS phase
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Now: update an INDEXED column (status has idx_sessions_status)
-- This should KILL all HOT updates
UPDATE user_sessions SET status = 'idle' WHERE id % 10 = 0;

-- Check: HOT ratio should plummet
-- Note: cumulative stats, so ratio drops from the previous high
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    'after indexed update' AS phase
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

\echo 'OBSERVATION: The non_hot_updates jumped up. Even though fillfactor=80'
\echo 'leaves room for HOT, updating an indexed column (status) prevents HOT entirely.'
\echo ''
\echo 'LESSON: HOT requires NO indexed columns to change. Not even one.'
\echo 'If you need to update an indexed column frequently, consider removing that index.'
\echo ''

-- Reset for next scenario
VACUUM user_sessions;


-- ============================================================
-- Scenario 2: fillfactor=10 → Massive Space Waste
-- ============================================================

\echo '>>> SCENARIO 2: Extreme fillfactor=10 → Wasted Space'

-- Record size before
SELECT
    pg_size_pretty(pg_relation_size('user_sessions')) AS size_before,
    relpages AS pages_before
FROM pg_class
WHERE relname = 'user_sessions';

-- Set absurdly low fillfactor
ALTER TABLE user_sessions SET (fillfactor = 10);
VACUUM FULL user_sessions;
ANALYZE user_sessions;

-- Check size after
SELECT
    pg_size_pretty(pg_relation_size('user_sessions')) AS size_after_ff10,
    relpages AS pages_after
FROM pg_class
WHERE relname = 'user_sessions';

-- HOT ratio will be amazing!
SELECT pg_stat_reset();
UPDATE user_sessions SET last_active = NOW() WHERE id % 10 = 0;

SELECT
    n_tup_upd,
    n_tup_hot_upd,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    'fillfactor=10' AS note
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- But look at the cost: table is ~10x larger!
-- Each page is 90% empty → sequential scans read 10x more pages
-- Cache hit ratio tanks because you're caching mostly empty space

\echo 'OBSERVATION: HOT ratio is near 100%, but table size exploded.'
\echo 'Each page is 90% empty space. Your buffer cache is now 90% wasted.'
\echo ''
\echo 'LESSON: Extreme fillfactor values trade space for HOT updates.'
\echo 'The optimal value balances HOT ratio against space waste.'
\echo 'In production, never go below 70 without extreme justification.'
\echo ''

-- Fix: restore fillfactor=80
ALTER TABLE user_sessions SET (fillfactor = 80);
VACUUM FULL user_sessions;
ANALYZE user_sessions;


-- ============================================================
-- Scenario 3: fillfactor=100 on Heavy-Update Table → No HOT
-- ============================================================

\echo '>>> SCENARIO 3: fillfactor=100 (default) on heavy-update table'

-- Reset to default
ALTER TABLE user_sessions SET (fillfactor = 100);
VACUUM FULL user_sessions;
ANALYZE user_sessions;

-- Reset stats
SELECT pg_stat_reset();

-- Simulate heavy workload: 5 rounds of updating 20% of rows
DO $$
BEGIN
    FOR i IN 1..5 LOOP
        UPDATE user_sessions SET last_active = NOW() WHERE id % 5 = 0;
        RAISE NOTICE 'Round % complete', i;
    END LOOP;
END $$;

-- Results: zero or near-zero HOT updates
SELECT
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    'fillfactor=100 (default)' AS note
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Calculate wasted work
SELECT
    (n_tup_upd - n_tup_hot_upd) AS non_hot_updates,
    (n_tup_upd - n_tup_hot_upd) * (
        SELECT count(*) FROM pg_indexes WHERE tablename = 'user_sessions'
    ) AS total_index_writes,
    pg_size_pretty(
        (n_tup_upd - n_tup_hot_upd) * (
            SELECT count(*) FROM pg_indexes WHERE tablename = 'user_sessions'
        ) * 8192
    ) AS estimated_index_io
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Check table bloat: dead tuples everywhere
SELECT
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
    'fillfactor=100 bloat' AS note
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

\echo 'OBSERVATION: 100K updates × 4 indexes = 400K index writes that were'
\echo 'completely unnecessary. Plus dead tuples accumulating rapidly.'
\echo ''
\echo 'LESSON: The default fillfactor=100 is hostile to HOT updates.'
\echo 'Any UPDATE-heavy table with multiple indexes should use fillfactor < 100.'
\echo ''

-- Clean up
VACUUM user_sessions;

-- Restore to fillfactor=80 for further exploration
ALTER TABLE user_sessions SET (fillfactor = 80);
VACUUM FULL user_sessions;
ANALYZE user_sessions;


-- ============================================================
-- Bonus Scenario: Row Growth Breaks HOT
-- ============================================================

\echo '>>> BONUS SCENARIO: Row growth exceeds reserved space'

-- Even with fillfactor=80, if the updated row is much larger,
-- it won't fit in the reserved space

SELECT pg_stat_reset();

-- Normal update: row stays roughly same size → HOT works
UPDATE user_sessions SET last_active = NOW() WHERE id <= 1000;

SELECT
    n_tup_hot_upd AS hot_after_normal,
    n_tup_upd AS total_after_normal,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Growing update: user_agent column gets much larger
-- This may push the new tuple beyond the reserved space on some pages
UPDATE user_sessions
SET user_agent = user_agent || repeat('x', 200)
WHERE id <= 1000;

SELECT
    n_tup_hot_upd AS hot_after_growth,
    n_tup_upd AS total_after_growth,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_pct,
    'after row growth' AS note
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

\echo 'OBSERVATION: HOT ratio may drop slightly after row-growth updates.'
\echo 'When the new version is larger, it may not fit in the reserved space.'
\echo ''
\echo 'LESSON: fillfactor reserves space based on page size, not row size.'
\echo 'If rows grow significantly on update, you may need even lower fillfactor.'
