\timing on
SELECT COUNT(*) FROM accounts;
UPDATE accounts SET balance = balance + 1 WHERE id % 10 = 0;
