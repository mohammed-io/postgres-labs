\timing on

-- Simple write/read workload
INSERT INTO ledger (account_id, amount, kind)
SELECT (floor(random() * 1000) + 1)::int, (random() * 100)::numeric(12,2), 'credit'
FROM generate_series(1, 1000);

SELECT account_id, SUM(amount)
FROM ledger
GROUP BY account_id
ORDER BY SUM(amount) DESC
LIMIT 20;
