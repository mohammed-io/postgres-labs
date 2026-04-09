-- ============================================================
-- Explore: Discovery Queries for HOT Updates & Fillfactor
-- Use these to build intuition about how HOT works internally.
-- ============================================================

\timing on

-- ============================================================
-- Section 1: Understanding pg_stat_user_tables HOT Columns
-- ============================================================

\echo '>>> Section 1: HOT Statistics Columns'

-- All HOT-related columns in pg_stat_user_tables
SELECT
    relname,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_del AS deletes,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * (n_tup_upd - n_tup_hot_upd) / n_tup_upd, 1)
        ELSE 0
    END AS non_hot_ratio_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;


-- ============================================================
-- Section 2: Index Write Amplification Estimate
-- ============================================================

\echo '>>> Section 2: Index Write Amplification'

-- Estimate how many index writes non-HOT updates caused
SELECT
    st.relname,
    st.n_tup_upd - st.n_tup_hot_upd AS non_hot_updates,
    (st.n_tup_upd - st.n_tup_hot_upd) * (
        SELECT count(*)
        FROM pg_indexes
        WHERE tablename = st.relname
    ) AS estimated_index_writes,
    (st.n_tup_upd - st.n_tup_hot_upd) * (
        SELECT count(*)
        FROM pg_indexes
        WHERE tablename = st.relname
    ) * 8192 AS estimated_index_write_bytes
FROM pg_stat_user_tables st
WHERE st.schemaname = 'public'
    AND st.n_tup_upd > 0
ORDER BY st.relname;


-- ============================================================
-- Section 3: Inspecting HOT Chains with pageinspect
-- ============================================================

\echo '>>> Section 3: HOT Chain Inspection'

-- First, create some HOT updates to inspect
-- (make sure fillfactor < 100 first!)
SELECT pg_stat_reset();

-- Update non-indexed column to generate HOT chains
UPDATE user_sessions SET last_active = NOW() WHERE id <= 500;

-- Look for HOT chains on page 0: line pointers pointing to other offsets
-- If a line pointer's t_ctid points to a different offset on the SAME page,
-- that's a HOT chain.
SELECT
    lp AS line_pointer,
    t_xmin,
    t_xmax,
    (t_ctid).block AS ctid_block,
    (t_ctid).offset AS ctid_offset,
    t_len AS tuple_bytes,
    CASE
        WHEN (t_ctid).offset = lp THEN 'latest version (self-referencing)'
        WHEN (t_ctid).offset != lp THEN 'HOT chain → points to offset ' || (t_ctid).offset
    END AS chain_status
FROM heap_page_items(get_raw_page('user_sessions', 0))
ORDER BY lp
LIMIT 30;

-- ============================================================
-- Section 4: Page Space Analysis
-- ============================================================

\echo '>>> Section 4: Page Space Analysis'

-- How much free space exists per page?
-- With fillfactor=80, each page should have ~1600 bytes free
SELECT
    c.relname,
    c.relpages AS total_pages,
    pg_size_pretty(c.relpages * 8192) AS total_heap_size,
    CASE WHEN c.relpages > 0
        THEN pg_size_pretty((pg_relation_size(c.oid) / c.relpages)::bigint)
        ELSE 'N/A'
    END AS avg_page_size
FROM pg_class c
WHERE c.relname = 'user_sessions';

-- Use pg_freespacemap to see actual free space per page
CREATE EXTENSION IF NOT EXISTS pg_freespacemap;

SELECT
    blkno AS page_number,
    avail AS free_bytes,
    round(100.0 * avail / 8192, 1) AS free_pct
FROM pg_freespace('user_sessions')
WHERE avail > 0
ORDER BY blkno
LIMIT 20;


-- ============================================================
-- Section 5: Fillfactor Settings Across All Tables
-- ============================================================

\echo '>>> Section 5: Fillfactor Audit'

-- Check fillfactor for all user tables
SELECT
    c.relname AS table_name,
    COALESCE(
        substring(array_to_string(c.reloptions, ',') FROM 'fillfactor=(\d+)'),
        '100 (default)'
    ) AS fillfactor,
    pg_size_pretty(pg_relation_size(c.oid)) AS size,
    st.n_tup_upd,
    st.n_tup_hot_upd,
    CASE WHEN st.n_tup_upd > 0
        THEN round(100.0 * st.n_tup_hot_upd / st.n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables st ON st.relid = c.oid
WHERE n.nspname = 'public'
    AND c.relkind = 'r'
ORDER BY st.n_tup_upd DESC NULLS LAST;


-- ============================================================
-- Section 6: Correlation Between Updates and Index Count
-- ============================================================

\echo '>>> Section 6: Index Count vs HOT Benefit'

-- Show how many indexes each table has and its HOT ratio
SELECT
    st.relname,
    (SELECT count(*)
     FROM pg_indexes i
     WHERE i.tablename = st.relname
       AND i.schemaname = 'public'
    ) AS index_count,
    st.n_tup_upd AS total_updates,
    st.n_tup_hot_upd AS hot_updates,
    CASE WHEN st.n_tup_upd > 0
        THEN round(100.0 * st.n_tup_hot_upd / st.n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    (st.n_tup_upd - st.n_tup_hot_upd) *
    (SELECT count(*) FROM pg_indexes i WHERE i.tablename = st.relname)
    AS wasted_index_writes
FROM pg_stat_user_tables st
WHERE st.schemaname = 'public'
    AND st.n_tup_upd > 0
ORDER BY wasted_index_writes DESC;


-- ============================================================
-- Section 7: Current Transaction IDs on Tuples
-- ============================================================

\echo '>>> Section 7: Tuple Versioning (xmin/xmax)'

-- See xmin/xmax for first few rows to understand versioning
SELECT
    ctid,
    xmin,
    xmax,
    id,
    status,
    last_active
FROM user_sessions
WHERE ctid < '(1, 50)'
ORDER BY ctid
LIMIT 20;

-- Rows where xmax > 0 have been updated or deleted
-- (visible ones with xmax > 0 are from aborted transactions or
--  MVCC visibility where current transaction can still see them)
