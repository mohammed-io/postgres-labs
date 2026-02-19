---
name: "Autovacuum, Bloat & Visibility Map"
category: "06-vacuum"
difficulty: "advanced"
time: "75 minutes"
concepts: ["autovacuum", "bloat", "visibility map", "dead tuples", "fillfactor"]
---

# Autovacuum, Bloat & Visibility Map

## Scenario

Your database is growing despite regular DELETE operations. The `user_sessions` table continues to grow from 100K sessions/hour, but expired sessions should be removed. You notice queries are getting slower, and the table size keeps increasing.

Your job is to understand why dead tuples accumulate, how autovacuum works, and how to prevent table bloat.

## Why This Lab Exists

Dead tuples (space left behind after DELETEs/UPDATEs) are a hidden performance killer:
- They waste disk space
- They slow down queries by increasing table size
- They can block updates if not cleaned up
- They cause index bloat
- They impact MVCC visibility

Without proper autovacuum configuration, tables can bloat 2-3x their actual data size. This happens silently until performance degrades.

## Real-World Example

### High-Write Tables Bloat

**Problem:** Analytics staging tables, queue tables, session/token tables. 100K sessions created per hour, sessions expire after 1 hour (DELETE old sessions). Table keeps growing despite deletes.

**Root cause:** Dead tuples not cleaned up fast enough. Autovacuum interval too long or configured too conservatively.

**Solution:** Tune autovacuum settings for high-write workloads, or use partitioning.

**What this teaches:** Autovacuum isn't automatic in the sense that you never configure it - it's automatic but requires tuning for your workload.

### Long-Running Reports Block Autovacuum

**Problem:** A long-running transaction blocks autovacuum from cleaning up dead tuples.

**Result:** Table grows 2-3x in size. Queries become progressively slower.

**Solution:** Keep transactions short, or accept that reports might impact performance.

**What this teaches:** Long transactions are one of the biggest causes of bloat. This is especially critical for reporting databases.

## What You Will Build

```
Phase 1: [Autovacuum Triggers] - Understand when autovacuum runs
Phase 2: [Bloat Measurement] - Measure and quantify table/index bloat
Phase 3: [Visibility Map] - Learn how MVCC tracks row visibility
Phase 4: [Tuning for Write-Heavy Workloads] - Configure autovacuum for high-write tables
```

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: Autovacuum Triggers - understand when autovacuum runs
2. Read `step-02.md`: Bloat Measurement - measure and quantify table/index bloat
3. Read `step-03.md`: Visibility Map - learn how MVCC tracks row visibility
4. Read `step-04.md`: Tuning for Write-Heavy Workloads - configure autovacuum for high-write tables
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with extreme autovacuum settings

## Learning Objectives

Master PostgreSQL's vacuum process and table bloat.

## Common Bloat Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Insufficient autovacuum | Table bloat, slow queries | Tune autovacuum settings |
| Long transactions | autovacuum can't clean up | Keep transactions short |
| High update tables | Excessive bloat | Adjust fillfactor |

## Your Tasks

1. Understand autovacuum triggers
2. Measure table/index bloat
3. Understand visibility map
4. Tune autovacuum for write-heavy workloads

## Real-World Scenario

You have a `user_sessions` table:
- 100K sessions created per hour
- Sessions expire after 1 hour (DELETE old sessions)
- Table keeps growing despite deletes

**Why?** Dead tuples not cleaned up fast enough.
