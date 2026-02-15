---
name: "Autovacuum, Bloat & Visibility Map"
category: "06-vacuum"
difficulty: "advanced"
time: "75 minutes"
concepts: ["autovacuum", "bloat", "visibility map", "dead tuples", "fillfactor"]
---

# Autovacuum, Bloat & Visibility Map

## Learning Objectives

Master PostgreSQL's vacuum process and table bloat.

## Why This Matters

| Issue | Symptom | Solution |
|-------|---------|----------|
| Insufficient autovacuum | Table bloat, slow queries | Tune autovacuum settings |
| Long transactions | autovacuum can't clean up | Keep transactions short |
| High update tables | Excessive bloat | Adjust fillfactor |

## Real World Use

### When This Matters

1. **High-write tables** (insert/update/delete heavy)
   - Analytics staging tables
   - Queue tables
   - Session/token tables
   - Result: Dead tuples accumulate, causing bloat

2. **Long-running reports**
   - A transaction open for hours
   - Blocks autovacuum from cleaning up
   - Result: Table grows 2-3x in size

3. **Batch updates**
   - Update 1M rows in one transaction
   - Creates 1M dead tuples
   - Without aggressive autovacuum: table bloats

## Your Tasks

1. Understand autovacuum triggers
2. Measure table/index bloat
3. Understand visibility map
4. Tune autovacuum for write-heavy workloads

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Real-World Scenario

You have a `user_sessions` table:
- 100K sessions created per hour
- Sessions expire after 1 hour (DELETE old sessions)
- Table keeps growing despite deletes

**Why?** Dead tuples not cleaned up fast enough.
