-- =====================================================================
-- REPLICATION VERIFICATION SUITE
-- Run sections as needed during the lab
-- =====================================================================

-- =====================================================================
-- SECTION 1: Primary Configuration Check
-- Run on: Primary only
-- =====================================================================

SELECT 'primary_config' AS section;

-- Core replication settings
SELECT name, setting, source 
FROM pg_settings 
WHERE name IN ('wal_level', 'max_wal_senders', 'max_replication_slots', 'wal_keep_size', 
               'synchronous_commit', 'synchronous_standby_names')
ORDER BY name;

-- Show as simple values
SELECT 'wal_level' AS setting, current_setting('wal_level') AS value
UNION ALL SELECT 'max_wal_senders', current_setting('max_wal_senders')
UNION ALL SELECT 'max_replication_slots', current_setting('max_replication_slots')
UNION ALL SELECT 'wal_keep_size', current_setting('wal_keep_size');

-- =====================================================================
-- SECTION 2: Replication Slots Check
-- Run on: Primary
-- =====================================================================

SELECT 'replication_slots' AS section;

SELECT 
    slot_name,
    slot_type,
    active,
    restart_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS wal_retained_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained_size
FROM pg_replication_slots
ORDER BY slot_name;

-- Warning: Inactive slots retain WAL indefinitely!
SELECT 'WARNING: Inactive slots retain WAL forever!' AS note
WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE NOT active);

-- =====================================================================
-- SECTION 3: Connected Replicas
-- Run on: Primary
-- =====================================================================

SELECT 'connected_replicas' AS section;

SELECT 
    application_name AS replica_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_size,
    backend_start
FROM pg_stat_replication
ORDER BY application_name;

-- Quick health check
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN 'NO REPLICAS CONNECTED'
        WHEN COUNT(*) < 2 THEN 'WARNING: Only ' || COUNT(*) || ' replica(s)'
        ELSE 'OK: ' || COUNT(*) || ' replicas connected'
    END AS status
FROM pg_stat_replication;

-- =====================================================================
-- SECTION 4: Replica Status
-- Run on: Replica
-- =====================================================================

SELECT 'replica_status' AS section;

-- Is this server a replica?
SELECT 
    pg_is_in_recovery() AS is_replica,
    CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END AS role;

-- WAL receive/replay progress
SELECT 
    pg_last_wal_receive_lsn() AS received_lsn,
    pg_last_wal_replay_lsn() AS replayed_lsn,
    pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) AS replay_lag_size;

-- Time since last replay
SELECT 
    now() - pg_last_xact_replay_timestamp() AS time_since_last_replay,
    CASE 
        WHEN now() - pg_last_xact_replay_timestamp() < interval '1 second' THEN 'CAUGHT UP'
        WHEN now() - pg_last_xact_replay_timestamp() < interval '10 seconds' THEN 'SLIGHT LAG'
        ELSE 'SIGNIFICANT LAG'
    END AS status;

-- Connection to primary
SELECT * FROM pg_stat_wal_receiver;

-- =====================================================================
-- SECTION 5: Data Consistency Check
-- Run on: Both Primary and Replica (compare results)
-- =====================================================================

SELECT 'data_consistency' AS section;

SELECT 'accounts' AS table_name, COUNT(*) AS rows FROM accounts
UNION ALL
SELECT 'ledger', COUNT(*) FROM ledger;

-- Checksum comparison (run on both, should match)
SELECT 
    md5(string_agg(id::text || owner || balance::text, '' ORDER BY id)) AS accounts_checksum
FROM accounts;

SELECT 
    md5(string_agg(id::text || account_id::text || amount::text, '' ORDER BY id)) AS ledger_checksum
FROM ledger;

-- =====================================================================
-- SECTION 6: After Promotion Check
-- Run on: Promoted replica (new primary)
-- =====================================================================

SELECT 'after_promotion' AS section;

-- Confirm promotion succeeded
SELECT 
    pg_is_in_recovery() AS still_in_recovery,
    CASE WHEN pg_is_in_recovery() THEN 'ERROR: Still a replica!' ELSE 'OK: Now primary' END AS status;

-- Check if replicas exist (if you reconfigured them)
SELECT application_name, state, sync_state FROM pg_stat_replication;

-- Verify write capability
CREATE TABLE IF NOT EXISTS promotion_test (id serial PRIMARY KEY, created_at timestamptz DEFAULT now());
INSERT INTO promotion_test DEFAULT VALUES;
SELECT * FROM promotion_test ORDER BY id DESC LIMIT 1;
DROP TABLE promotion_test;

-- =====================================================================
-- SECTION 7: Replication Lag Deep Dive
-- Run on: Primary (for replica lag) or Replica (for replay lag)
-- =====================================================================

SELECT 'lag_analysis' AS section;

-- On primary: Detailed lag per replica
SELECT 
    application_name,
    pg_wal_lsn_diff(sent_lsn, write_lsn) AS network_lag_bytes,
    pg_wal_lsn_diff(write_lsn, flush_lsn) AS flush_lag_bytes,
    pg_wal_lsn_diff(flush_lsn, replay_lsn) AS replay_lag_bytes,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS total_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS total_lag_size
FROM pg_stat_replication;

-- On replica: Current WAL position vs received
SELECT 
    pg_current_wal_lsn() AS current_wal,
    pg_last_wal_receive_lsn() AS received_wal,
    pg_last_wal_replay_lsn() AS replayed_wal;

-- =====================================================================
-- SECTION 8: Quick Health Summary
-- Run on: Primary
-- =====================================================================

SELECT 'health_summary' AS section;

WITH primary_stats AS (
    SELECT 
        current_setting('wal_level') AS wal_level,
        (SELECT COUNT(*) FROM pg_replication_slots) AS slots_count,
        (SELECT COUNT(*) FROM pg_replication_slots WHERE active) AS active_slots,
        (SELECT COUNT(*) FROM pg_stat_replication) AS replicas_count
)
SELECT 
    CASE 
        WHEN wal_level NOT IN ('replica', 'logical') THEN 'FAIL: wal_level=' || wal_level
        WHEN slots_count = 0 THEN 'WARN: No replication slots (risk of WAL recycling)'
        WHEN replicas_count = 0 THEN 'WARN: No replicas connected'
        WHEN active_slots < replicas_count THEN 'WARN: Some slots inactive'
        ELSE 'OK: Replication healthy'
    END AS status,
    wal_level,
    slots_count AS slots,
    active_slots AS active_slots,
    replicas_count AS connected_replicas
FROM primary_stats;
