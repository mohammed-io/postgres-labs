# Step 1: Understanding Lock Modes

## Lock Mode Hierarchy (Strongest to Weakest)

```
AccessExclusive    ← DDL (DROP, ALTER)
     ↑
Exclusive          ← ROW EXCLUSIVE for UPDATE
     ↑
ShareRowExclusive  ← CREATE INDEX CONCURRENTLY
     ↑
Share              ← SELECT FOR SHARE
     ↑
ShareUpdateExclusive ← VACUUM (without FULL)
     ↑
RowExclusive       ← INSERT, UPDATE, DELETE
     ↑
RowShare           ← SELECT FOR UPDATE
     ↑
AccessShare        ← SELECT
```

### Key Conflicts

| Requested | Conflicts With |
|-----------|----------------|
| ACCESS EXCLUSIVE | Everything |
| EXCLUSIVE | Everything except ACCESS SHARE |
| ROW EXCLUSIVE | EXCLUSIVE, SHARE, SHARE ROW EXCLUSIVE |
| SHARE | ROW EXCLUSIVE, EXCLUSIVE |
| ROW SHARE | EXCLUSIVE, ACCESS EXCLUSIVE |
| ACCESS SHARE | ACCESS EXCLUSIVE only |

---

## Investigation

### 1. Observe Locks in Action

```sql
docker exec -it postgres-locking psql -U postgres

-- Terminal 1: Start transaction with update
BEGIN;
UPDATE products SET price = 100 WHERE id = 1;
-- Don't commit yet!

-- Terminal 2: Try to update same row
BEGIN;
UPDATE products SET price = 200 WHERE id = 1;
-- This blocks! Waiting for Terminal 1...
```

### 2. Check What's Locked

```sql
-- From Terminal 3 (admin connection)
SELECT
    pid,
    usename,
    pg_blocking_pids(pid) AS blocked_by,
    query,
    state
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
    AND cardinality(pg_blocking_pids(pid)) > 0;
```

### 3. See Lock Details

```sql
SELECT
    locktype,
    database,
    relation,
    page,
    tuple,
    virtualxid,
    transactionid,
    classid,
    objid,
    objsubid,
    virtualtransaction,
    pid,
    mode,
    granted
FROM pg_locks
WHERE pid = <transaction_pid>;
```

### 4. SELECT FOR UPDATE Practice

```sql
-- This locks rows for update
BEGIN;
SELECT * FROM products WHERE category = 'Electronics' FOR UPDATE;
-- Rows are now locked, other transactions must wait

-- Do processing...
UPDATE products SET price = price * 1.1 WHERE category = 'Electronics';

COMMIT;
```

**Use Case**: Preventing race conditions when:
- Bank transfers (debit one account, credit another)
- Inventory management (reserve items)
- Queue processing (claim jobs)

---

## Mini-Experiment

```sql
-- Terminal 1: Claim a job
BEGIN;
SELECT * FROM job_queue
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
-- Locks first available row, skips locked rows

-- Terminal 2: Try to claim same job
-- Gets NEXT pending row, doesn't wait!
```

`FOR UPDATE SKIP LOCKED` = Essential for multi-worker queue processing.
