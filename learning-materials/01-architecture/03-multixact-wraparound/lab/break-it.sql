-- ============================================================
-- Break-It Lab: MultiXact ID Wraparound Failure Scenarios
-- ============================================================
-- WARNING: These scenarios intentionally stress the multixact
-- system. Run in this isolated Docker environment ONLY.
--
-- Each experiment uses dblink to create genuine multixacts
-- by simulating concurrent sessions locking the same rows.
-- A multixact is only created when TWO DIFFERENT transactions
-- hold locks on the same row simultaneously.
-- ============================================================

-- ============================================================
-- EXPERIMENT 1: Rapid MultiXact Accumulation
-- ============================================================
-- What breaks: mxid age climbs rapidly as multixacts are created
-- faster than autovacuum can freeze them.
-- Prerequisites: setup.sql has been run
-- ============================================================

\echo ''
\echo '=== EXPERIMENT 1: Rapid MultiXact Accumulation ==='
\echo 'Creating multixacts by locking many rows via dblink...'

-- Baseline check
SELECT mxid_age(datminmxid) AS mxid_age_before
FROM pg_database WHERE datname = 'labdb';

SELECT next_multixact_id::text::bigint AS next_mxid_before
FROM pg_control_checkpoint();

-- Use the procedure from setup.sql to create multixacts in bulk
-- Each iteration: dblink session locks row, current session locks
-- same row → genuine multixact created with [remote_XID, local_XID]
CALL create_multixact_batch('mxid_stress', 200);

-- Observe the result
SELECT next_multixact_id::text::bigint AS next_mxid_after
FROM pg_control_checkpoint();

SELECT mxid_age(datminmxid) AS mxid_age_after
FROM pg_database WHERE datname = 'labdb';

-- Expected: mxid_age has increased significantly
-- Each multixact consumes one 32-bit ID. At this rate, a busy
-- production system could hit warning threshold in weeks.

-- Per-table mxid age after accumulation
SELECT
    relname,
    relminmxid,
    mxid_age(relminmxid) AS mxid_age
FROM pg_class
WHERE relname IN ('mxid_stress', 'inventory', 'order_locks')
ORDER BY mxid_age(relminmxid) DESC;

-- Recovery (uncomment to fix):
-- VACUUM FREEZE mxid_stress;
-- VACUUM FREEZE inventory;
-- VACUUM FREEZE order_locks;


-- ============================================================
-- EXPERIMENT 2: Disable Autovacuum — Unbounded Growth
-- ============================================================
-- What breaks: Without autovacuum, multixacts are never frozen.
-- mxid age grows toward the 2-billion limit with no backpressure.
-- Prerequisites: setup.sql has been run
-- ============================================================

\echo ''
\echo '=== EXPERIMENT 2: Disable Autovacuum — Unbounded Growth ==='
\echo 'Disabling autovacuum on mxid_stress table...'

-- Step 1: Trigger — Disable autovacuum on the stress table
ALTER TABLE mxid_stress SET (autovacuum_enabled = false);

-- Step 2: Observe — autovacuum won't touch this table
SELECT
    relname,
    reloptions
FROM pg_class
WHERE relname = 'mxid_stress';

-- Step 3: Trigger — Create multixacts that will never be frozen
-- Even though other tables get autovacuum'd, this table blocks
-- the database-wide dat_minmxid from advancing.
DO $$
DECLARE
    v_conn TEXT;
    v_mxid_before BIGINT;
    v_mxid_after BIGINT;
    v_created INTEGER := 0;
BEGIN
    v_mxid_before := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());

    FOR i IN 1..100 LOOP
        v_conn := 'exp2_mxid_' || i;
        BEGIN
            PERFORM dblink_connect(v_conn, 'dbname=labdb');
            PERFORM dblink_exec(v_conn, 'BEGIN');

            PERFORM * FROM dblink(v_conn,
                format('SELECT 1 FROM mxid_stress WHERE id = %s FOR SHARE', (i % 200) + 1)
            ) AS t(dummy int);

            PERFORM * FROM mxid_stress WHERE id = (i % 200) + 1 FOR SHARE;

            PERFORM dblink_exec(v_conn, 'COMMIT');
            PERFORM dblink_disconnect(v_conn);
            v_created := v_created + 1;
        EXCEPTION WHEN OTHERS THEN
            BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
        END;
    END LOOP;

    v_mxid_after := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());
    RAISE NOTICE 'Created % mxids on a table with autovacuum disabled (total new mxids: %)',
        v_created, v_mxid_after - v_mxid_before;
END $$;

