# Step 2: Deadlocks and Isolation Levels

## Understanding Deadlocks

**Deadlock** = Two transactions waiting for each other, neither can proceed.

```
Transaction A:          Transaction B:
UPDATE row_1
                         UPDATE row_2
UPDATE row_2 (blocks)    UPDATE row_1 (blocks)
    ↓                          ↓
   waits for B              waits for A
    ←────────── DEADLOCK ───────→
```

---

## Investigation

### 1. Cause a Deadlock

```sql
-- Terminal 1
BEGIN;
UPDATE products SET price = 100 WHERE id = 1;

-- Terminal 2
BEGIN;
UPDATE products SET price = 200 WHERE id = 2;

-- Back to Terminal 1
UPDATE products SET price = 300 WHERE id = 2;
-- Blocked, waiting for Terminal 2...

-- Terminal 2
UPDATE products SET price = 400 WHERE id = 1;
-- DEADLOCK! Postgres kills one transaction
```

### 2. Check Deadlock Log

```sql
-- View deadlock information
SELECT * FROM pg_stat_database_conflicts;
```

Postgres logs deadlocks to the server log, not directly queryable.

### 3. Test Isolation Levels

```sql
-- Read Committed (default)
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;
SELECT * FROM products WHERE id = 1;
-- Terminal 2: UPDATE products SET price = 500 WHERE id = 1; COMMIT
-- Terminal 1: SELECT * FROM products WHERE id = 1;
-- Sees NEW price = 500 (committed changes)
COMMIT;

-- Repeatable Read
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;
SELECT * FROM products WHERE id = 1;
-- Terminal 2: UPDATE products SET price = 600 WHERE id = 1; COMMIT
-- Terminal 1: SELECT * FROM products WHERE id = 1;
-- Still sees OLD price (snapshot)
COMMIT;

-- Serializable
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Most strict - detects concurrent modification conflicts
-- May fail with: ERROR: could not serialize due to concurrent update
```

### 4. Real-World Inventory Race Condition

```sql
-- Problem: Two users buy last item simultaneously
-- Terminal 1 (User A)
BEGIN;
SELECT stock FROM products WHERE id = 1;
-- Shows: 1 left

-- Terminal 2 (User B)
BEGIN;
SELECT stock FROM products WHERE id = 1;
-- Shows: 1 left

-- Both proceed...
-- Terminal 1
UPDATE products SET stock = stock - 1 WHERE id = 1;
COMMIT;

-- Terminal 2
UPDATE products SET stock = stock - 1 WHERE id = 1;
COMMIT;

-- Result: stock = -1! Oversold!
```

**Solution**: Use proper locking (see solution.md)
