-- Break-it experiments (run intentionally in a throwaway environment)

-- 1) Disable replication access rule and observe replica bootstrap failure
-- (Edit pg_hba.conf and remove replication lines, then reload config)

-- 2) Set wal_keep_size very low and generate heavy writes to observe replay problems
-- ALTER SYSTEM SET wal_keep_size = '16MB';
-- SELECT pg_reload_conf();

SELECT 'Use this file to create controlled failure scenarios.' AS note;
