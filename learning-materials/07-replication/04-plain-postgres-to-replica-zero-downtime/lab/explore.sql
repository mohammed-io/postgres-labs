-- Explore current role and recovery status
SELECT pg_is_in_recovery() AS is_replica;

-- On primary, this should show replica senders after bootstrap
SELECT * FROM pg_stat_replication;

-- On replica, this should show replay progress
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
