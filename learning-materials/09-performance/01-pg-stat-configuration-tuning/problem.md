---
name: "pg_stat, Configuration & Tuning"
category: "09-performance"
difficulty: "advanced"
time: "75 minutes"
concepts: ["pg_stat_statements", "pg_stat_activity", "configuration", "tuning"]
---

# pg_stat, Configuration & Tuning

## Scenario

Your API is experiencing slow page loads. Dashboard takes 5 seconds to load, and you don't know why. You need to:
1. Identify which queries are slow
2. Understand why they're slow
3. Fix the bottleneck

Your job is to master PostgreSQL's monitoring tools and tune the database for optimal performance.

## Why This Lab Exists

Performance tuning requires data, not guesses. PostgreSQL provides extensive statistics for monitoring:
- `pg_stat_statements` tracks query performance over time
- `pg_stat_activity` shows what's running now
- `pg_stat_user_tables` reveals hot/cold tables
- `pg_stat_user_indexes` identifies unused indexes

Without these tools, you're tuning blind. You might optimize a query that no one uses, or miss the real bottleneck entirely.

## Real-World Example

### Slow Page Loads Due to Missed Indexes

**Problem:** Dashboard takes 5 seconds to load. You suspect it's slow queries.

**Investigation:** `pg_stat_statements` reveals a full table scan on a 1M row table for a daily summary query.

**Root cause:** Query was recently added but never indexed.

**Solution:** Add appropriate index, query reduces to 50ms.

**What this teaches:** Monitor query performance continuously. New queries should be measured before deployment.

### Connection Pool Exhaustion

**Problem:** App errors showing "too many connections".

**Investigation:** `pg_stat_activity` shows 200 connections, but only 20% are actively running queries. The rest are idle.

**Root cause:** Connection pool size too small, or connections not being released properly.

**Solution:** Add PgBouncer to manage connections, reduce pool size per connection.

**What this teaches:** Connection limits are finite. Over-provisioning connections wastes resources. Use connection pooling for production.

### High CPU After Deployment

**Problem:** New deployment causes CPU spike, site becomes unresponsive.

**Investigation:** `pg_stat_activity` shows many parallel executions of a new query.

**Root cause:** Query not optimized for the data distribution. 10x more rows than expected.

**Solution:** Analyze statistics, optimize query, add parameterized queries.

**What this teaches:** Performance changes after deployment are common. Always test thoroughly before going live.

## What You Will Build

```
Phase 1: [pg_stat_statements Setup] - Enable and use query performance tracking
Phase 2: [Slow Query Identification] - Find the actual bottlenecks
Phase 3: [Configuration Tuning] - Tune work_mem, shared_buffers, autovacuum
Phase 4: [Active Monitoring] - Use pg_stat_activity to debug blocking
Phase 5: [Index Optimization] - Use pg_stat_user_indexes to find unused indexes
```

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: pg_stat_statements Setup - enable and use query performance tracking
2. Read `step-02.md`: Slow Query Identification - find the actual bottlenecks
3. Read `step-03.md`: Configuration Tuning - tune work_mem, shared_buffers, autovacuum
4. Read `step-04.md`: Active Monitoring - use pg_stat_activity to debug blocking
5. Read `step-05.md`: Index Optimization - use pg_stat_user_indexes to find unused indexes
6. Run `lab/verify.sql` throughout to validate your understanding
7. Try `lab/break-it.sql` - see what happens with various performance scenarios

## Learning Objectives

Master PostgreSQL performance monitoring and tuning.

## Common Performance Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Slow page loads | High latency, timeouts | Use pg_stat_statements to find slow queries |
| Connection pool exhaustion | "too many connections" | Check pg_stat_activity for idle connections, add PgBouncer |
| High CPU after deployment | Slow site, high CPU usage | Analyze parallel execution, optimize query |
| High I/O during queries | Disk activity spikes | Check index usage, add missing indexes |

## Your Tasks

1. Enable pg_stat_statements
2. Find slow queries
3. Tune configuration (work_mem, shared_buffers, etc.)
4. Set autovacuum aggressive for write-heavy tables

## Real-World Scenario

Your API is slow. You need to:
1. Identify which queries are slow
2. Understand why they're slow
3. Fix the bottleneck
