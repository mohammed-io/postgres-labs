---
name: "Lock Modes, Deadlocks & Isolation"
category: "08-locking"
difficulty: "intermediate"
time: "60 minutes"
concepts: ["lock modes", "deadlocks", "isolation levels", "for update"]
---

# Lock Modes, Deadlocks & Isolation

## Scenario

You're building an order system for an e-commerce platform. Two users simultaneously click "Buy" on the same limited stock item. Without proper locking, you could oversell the item or have race conditions.

Your job is to understand PostgreSQL's locking mechanisms, deadlocks, and isolation levels to prevent these issues.

## Why This Lab Exists

Concurrency control is one of PostgreSQL's most complex but critical features:
- **Lock modes** determine what operations can happen simultaneously
- **Deadlocks** occur when transactions wait on each other indefinitely
- **Isolation levels** balance consistency vs. concurrency
- **SELECT FOR UPDATE** prevents race conditions

Without understanding these concepts, you can build applications with:
- Overselling inventory
- Lost updates (incorrect balances)
- Deadlocks causing transaction failures
- Unintended side effects

## Real-World Example

### Inventory Management Race Condition

**Problem:** Multiple users buying the same product.

**Scenario:**
1. User A: Checks stock (50 items)
2. User B: Checks stock (50 items)
3. User A: Buys 1 item (stock: 49)
4. User B: Buys 1 item (stock: 49) ❌ Should be 48!

**Root cause:** Two transactions read the same stale value independently. No locking.

**Solution:** Use proper locking:
```sql
BEGIN;
SELECT stock FROM inventory WHERE id = 1 FOR UPDATE;
UPDATE inventory SET stock = stock - 1 WHERE id = 1;
COMMIT;
```

**What this teaches:** SELECT FOR UPDATE locks the row, preventing other transactions from modifying it until the first transaction commits.

### Job Processing Duplicate Processing

**Problem:** Multiple workers processing the same queue item.

**Scenario:**
1. Worker A: Finds job #100 (status: pending)
2. Worker B: Finds job #100 (status: pending)
3. Both process job #100
4. Job executed twice! ❌

**Root cause:** No locking when selecting jobs from queue.

**Solution:** SELECT FOR UPDATE SKIP LOCKED:
```sql
BEGIN;
SELECT id FROM jobs WHERE status = 'pending' AND worker_id IS NULL FOR UPDATE SKIP LOCKED LIMIT 1;
UPDATE jobs SET worker_id = 'worker_a', status = 'processing' WHERE id = ?;
COMMIT;
```

**What this teaches:** SKIP LOCKED lets transactions skip rows locked by other transactions. Essential for queue processing.

### Financial Transaction Lost Update

**Problem:** Account balance updates incorrectly.

**Scenario:**
1. Transaction A: Reads balance = 100
2. Transaction B: Reads balance = 100
3. Transaction A: Updates balance to 95
4. Transaction B: Updates balance to 90 (based on old value) ❌

**Root cause:** Lost update - Transaction B overwrote Transaction A's changes.

**Solution:** Use serializable isolation level with retry:
```sql
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;
```

**What this teaches:** Serializable isolation prevents lost updates by detecting conflicts. If a conflict occurs, the transaction is retried.

## What You Will Build

```
Phase 1: [Lock Modes] - Understand locking behavior of different operations
Phase 2: [Deadlocks] - Cause and resolve deadlock scenarios
Phase 3: [Isolation Levels] - Test and understand ACID guarantees
Phase 4: [SELECT FOR UPDATE] - Use proper locking for race conditions
```

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: Lock Modes - understand locking behavior of different operations
2. Read `step-02.md`: Deadlocks - cause and resolve deadlock scenarios
3. Read `step-03.md`: Isolation Levels - test and understand ACID guarantees
4. Read `step-04.md`: SELECT FOR UPDATE - use proper locking for race conditions
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with various concurrency scenarios

## Learning Objectives

Understand PostgreSQL's locking and concurrency control.

## Common Locking Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Blocking queries | Slow application, timeouts | Use appropriate lock modes |
| Deadlocks | Transaction failures | Order locks consistently |
| Wrong isolation level | Phantom reads, lost updates | Choose correct isolation level |

## Your Tasks

1. Understand lock modes and conflicts
2. Cause and resolve deadlocks
3. Test isolation levels
4. Use SELECT FOR UPDATE properly

## Real-World Scenario

You're building an order system:
- User clicks "Buy" → Check inventory → Decrement stock → Create order
- Two users click simultaneously
- Without proper locking: Both succeed, but only 1 item in stock!
