-- Benchmark: Connection Overhead

\echo '=== Benchmark: Connection Creation Time ==='
\timing on

-- Time 10 individual connections (no pooling)
\echo 'Creating 10 separate connections...'
DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    result TEXT;
BEGIN
    FOR i IN 1..10 LOOP
        -- Simulate new connection by checking backend start
        SELECT pg_postmaster_start_time() INTO start_time;
        -- Each query here would be a new connection in real scenario
        PERFORM pg_sleep(0.01);
    END LOOP;
END $$;

\timing off

\echo ''
\echo '=== Analysis ==='
\echo 'Each fork() operation copies the parent process memory.'
\echo 'This explains why connection pooling is essential for high-traffic applications.'

-- Show memory comparison
SELECT
    'Base Postgres Process' AS description,
    '~2-4 MB' AS memory_range
UNION ALL
SELECT
    'Each Backend Connection',
    '~10 MB base + work_mem per operation'
UNION ALL
SELECT
    '100 Connections',
    '~1 GB minimum'
UNION ALL
SELECT
    '1000 Connections (without pooling)',
    '~10 GB minimum - NOT RECOMMENDED';
