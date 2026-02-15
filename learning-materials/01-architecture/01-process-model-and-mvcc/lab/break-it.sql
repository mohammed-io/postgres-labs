-- Break-it Lab: Cause Problems to Learn from Them

\echo '=== Break-it 1: Cause Transaction Wraparound Warning ==='

-- First, see current transaction ID age
SELECT
    txid_current() AS current_xid,
    age(txid_current()) AS current_age,
    (SELECT setting::int FROM pg_settings WHERE name = 'autovacuum_freeze_max_age') AS warning_threshold;

-- Explanation: Transaction IDs wrap around at 4 billion
-- Postgres must freeze old tuples to prevent wraparound
-- If autovacuum can't keep up, database stops accepting writes!

\echo ''
\echo '=== Break-it 2: Prevent Autovacuum from Running ==='

-- Disable autovacuum on a table (DANGEROUS!)
CREATE TABLE break_vacuum (
    id SERIAL,
    data TEXT
) WITH (autovacuum_enabled = false);

-- Insert data
INSERT INTO break_vacuum (data)
SELECT repeat('x', 1000) FROM generate_series(1, 1000);

-- Update everything (creates dead tuples)
UPDATE break_vacuum SET data = data || 'y';

-- Check: Dead tuples accumulate
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'break_vacuum';

-- Re-enable for cleanup
ALTER TABLE break_vacuum SET (autovacuum_enabled = true);

\echo ''
\echo '=== Break-it 3: Create a Long-Running Transaction ==='

-- Terminal 1: Run this and LEAVE IT OPEN
BEGIN;
SELECT * FROM mvcc_demo;
-- Don't commit! Check step-02.md for what happens...

\echo ''
\echo '=== Break-it 4: Exhaust Work Memory ==='

-- Create a query that needs more work_mem than available
SET work_mem = '64kB';

-- This should spill to disk (slow!)
SELECT *
FROM generate_series(1, 10000) AS s(x)
ORDER BY x DESC;

-- Check if it spilled
SELECT
    kind,
    context,
    space_used
FROM pg_stat_statements
WHERE query LIKE '%generate_series%';

-- Reset
SET work_mem = DEFAULT;

\echo ''
\echo '=== Cleanup ==='
DROP TABLE IF EXISTS break_vacuum;
\echo 'Tables cleaned up.'
