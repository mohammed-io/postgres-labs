---
name: "pg_stat, Configuration & Tuning"
category: "09-performance"
difficulty: "advanced"
time: "75 minutes"
concepts: ["pg_stat_statements", "pg_stat_activity", "configuration", "tuning"]
---

# pg_stat, Configuration & Tuning

## Learning Objectives

Master PostgreSQL performance monitoring and tuning.

## Why This Matters

| Tool | Purpose | Production Impact |
|------|---------|-------------------|
| `pg_stat_statements` | Find slow queries | Essential for optimization |
| `pg_stat_activity` | See what's running now | Debug blocking queries |
| `pg_stat_user_tables` | Table access stats | Identify hot/cold tables |
| `pg_stat_user_indexes` | Index usage | Find unused indexes |

## Real World Use

### When This Matters

1. **Slow page loads**
   - Dashboard takes 5 seconds to load
   - Investigation: `pg_stat_statements` reveals full table scan on 1M row table
   - Solution: Add index, reduce to 50ms

2. **Connection pool exhaustion**
   - App errors: "too many connections"
   - Investigation: 200 connections, most idle
   - Solution: Add PgBouncer, reduce pool size

3. **High CPU after deployment**
   - New query causing CPU spike
   - Investigation: `pg_stat_activity` shows many parallel executions
   - Solution: Optimize query, add rate limiting

## Your Tasks

1. Enable pg_stat_statements
2. Find slow queries
3. Tune configuration (work_mem, shared_buffers, etc.)
4. Set autovacuum aggressive for write-heavy tables

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Real-World Scenario

Your API is slow. You need to:
1. Identify which queries are slow
2. Understand why they're slow
3. Fix the bottleneck
