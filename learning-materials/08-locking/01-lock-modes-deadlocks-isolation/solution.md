# Solution: Lock Modes, Deadlocks & Isolation

## Real-World Scenarios & Solutions

### Scenario 1: Inventory Management (Prevent Oversell)

**Problem**: Multiple users buy same item simultaneously.

**Wrong Approach**:
```sql
BEGIN;
SELECT stock FROM products WHERE id = 1;  -- Read
-- User decides to buy
UPDATE products SET stock = stock - 1 WHERE id = 1;  -- Write
COMMIT;
```

**Race Condition**: Two users see `stock = 1`, both update to `0` - OK.
But if `stock = 2`, both see `2`, both update to `1` - OK.
No problem? Wrong! If check and update aren't atomic:

```sql
-- User A: Reads stock = 1
-- User B: Reads stock = 1
-- User A: Updates to 0, commits
-- User B: Updates to 0, commits
-- Result: Both succeeded, but stock was only 1!
```

**Solution 1: SELECT FOR UPDATE**
```sql
BEGIN;
SELECT stock FROM products WHERE id = 1 FOR UPDATE;
-- Row is now locked, other transactions wait
-- User B: SELECT ... FOR UPDATE → blocks until User A commits
-- User A:
UPDATE products SET stock = stock - 1 WHERE id = 1;
COMMIT;
-- User B: Now gets lock, reads stock = 0
-- Application logic: If stock = 0, reject purchase
```

**Solution 2: Atomic Update**
```sql
UPDATE products
SET stock = stock - 1
WHERE id = 1 AND stock > 0;

-- Check if row was updated
SELECT row_count();  -- If 0, no stock!
```

**Solution 3: Serializable Isolation with Retry**
```sql
CREATE TABLE purchase_attempts (
    retries INT DEFAULT 0
);

CREATE OR REPLACE FUNCTION buy_product(product_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    v_stock INT;
BEGIN
    LOOP
        BEGIN
            -- Try to purchase
            UPDATE products
            SET stock = stock - 1
            WHERE id = product_id AND stock > 0
            RETURNING stock INTO v_stock;

            IF FOUND THEN
                RETURN TRUE;  -- Success
            ELSE
                RETURN FALSE;  -- No stock
            END IF;
        EXCEPTION
            WHEN serialization_failure THEN
                -- Retry with exponential backoff
                PERFORM pg_sleep(0.1 * random());
                CONTINUE;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT buy_product(1);  -- Returns true/false
```

### Scenario 2: Queue Processing with Multiple Workers

**Problem**: 10 workers processing same job queue. Avoid duplicate processing.

**Solution**: SELECT FOR UPDATE SKIP LOCKED

```sql
CREATE FUNCTION claim_job(worker_id INT)
RETURNS INT AS $$
DECLARE
    v_job_id INT;
BEGIN
    -- Claim first pending job, skip if already locked
    SELECT id INTO v_job_id
    FROM job_queue
    WHERE status = 'pending'
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_job_id IS NULL THEN
        RETURN NULL;  -- No pending jobs
    END IF;

    UPDATE job_queue
    SET status = 'processing',
        worker_id = worker_id,
        started_at = NOW()
    WHERE id = v_job_id;

    RETURN v_job_id;
END;
$$ LANGUAGE plpgsql;

-- Workers run simultaneously
-- Worker 1
SELECT claim_job(1);

-- Worker 2 (runs at same time)
-- Gets DIFFERENT job, doesn't wait for Worker 1!
SELECT claim_job(2);
```

### Scenario 3: Deadlock Prevention

**Bad Pattern** (causes deadlock):
```sql
-- Transaction A
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;

-- Transaction B (reversed order!)
UPDATE accounts SET balance = balance - 100 WHERE id = 2;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
-- DEADLOCK!
```

**Good Pattern** (always lock in same order):
```sql
-- Always lock accounts in ascending ID order
-- Transaction A
UPDATE accounts SET balance = balance - 100 WHERE id IN (1, 2);
UPDATE accounts SET balance = balance + 100 WHERE id IN (3, 4);

-- Transaction B
UPDATE accounts SET balance = balance - 100 WHERE id IN (1, 2);
UPDATE accounts SET balance = balance + 100 WHERE id IN (3, 4);
-- No deadlock - both waiting for same locks in same order
```

### Isolation Level Guide

| Level | Guarantees | Use When |
|-------|------------|----------|
| READ COMMITTED | See committed changes | Default, most cases |
| REPEATABLE READ | Stable snapshot within transaction | Reports, analytics |
| SERIALIZABLE | Full isolation, no phantom reads | Financial transactions |

**Performance Impact**: Higher isolation = More locking overhead = Potential serialization failures (requiring retry logic)
