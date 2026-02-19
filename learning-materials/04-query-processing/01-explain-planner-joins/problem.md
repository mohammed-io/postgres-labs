---
name: "EXPLAIN, Planner & Join Algorithms"
category: "04-query-processing"
difficulty: "intermediate"
time: "60 minutes"
concepts: ["EXPLAIN", "planner", "executor", "join algorithms", "cost model"]
---

# EXPLAIN, Planner & Join Algorithms

## Scenario

Your production queries are suddenly running slow, and you need to understand why. The query that took 5ms now takes 2 seconds. You have no idea what's causing the performance degradation.

Your job is to diagnose the issue using `EXPLAIN ANALYZE` and optimize the query execution plan.

## Why This Lab Exists

Most developers use `SELECT` and `INSERT` but rarely look at the execution plan. Understanding how PostgreSQL generates execution plans is critical for:
- Diagnosing slow queries
- Understanding why the planner makes certain choices
- Optimizing queries for real-world data distributions
- Identifying common pitfalls (statistics, index usage, join algorithms)

Poor planning leads to:
- Full table scans on large tables
- Suboptimal join algorithms
- Excessive I/O
- Unpredictable performance

## Real-World Example

### 1. Stormatics - Production Query Fixed by ANALYZE ([Stormatics Blog](https://stormatics.tech/blogs/dont-skip-analyze-a-real-world-postgresql-story))

**Problem:** A production query suddenly degraded in performance after a bulk insert of 100K rows.

**Root cause:** `EXPLAIN ANALYZE` showed the planner choosing a `Seq Scan` (sequential scan) instead of an `Index Scan`. The statistics were outdated - planner expected 100 rows, but actual was 100K. With 100K rows, sequential scan became more efficient.

**Solution:** Run `ANALYZE` to refresh statistics. Query performance instantly restored.

**What this teaches:** Statistics are critical for the planner. Always run ANALYZE after bulk data changes.

### 2. LinkedIn Article - Full Table Scan on 1.2M Rows ([LinkedIn](https://www.linkedin.com/pulse/day-2-use-explain-analyze-debug-slow-queries-shashank-vengala-ggeuc))

**Problem:** Real-world debugging of a slow query.

**Root cause:** `EXPLAIN ANALYZE` revealed a full table scan on a 1.2M row table. The `BUFFERS` option showed high disk I/O.

**Solution:** Index creation reduced query from seconds to milliseconds.

**What this teaches:** EXPLAIN ANALYZE with BUFFERS is your best tool for identifying I/O hotspots.

### 3. Garvit Gupta - 1000x Query Optimization ([Blog](https://garvitgupta58.medium.com/learnings-from-a-slow-query-analysis-in-postgresql-d2316def97d7))

**Problem:** Worst-case runtime reduced by ~1000 times.

**Root cause:** Used `EXPLAIN ANALYZE` to identify bottleneck - planner choosing wrong join algorithm for large datasets.

**Solution:** Changed from `Nested Loop Join` to `Hash Join` by adjusting statistics and query structure.

**What this teaches:** Understanding the cost model helps you guide the planner to better plans.

## What You Will Build

```
Phase 1: [EXPLAIN Basics] - Read and understand execution plans
Phase 2: [Statistics Impact] - See how accurate stats affect planner decisions
Phase 3: [Join Algorithms] - Compare Nested Loop, Hash Join, Merge Join
Phase 4: [Real Query Optimization] - Fix a slow production-style query
```

## Quick Start

```bash
cd lab && docker-compose up -d && docker exec -it postgres-query psql -U postgres
```

## Lab Flow

1. Read `step-01.md`: EXPLAIN Basics - read and understand execution plans
2. Read `step-02.md`: Statistics Impact - see how accurate stats affect planner decisions
3. Read `step-03.md`: Join Algorithms - compare Nested Loop, Hash Join, Merge Join
4. Read `step-04.md`: Real Query Optimization - fix a slow production-style query
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with various query patterns

## Learning Objectives

Read and optimize query execution plans.

## Your Tasks

1. Read EXPLAIN output
2. Understand join algorithm selection
3. Fix plans with inaccurate statistics
4. Optimize a real slow query

## Query Flow

```
Query → Parser → Analyzer → Rewriter → Planner → Executor
                                     ↓
                             EXPLAIN shows this plan
```

## Verification

```bash
docker exec postgres-query psql -U postgres -f lab/verify.sql
```