-- Step 4: Observe — The multixacts won't be frozen
-- Even if other tables get vacuumed, mxid_stress won't advance
-- its relminmxid, so dat_minmxid can't advance either.
SELECT
    c.relname,
    c.relminmxid,
    mxid_age(c.relminmxid) AS mxid_age,
    CASE WHEN c.relname = 'mxid_stress' THEN 'AUTOVACUUM OFF — age stays high' ELSE 'autovacuum active' END AS note
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('mxid_stress', 'inventory')
    AND n.nspname = 'public'
ORDER BY mxid_age(c.relminmxid) DESC;

-- Expected: mxid_stress shows high mxid_age that won't decrease
-- In production, this single table blocks freeze for the whole DB.

-- Recovery (uncomment to fix):
-- ALTER TABLE mxid_stress SET (autovacuum_enabled = true);
-- VACUUM FREEZE mxid_stress;


-- ============================================================
-- EXPERIMENT 3: Long-Running Transaction Blocking Freeze
-- ============================================================
-- What breaks: A long-running transaction prevents VACUUM from
-- freezing old multixacts because it might still need to resolve
-- them. mxid age grows even though autovacuum is trying to help.
-- Prerequisites: setup.sql has been run
-- ============================================================

\echo ''
\echo '=== EXPERIMENT 3: Long-Running Transaction Blocking Freeze ==='
\echo 'Starting a long-running transaction that holds old mxids...'

-- Step 1: Trigger — Create multixacts first using dblink
DO $$
DECLARE
    v_conn TEXT;
BEGIN
    FOR i IN 1..20 LOOP
        v_conn := 'exp3_seed_' || i;
        BEGIN
            PERFORM dblink_connect(v_conn, 'dbname=labdb');
            PERFORM dblink_exec(v_conn, 'BEGIN');

            PERFORM * FROM dblink(v_conn,
                format('SELECT 1 FROM long_lock_demo WHERE id = %s FOR SHARE', i)
            ) AS t(dummy int);

            PERFORM * FROM long_lock_demo WHERE id = i FOR SHARE;

            PERFORM dblink_exec(v_conn, 'COMMIT');
            PERFORM dblink_disconnect(v_conn);
        EXCEPTION WHEN OTHERS THEN
            BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
        END;
    END LOOP;
END $$;

-- Step 2: Trigger — Start a long-running transaction
-- This transaction doesn't need to do anything — just existing
-- prevents vacuum from freezing mxids older than its snapshot.
BEGIN;
SELECT * FROM long_lock_demo LIMIT 1;
-- This transaction is now "active" and holds a snapshot
-- DO NOT COMMIT — this simulates an abandoned connection

-- Step 3: Observe — in a separate session, try to freeze
-- Run this in another terminal to see the problem:
--   docker exec pg-multixact psql -U postgres -d labdb -c "VACUUM FREEZE long_lock_demo;"
--
-- The VACUUM will run but won't be able to advance relminmxid
-- because our long-running transaction might still need the old mxids.

-- Check for blocking transactions
SELECT
    pid,
    NOW() - xact_start AS transaction_age,
    state,
    LEFT(query, 60) AS query_preview
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
    AND pid != pg_backend_pid()
    AND NOW() - xact_start > INTERVAL '1 second'
ORDER BY xact_start;

-- Expected: You should see at least one "active" transaction
-- that has been running for several seconds. While it exists,
-- multixact freeze cannot advance dat_minmxid past the mxids
-- that were visible when this transaction started.

-- Recovery (uncomment to fix):
-- First, commit or terminate the long-running transaction above:
-- COMMIT;
--
-- Then freeze:
-- VACUUM FREEZE long_lock_demo;
--
-- Or terminate from another session:
-- SELECT pg_terminate_backend(pid)
-- FROM pg_stat_activity
-- WHERE state = 'idle in transaction'
--     AND NOW() - xact_start > INTERVAL '5 minutes';

-- Commit the long transaction to allow cleanup
COMMIT;

\echo ''
\echo '=== Cleanup: Re-enable Autovacuum and Freeze ==='

-- Re-enable autovacuum on mxid_stress
ALTER TABLE mxid_stress SET (autovacuum_enabled = true);

-- Freeze all tables to reset mxid age
VACUUM FREEZE mxid_stress;
VACUUM FREEZE inventory;
VACUUM FREEZE order_locks;
VACUUM FREEZE shared_resources;
VACUUM FREEZE long_lock_demo;

-- Verify cleanup
SELECT
    datname,
    mxid_age(datminmxid) AS mxid_age_after_cleanup,
    age(datfrozenxid) AS xid_age_after_cleanup
FROM pg_database
WHERE datname = 'labdb';

\echo ''
\echo 'Experiments complete. All tables re-enabled and frozen.'
