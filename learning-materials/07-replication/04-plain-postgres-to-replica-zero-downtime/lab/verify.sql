-- Run on primary
SELECT 'replication_settings' AS section;
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;

SELECT 'replication_clients' AS section;
SELECT application_name, state, sync_state FROM pg_stat_replication;

SELECT 'data_check' AS section;
SELECT COUNT(*) AS accounts, (SELECT COUNT(*) FROM ledger) AS ledger_rows FROM accounts;
