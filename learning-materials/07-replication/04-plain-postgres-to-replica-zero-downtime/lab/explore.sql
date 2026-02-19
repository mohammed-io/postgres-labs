-- =====================================================================
-- REPLICATION EXPLORATION QUERIES
-- Use these to understand your replication setup
-- =====================================================================

-- =====================================================================
-- Explore: Server Role
-- =====================================================================

-- Is this server a primary or replica?
SELECT 
    pg_is_in_recovery() AS is_replica,
    CASE WHEN pg_is_in_recovery() THEN 'REPLICA (Standby)' ELSE 'PRIMARY (Read/Write)' END AS role;

-- =====================================================================
-- Explore: On PRIMARY - Connected Replicas
-- =====================================================================

-- Detailed view of connected replicas
SELECT 
    application_name AS replica_name,
    client_addr AS replica_ip,
    state AS connection_state,
    sync_state,
    sent_lsn AS primary_sent,
    write_lsn AS replica_written,
    flush_lsn AS replica_flushed,
    replay_lsn AS replica_applied,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag_human
FROM pg_stat_replication;

-- What does each LSN mean?
-- sent_lsn:    Primary sent this WAL position
-- write_lsn:   Replica wrote to OS cache
-- flush_lsn:   Replica fsynced to disk  
-- replay_lsn:  Replica applied to data files (this is what matters!)

-- =====================================================================
-- Explore: On PRIMARY - Replication Slots
-- =====================================================================

-- Check replication slots (CRITICAL for avoiding WAL recycling)
SELECT 
    slot_name,
    slot_type,
    active,
    restart_lsn,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS wal_bytes_retained,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained
FROM pg_replication_slots
ORDER BY slot_name;

-- WARNING: Inactive slots retain WAL forever!
-- This can fill up your disk if a replica is down for long
SELECT 'WARNING: Inactive slot retaining WAL!' AS alert
WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE NOT active);

-- =====================================================================
-- Explore: On REPLICA - WAL Receiver Status
-- =====================================================================

-- Connection to primary
SELECT 
    status,
    sender_host,
    sender_port,
    received_lsn,
    latest_end_lsn,
    slot_name
FROM pg_stat_wal_receiver;

-- WAL receive vs replay progress
SELECT 
    pg_last_wal_receive_lsn() AS received_from_primary,
    pg_last_wal_replay_lsn() AS applied_to_data,
    pg_wal_lsn_diff(
        pg_last_wal_receive_lsn(), 
        pg_last_wal_replay_lsn()
    ) AS replay_queue_bytes;

-- Time since last transaction was replayed
SELECT 
    pg_last_xact_replay_timestamp() AS last_replay_time,
    now() - pg_last_xact_replay_timestamp() AS time_since_replay,
    CASE 
        WHEN now() - pg_last_xact_replay_timestamp() < interval '1 second' THEN 'CAUGHT UP'
        WHEN now() - pg_last_xact_replay_timestamp() < interval '1 minute' THEN 'SLIGHT LAG'
        ELSE 'SIGNIFICANT LAG'
    END AS status;

-- =====================================================================
-- Explore: WAL Configuration
-- =====================================================================

-- Current WAL-related settings
SELECT name, setting, source, short_desc
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders', 
    'max_replication_slots',
    'wal_keep_size',
    'wal_sender_delay',
    'wal_compression',
    'synchronous_commit',
    'synchronous_standby_names'
)
ORDER BY name;

-- =====================================================================
-- Explore: Current WAL Position
-- =====================================================================

-- Where is WAL currently writing?
SELECT 
    pg_current_wal_lsn() AS current_lsn,
    pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file,
    pg_walfile_name_offset(pg_current_wal_lsn()) AS file_and_offset;

-- =====================================================================
-- Explore: Replication Protocol Details
-- =====================================================================

-- What version of replication protocol?
SELECT pg_control_system() AS pg_version;

-- Available replication slots vs configured max
SELECT 
    current_setting('max_replication_slots')::int AS max_slots,
    (SELECT COUNT(*) FROM pg_replication_slots) AS used_slots,
    current_setting('max_replication_slots')::int - (SELECT COUNT(*) FROM pg_replication_slots) AS available_slots;

-- =====================================================================
-- Explore: Data Files and WAL
-- =====================================================================

-- How much WAL is being generated? (run before and after activity)
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS total_wal_bytes;

-- WAL directory size (shell command):
-- docker exec -it pg-plain-primary du -sh $PGDATA/pg_wal

-- =====================================================================
-- Explore: Understanding LSN (Log Sequence Number)
-- =====================================================================

-- LSN is PostgreSQL's way of tracking position in WAL
-- Format: X/Y where X is segment number, Y is offset within segment

-- Convert LSN to human-readable
SELECT 
    '0/16B7F48'::pg_lsn AS example_lsn,
    pg_walfile_name('0/16B7F48'::pg_lsn) AS filename;

-- Each WAL segment is typically 16MB
-- X increments by 1 for each segment = 16MB

-- =====================================================================
-- Explore: Replication Lag Scenarios
-- =====================================================================

-- Common causes of replication lag:
-- 1. Network bandwidth saturation
-- 2. Disk I/O bottleneck on replica
-- 3. Long-running queries on replica (conflicts with replay)
-- 4. Primary generating WAL faster than replica can consume

-- Check for replication conflicts on replica:
SELECT 
    datname,
    conflict_type,
    conflicts_count
FROM pg_stat_database_conflicts
WHERE conflicts_count > 0;

-- =====================================================================
-- Explore: Recovery Settings (On Replica)
-- =====================================================================

-- What's in postgresql.auto.conf (set by pg_basebackup -R)?
-- docker exec -it pg-plain-replica-1 cat $PGDATA/postgresql.auto.conf

-- Check for standby.signal file (marks as standby)
-- docker exec -it pg-plain-replica-1 ls -la $PGDATA/standby.signal
