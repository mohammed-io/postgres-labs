\timing on
SELECT c.region, SUM(o.amount)
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE o.created_at > NOW() - INTERVAL '30 days'
GROUP BY c.region;
