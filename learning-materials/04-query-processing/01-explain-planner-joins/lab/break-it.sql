-- Intentionally degrade planner choices for learning
SET LOCAL random_page_cost = 8;
SET LOCAL work_mem = '64kB';

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.region, SUM(o.amount)
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE o.created_at > NOW() - INTERVAL '30 days'
GROUP BY c.region;
