\timing on

-- =====================================================================
-- REPLICATION BENCHMARK SUITE
-- Tests performance and replication lag under various workloads
-- =====================================================================

-- =====================================================================
-- TEST 1: Baseline Write Performance (No replication pressure)
-- =====================================================================

SELECT 'TEST 1: Baseline Write Performance' AS test;

EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY)
INSERT INTO ledger (account_id, amount, kind)
SELECT 
    (floor(random() * 1000) + 1)::int,
    (random() * 100)::numeric(12,2),
    CASE WHEN random() > 0.5 THEN 'credit' ELSE 'debit' END
FROM generate_series(1, 1000);

-- =====================================================================
-- TEST 2: Bulk Insert - Watch Replication Lag
-- =====================================================================

SELECT 'TEST 2: Bulk Insert (monitor lag on replicas)' AS test;

-- Before: Check current lag
SELECT 'BEFORE' AS phase, 
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Bulk insert
INSERT INTO ledger (account_id, amount, kind)
SELECT 
    (floor(random() * 1000) + 1)::int,
    (random() * 500)::numeric(12,2),
    'credit'
FROM generate_series(1, 50000);

-- Immediately after
SELECT 'AFTER_INSERT' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Wait 2 seconds and check again
SELECT pg_sleep(2);

SELECT 'AFTER_2SEC' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- =====================================================================
-- TEST 3: Concurrent Write + Read Pattern
-- =====================================================================

SELECT 'TEST 3: Concurrent Write/Read' AS test;

-- Simulate OLTP pattern
DO $$
BEGIN
    FOR i IN 1..100 LOOP
        -- Write
        INSERT INTO ledger (account_id, amount, kind)
        VALUES ((floor(random() * 1000) + 1)::int, random() * 100, 'credit');
        
        -- Read
        PERFORM * FROM accounts WHERE id = (floor(random() * 1000) + 1)::int;
        
        -- Update
        UPDATE accounts SET balance = balance + (random() * 10)::numeric(12,2) 
        WHERE id = (floor(random() * 1000) + 1)::int;
        
        COMMIT;
    END LOOP;
END;
$$;

-- =====================================================================
-- TEST 4: Index Impact on Replication
-- =====================================================================

SELECT 'TEST 4: Index Creation During Replication' AS test;

-- Check lag before
SELECT 'BEFORE_INDEX' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Create index (generates WAL)
CREATE INDEX IF NOT EXISTS idx_ledger_created_at ON ledger(created_at);

-- Check lag after
SELECT 'AFTER_INDEX' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Drop index (cleanup)
DROP INDEX IF EXISTS idx_ledger_created_at;

-- =====================================================================
-- TEST 5: Vacuum Impact
-- =====================================================================

SELECT 'TEST 5: Vacuum During Replication' AS test;

-- Generate some dead tuples
DELETE FROM ledger WHERE id % 100 = 0;

-- Check lag before vacuum
SELECT 'BEFORE_VACUUM' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Vacuum
VACUUM ANALYZE ledger;

-- Check lag after
SELECT 'AFTER_VACUUM' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- =====================================================================
-- TEST 6: Transaction Size Impact
-- =====================================================================

SELECT 'TEST 6: Large vs Small Transactions' AS test;

-- Single large transaction
SELECT 'LARGE_TX_START' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

BEGIN;
INSERT INTO ledger (account_id, amount, kind)
SELECT (floor(random() * 1000) + 1)::int, random() * 100, 'credit'
FROM generate_series(1, 10000);
COMMIT;

SELECT 'LARGE_TX_END' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Many small transactions (same total rows)
SELECT 'SMALL_TX_START' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

DO $$
BEGIN
    FOR i IN 1..100 LOOP
        INSERT INTO ledger (account_id, amount, kind)
        SELECT (floor(random() * 1000) + 1)::int, random() * 100, 'credit'
        FROM generate_series(1, 100);
        COMMIT;
    END LOOP;
END;
$$;

SELECT 'SMALL_TX_END' AS phase,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- =====================================================================
-- TEST 7: Replication Slot Retention Check
-- =====================================================================

SELECT 'TEST 7: Slot Retention' AS test;

-- Check how much WAL is being retained
SELECT 
    slot_name,
    active,
    restart_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained
FROM pg_replication_slots;

-- =====================================================================
-- TEST 8: Read Performance on Replica (Run on Replica)
-- =====================================================================

-- Run this section ON THE REPLICA
-- SELECT 'TEST 8: Replica Read Performance' AS test;
-- 
-- EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY)
-- SELECT account_id, SUM(amount)
-- FROM ledger
-- GROUP BY account_id
-- ORDER BY SUM(amount) DESC
-- LIMIT 20;

-- =====================================================================
-- SUMMARY: Final State
-- =====================================================================

SELECT 'SUMMARY' AS section;

SELECT 
    'accounts' AS table_name, 
    COUNT(*) AS rows,
    pg_size_pretty(pg_total_relation_size('accounts')) AS size
FROM accounts
UNION ALL
SELECT 
    'ledger', 
    COUNT(*),
    pg_size_pretty(pg_total_relation_size('ledger'))
FROM ledger;

-- Final replication state
SELECT 
    application_name AS replica,
    state,
    sync_state,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag
FROM pg_stat_replication;
