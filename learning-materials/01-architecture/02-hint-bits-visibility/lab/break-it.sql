-- Break-it Lab: Hint Bit Edge Cases and Failure Scenarios

\echo '=== EXPERIMENT 1: VACUUM FULL Resets Hint Bit State ==='
\echo 'What breaks: VACUUM FULL rewrites the table, creating entirely new pages.'
\echo 'All hint bits are lost on the new pages, triggering a hint bit storm on next read.'
\echo '====================================='

-- Create a table with hint bits already set
CREATE TABLE break_vacuum_full (
    id serial PRIMARY KEY,
    data text NOT NULL
);

INSERT INTO break_vacuum_full (data)
SELECT 'row-' || i || '-' || repeat('x', 80) FROM generate_series(1, 1000) AS i;

-- Read to set hint bits
SELECT count(*) FROM break_vacuum_full;

-- Verify hint bits are set
\echo '--- Before VACUUM FULL: hint bit status ---'
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS pct
FROM heap_page_items(get_raw_page('break_vacuum_full', 0))
WHERE t_xmin IS NOT NULL;

-- Step 1: Trigger VACUUM FULL (rewrites the table)
VACUUM FULL break_vacuum_full;

-- Step 2: Observe - hint bits are now gone!
\echo '--- After VACUUM FULL: hint bit status ---'
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS pct
FROM heap_page_items(get_raw_page('break_vacuum_full', 0))
WHERE t_xmin IS NOT NULL;

-- Expected: pct drops dramatically. VACUUM FULL creates new pages with new tuples.
-- The new tuples have t_xmin set but hint bits are NOT set yet.

-- Step 3: Measure the cost of re-reading (hint bit storm!)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT count(*) FROM break_vacuum_full;

-- Recovery: Read the table once to set hint bits again
-- (Already done by the SELECT count(*) above)

\echo ''
\echo '=== EXPERIMENT 2: Massive INSERT in Single Transaction ==='
\echo 'What breaks: All rows share the same t_xmin. Hint bits are NOT set until first read.'
\echo 'On first read, Postgres must look up ONE transaction in CLOG, then set hint bits'
\echo 'for ALL tuples. This still dirties every page containing these tuples.'
\echo '====================================='

-- Step 1: Massive single-transaction INSERT
CREATE TABLE break_bulk_insert (
    id serial PRIMARY KEY,
    payload text NOT NULL,
    batch_id integer NOT NULL
);

BEGIN;
INSERT INTO break_bulk_insert (payload, batch_id)
SELECT repeat('x', 200), 1 FROM generate_series(1, 50000);
COMMIT;

-- Step 2: Check hint bits (all should be missing)
\echo '--- Hint bits before first read ---'
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS hints_missing,
    count(DISTINCT t_xmin) AS distinct_xmin_values
FROM heap_page_items(get_raw_page('break_bulk_insert', 0))
WHERE t_xmin IS NOT NULL;

-- Expected: hints_missing = total_tuples. All rows have the same xmin.
-- Only ONE CLOG lookup is needed, but EVERY page gets dirtied.

-- Step 3: Measure the dirtying cost
\echo '--- First read (setting hint bits, dirtying pages) ---'
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT count(*) FROM break_bulk_insert;

-- Note: shared dirtied=N in the output. This shows how many pages
-- had hint bits set (dirtying them for future checkpoint writes).

-- Step 4: Verify all hint bits are now set
\echo '--- Hint bits after first read ---'
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS hints_missing
FROM heap_page_items(get_raw_page('break_bulk_insert', 0))
WHERE t_xmin IS NOT NULL;

-- Recovery: First read already set all hint bits.

\echo ''
\echo '=== EXPERIMENT 3: Long-Running Transaction Prevents Hint Bit Optimization ==='
\echo 'What breaks: A long-running transaction holds a snapshot that prevents'
\echo 'VACUUM from fully processing pages. New tuples created AFTER the snapshot'
\echo 'cannot have their hint bits set by VACUUM until the transaction ends.'
\echo '====================================='

-- Create test table
CREATE TABLE break_long_xact (
    id serial PRIMARY KEY,
    data text NOT NULL,
    version integer DEFAULT 1
);

INSERT INTO break_long_xact (data)
SELECT 'initial-' || i FROM generate_series(1, 500) AS i;

-- Set hint bits by reading
SELECT count(*) FROM break_long_xact;

-- Step 1: Open a long-running transaction
\echo '--- Opening long-running transaction ---'
BEGIN;
-- This takes a snapshot. Any VACUUM after this cannot process
-- tuples newer than this snapshot.
SELECT txid_current() AS long_xact_xid;
-- DO NOT COMMIT YET (in real scenario, this stays open)

-- In a separate session, you would:
-- INSERT INTO break_long_xact (data) VALUES ('new-row');

-- For this demo, we'll do it in the same session
-- (In production, the blocking happens cross-session)
INSERT INTO break_long_xact (data) VALUES ('added-during-long-xact');

-- Step 2: Check which tuples can't get hint bits from vacuum
\echo '--- All tuples including new one ---'
SELECT
    id,
    data,
    xmin,
    CASE WHEN xmin::text::bigint < pg_snapshot_xmin(pg_current_snapshot()) THEN 'old' ELSE 'new' END AS age_class
FROM break_long_xact
ORDER BY id DESC
LIMIT 5;

-- Step 3: Try vacuum (it will run but can't fully process new tuples)
COMMIT;  -- End the long transaction first

VACUUM break_long_xact;

-- Step 4: After the long transaction ends, vacuum can now set all hint bits
\echo '--- After long transaction ended and vacuum ran ---'
SELECT
    count(*) AS total,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS hints_set,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / nullif(count(*), 0), 1) AS pct
FROM heap_page_items(get_raw_page('break_long_xact', 0))
WHERE t_xmin IS NOT NULL;

-- Recovery: The COMMIT above ended the transaction, and VACUUM cleaned up.

\echo ''
\echo '=== EXPERIMENT 4: Disable wal_log_hints and Observe ==='
\echo 'What breaks: Without wal_log_hints, pg_rewind cannot work after failover.'
\echo 'This experiment shows the configuration check.'
\echo '====================================='

-- Step 1: Check current setting
\echo '--- Current wal_log_hints setting ---'
SHOW wal_log_hints;

-- Step 2: What happens if it's off (don't actually change it in this lab)
-- If wal_log_hints = off:
--   - Hint bit changes are NOT logged to WAL
--   - Replicas don't receive hint bit updates
--   - After failover, pg_rewind cannot reconcile differences
--   - You must re-pg_basebackup instead

-- Step 3: Simulate checking if pg_rewind is possible
-- (In a real setup with replication, this would fail without wal_log_hints)
\echo '--- Checking if pg_rewind would work ---'
SELECT
    CASE
        WHEN current_setting('wal_log_hints') = 'on' THEN 'OK: pg_rewind is supported'
        ELSE 'DANGER: pg_rewind will NOT work. Enable wal_log_hints = on and restart.'
    END AS rewind_status;

-- Recovery: Our lab has wal_log_hints = on, so this is fine.

\echo ''
\echo '=== Cleanup ==='
DROP TABLE IF EXISTS break_vacuum_full;
DROP TABLE IF EXISTS break_bulk_insert;
DROP TABLE IF EXISTS break_long_xact;
\echo 'Tables cleaned up.'
