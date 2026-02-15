---
name: "EXPLAIN, Planner & Join Algorithms"
category: "04-query-processing"
difficulty: "intermediate"
time: "60 minutes"
concepts: ["EXPLAIN", "planner", "executor", "join algorithms", "cost model"]
---

# EXPLAIN, Planner & Join Algorithms

## Learning Objectives

Read and optimize query execution plans.

## Why This Matters

| Concept | Production Impact |
|---------|-------------------|
| **EXPLAIN ANALYZE** | Essential for diagnosing slow queries |
| **Join algorithms** | Nested loop vs hash join vs merge join performance |
| **Cost model** | Understand why planner makes choices |
| **Statistics** | Inaccurate stats = bad plans |

## Real World Use

### Verified Real-World Cases

**1. Stormatics - Production Query Fixed by ANALYZE ([Stormatics Blog](https://stormatics.tech/blogs/dont-skip-analyze-a-real-world-postgresql-story))**
   - Query performance suddenly degraded after data growth
   - `EXPLAIN ANALYZE` showed planner choosing wrong plan
   - Root cause: **Statistics outdated after bulk insert**
   - Planner expected 100 rows, actual was 100K
   - Solution: `ANALYZE` to refresh statistics
   - Query performance instantly restored
   - Published: October 10, 2025

**2. LinkedIn Article - Full Table Scan on 1.2M Rows ([LinkedIn](https://www.linkedin.com/pulse/day-2-use-explain-analyze-debug-slow-queries-shashank-vengala-ggeuc))**
   - Real-world debugging of slow query
   - `EXPLAIN ANALYZE` revealed full table scan on 1.2M row table
   - Used `BUFFERS` option to identify disk I/O hotspot
   - Solution: Index creation reduced query from seconds to milliseconds
   - Published: May 9, 2025

**3. Garvit Gupta - 1000x Query Optimization ([Blog](https://medium.com/@garvitgupta01/learnings-from-a-slow-query-analysis-in-postgresql-7f5e5f8f8f77))**
   - Worst-case runtime reduced by **~1000 times**
   - Used `EXPLAIN ANALYZE` to identify bottleneck
   - Focus on understanding planner's cost estimates
   - Published: March 6, 2023

## Quick Start

```bash
cd lab && docker-compose up -d && docker exec -it postgres-query psql -U postgres
```

## Key Concepts

```
Query → Parser → Analyzer → Rewriter → Planner → Executor
                                    ↓
                            EXPLAIN shows this plan
```

## Your Tasks

1. Read EXPLAIN output
2. Understand join algorithm selection
3. Fix plans with inaccurate statistics
4. Optimize a real slow query

## Verification

```bash
docker exec postgres-query psql -U postgres -f lab/verify.sql
```
