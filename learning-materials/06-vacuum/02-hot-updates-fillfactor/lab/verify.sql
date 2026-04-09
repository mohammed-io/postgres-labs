-- ============================================================
-- Verify: HOT Updates & Fillfactor Lab
-- Run each section to validate your understanding.
-- ============================================================

\timing on

-- ============================================================
-- Section 1: Baseline — Table Structure & Settings
-- ============================================================

\echo '>>> Section 1: Baseline — Table Structure & Settings'

-- 1a. Check current fillfactor
SELECT
    relname,
    COALESCE(
        (SELECT unnest FROM unnest(reloptions) WHERE unnest LIKE 'fillfactor=%'),
        'fillfactor=100 (default)'
    ) AS fillfactor
FROM pg_class
WHERE relname = 'user_sessions';

-- 1b. List all indexes on user_sessions
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'user_sessions'
ORDER BY indexname;

-- 1c. Table and index sizes
SELECT
    pg_size_pretty(pg_relation_size('user_sessions')) AS heap_size,
    pg_size_pretty(pg_indexes_size('user_sessions')) AS index_size,
    pg_size_pretty(pg_total_relation_size('user_sessions')) AS total_size;

-- 1d. Page and tuple estimates
SELECT
    relpages AS pages,
    reltuples AS estimated_rows
FROM pg_class
WHERE relname = 'user_sessions';


-- ============================================================
-- Section 2: HOT Ratio with fillfactor=100 (Before)
-- ============================================================

\echo '>>> Section 2: HOT Ratio with fillfactor=100'

-- Reset stats for clean measurement
SELECT pg_stat_reset();

-- Update a NON-indexed column (last_active is NOT indexed)
UPDATE user_sessions SET last_active = NOW() WHERE id % 5 = 0;

-- Check HOT ratio
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Expected: ~0% HOT ratio — pages are full at fillfactor=100


-- ============================================================
-- Section 3: HOT Ratio After fillfactor=80
-- ============================================================

\echo '>>> Section 3: HOT Ratio After fillfactor=80'

-- Apply fillfactor and rebuild
ALTER TABLE user_sessions SET (fillfactor = 80);
VACUUM FULL user_sessions;
ANALYZE user_sessions;

-- Verify fillfactor took effect
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'user_sessions';

-- Reset stats
SELECT pg_stat_reset();

-- Same workload: update non-indexed column
UPDATE user_sessions SET last_active = NOW() WHERE id % 5 = 0;

-- Check HOT ratio again
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Expected: ~90-95% HOT ratio with fillfactor=80

-- Verify table grew (space trade-off)
SELECT
    pg_size_pretty(pg_relation_size('user_sessions')) AS heap_size_after_fillfactor;


-- ============================================================
-- Section 4: Indexed Column Update Kills HOT
-- ============================================================

\echo '>>> Section 4: Indexed Column Update Kills HOT'

-- Reset stats
SELECT pg_stat_reset();

-- Update an INDEXED column (status has idx_sessions_status)
UPDATE user_sessions SET status = 'idle', last_active = NOW() WHERE id % 5 = 0;

-- Check: HOT ratio should drop to 0%
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Expected: 0.0% — changing an indexed column prevents HOT


-- ============================================================
-- Section 5: Dead Tuple Comparison
-- ============================================================

\echo '>>> Section 5: Dead Tuples After Updates'

-- Check dead tuples
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    CASE WHEN n_live_tup + n_dead_tup > 0
        THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
        ELSE 0
    END AS dead_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Clean up
VACUUM user_sessions;
