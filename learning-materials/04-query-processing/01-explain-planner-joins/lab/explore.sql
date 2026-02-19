-- Inspect row counts and stats
SELECT relname, n_live_tup
FROM pg_stat_user_tables
WHERE schemaname = 'public';

-- Baseline plan
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.region, SUM(o.amount)
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE o.created_at > NOW() - INTERVAL '30 days'
GROUP BY c.region;
