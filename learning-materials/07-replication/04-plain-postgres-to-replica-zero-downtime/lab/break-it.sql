-- Break-it experiments (run intentionally in a throwaway environment)
-- These simulate real-world failure scenarios to understand replication behavior

-- =====================================================================
-- EXPERIMENT 1: WAL Recycling - What happens when WAL is removed before replica catches up?
-- =====================================================================
-- Prerequisites: Primary must have replication configured, replica exists

-- Step 1: Check current WAL situation
SELECT pg_current_wal_lsn() AS current_lsn, 
       pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;

-- Step 2: Dramatically reduce WAL retention (DANGEROUS - only in lab!)
ALTER SYSTEM SET wal_keep_size = '16MB';
SELECT pg_reload_conf();

-- Step 3: Generate heavy write load to force WAL recycling
-- Run this in another session or as a separate script:
-- INSERT INTO ledger (account_id, amount, kind)
-- SELECT (floor(random() * 1000) + 1)::int, (random() * 1000)::numeric(12,2), 'credit'
-- FROM generate_series(1, 100000);

-- Step 4: Check if replica can still connect
-- On replica: SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
-- If WAL was recycled, replica will show error in logs: "requested WAL segment has been removed"

-- Cleanup: Restore safe value
-- ALTER SYSTEM SET wal_keep_size = '1GB';
-- SELECT pg_reload_conf();


-- =====================================================================
-- EXPERIMENT 2: Replication Slot Overflow - Run out of slots
-- =====================================================================

-- Check current slot usage
SELECT slot_name, slot_type, active, restart_lsn 
FROM pg_replication_slots;

-- Create slots until we hit the limit (default max_replication_slots = 10)
-- SELECT pg_create_physical_replication_slot('break_slot_' || i) 
-- FROM generate_series(1, 15) AS s(i);

-- Expected error: "all replication slots are in use"

-- Cleanup unused slots
-- SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE NOT active;


-- =====================================================================
-- EXPERIMENT 3: pg_hba.conf Denial - Block replication connections
-- =====================================================================

-- This requires shell access. Simulate by commenting out replication rules:
-- docker exec -it pg-plain-primary sed -i 's/^host replication/#host replication/' "$PGDATA/pg_hba.conf"
-- docker exec -it pg-plain-primary psql -U postgres -c "SELECT pg_reload_conf();"

-- Then try to connect from replica:
-- docker exec -it pg-plain-replica-1 psql -h postgres-primary -U replicator -d appdb

-- Expected: "no pg_hba.conf entry for replication connection"

-- Recovery: Uncomment the rules and reload


-- =====================================================================
-- EXPERIMENT 4: Network Partition Simulation
-- =====================================================================

-- Simulate using iptables inside container (requires privileged mode)
-- docker exec -it pg-plain-replica-1 iptables -A INPUT -s pg-plain-primary -j DROP
-- docker exec -it pg-plain-replica-1 iptables -A OUTPUT -d pg-plain-primary -j DROP

-- Watch replication lag grow:
-- On primary:
SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- On replica:
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;

-- Recovery: Clear iptables rules
-- docker exec -it pg-plain-replica-1 iptables -F


-- =====================================================================
-- EXPERIMENT 5: Promote Wrong Replica (Split-Brain Scenario)
-- =====================================================================

-- WARNING: This creates two primaries accepting writes!
-- Only do this in isolated lab environment

-- Promote replica-1 while primary is still up:
-- docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data

-- Now write to both:
-- On old primary: INSERT INTO accounts (owner, balance) VALUES ('split_brain_primary', 100);
-- On new primary (promoted replica-1): INSERT INTO accounts (owner, balance) VALUES ('split_brain_replica', 200);

-- Check divergence - these will differ:
-- On each node: SELECT COUNT(*) FROM accounts;

-- Recovery: Choose one source of truth, rebuild the other from scratch


-- =====================================================================
-- EXPERIMENT 6: Query Conflicts on Replica
-- =====================================================================

-- Long-running query on replica that conflicts with primary's vacuum/DDL

-- On replica, start a long transaction:
-- BEGIN;
-- SELECT * FROM ledger FOR UPDATE;
-- Don't commit yet

-- On primary, try to:
-- TRUNCATE TABLE ledger;

-- Replica will show conflict in logs
-- Check: SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Replication';


-- =====================================================================
-- EXPERIMENT 7: Disk Full on Replica
-- =====================================================================

-- Simulate by filling up replica's data volume
-- dd if=/dev/zero of=/var/lib/postgresql/data/junk bs=1M count=1000

-- Watch replica halt with "no space left on device" error
-- SELECT pg_is_in_recovery(); -- will still work
-- But WAL replay stops

-- Recovery: Remove junk file, WAL replay resumes automatically


-- =====================================================================
-- HELPER: Monitor replication health During Experiments
-- =====================================================================

-- On primary: Check connected replicas
SELECT 
    application_name,
    state,
    sync_state,
    sent_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_size
FROM pg_stat_replication;

-- On replica: Check recovery status
SELECT 
    pg_is_in_recovery() AS is_standby,
    pg_last_wal_receive_lsn() AS received_lsn,
    pg_last_wal_replay_lsn() AS replayed_lsn,
    pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_lag_bytes,
    now() - pg_last_xact_replay_timestamp() AS time_since_last_replay;

-- Check for replication slots (protects against WAL recycling)
SELECT slot_name, slot_type, active, restart_lsn, 
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS wal_retained_bytes
FROM pg_replication_slots;
