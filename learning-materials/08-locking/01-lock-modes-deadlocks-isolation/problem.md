---
name: "Lock Modes, Deadlocks & Isolation"
category: "08-locking"
difficulty: "intermediate"
time: "60 minutes"
concepts: ["lock modes", "deadlocks", "isolation levels", "for update"]
---

# Lock Modes, Deadlocks & Isolation

## Learning Objectives

Understand PostgreSQL's locking and concurrency control.

## Why This Matters

| Issue | Symptom | Solution |
|-------|---------|----------|
| Blocking queries | Slow application, timeouts | Use appropriate lock modes |
| Deadlocks | Transaction failures | Order locks consistently |
| Wrong isolation level | Phantom reads, lost updates | Choose correct isolation level |

## Real World Use

### When This Matters

1. **Inventory Management**
   - Multiple users buying same product
   - Risk: Overselling, race conditions
   - Solution: Proper locking + isolation level

2. **Job Processing**
   - Multiple workers processing same queue
   - Risk: Duplicate processing
   - Solution: SELECT FOR UPDATE SKIP LOCKED

3. **Financial Transactions**
   - Account balance updates
   - Risk: Lost updates, incorrect balances
   - Solution: Serializable isolation with retry

## Your Tasks

1. Understand lock modes and conflicts
2. Cause and resolve deadlocks
3. Test isolation levels
4. Use SELECT FOR UPDATE properly

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Real-World Scenario

You're building an order system:
- User clicks "Buy" → Check inventory → Decrement stock → Create order
- Two users click simultaneously
- Without proper locking: Both succeed, but only 1 item in stock!
