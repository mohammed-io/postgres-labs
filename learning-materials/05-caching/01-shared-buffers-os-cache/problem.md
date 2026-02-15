---
name: "Shared Buffers & OS Cache"
category: "05-caching"
difficulty: "intermediate"
time: "45 minutes"
concepts: ["shared_buffers", "OS page cache", "effective_cache_size", "plan cache"]
---

# Shared Buffers & OS Cache

## Learning Objectives

Understand PostgreSQL's two-level caching architecture.

## Why This Matters

| Setting | Purpose | Production Impact |
|---------|---------|-------------------|
| `shared_buffers` | Postgres's own cache | Too small = disk I/O, too big = double caching |
| `effective_cache_size` | Planner's estimate | Wrong value = bad query plans |
| `wal_buffers` | WAL cache | Affects commit performance |

## Real World Use

### Verified Real-World Cases

**1. Tinybird - shared_buffers Configuration Insight ([Tinybird Blog](https://www.tinybird.co/blog/outgrowing-postgres-handling-increased-user-concurrency))**
   - Real-world production experience challenging conventional wisdom
   - Finding: Setting `shared_buffers` to **25% of RAM (common advice) is often excessive**
   - On high-memory systems, large shared_buffers can hurt performance
   - OS page cache is often more efficient
   - Their experience: Lower shared_buffers, let OS cache handle more

**2. Stormatics - ANALYZE Fixed Slow Query ([Stormatics Blog](https://stormatics.tech/blogs/dont-skip-analyze-a-real-world-postgresql-story))**
   - Production query suddenly slowed down after data growth
   - Root cause: **Outdated statistics** made planner choose wrong plan
   - `EXPLAIN ANALYZE` showed planner expected 100 rows, actual was 100K
   - Solution: `ANALYZE table` to refresh statistics
   - Query performance instantly restored
   - Lesson: Always run ANALYZE after bulk data changes

## Architecture

```
Query Flow:
1. Check shared_buffers (Postgres managed)
2. If miss: Check OS page cache (system managed)
3. If miss: Read from disk

Result: Data often cached twice!
```

## Your Tasks

1. Understand two-level caching
2. Measure cache hit ratios
3. Set effective_cache_size correctly
4. Understand plan cache

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Verification

```sql
-- Cache hit ratio (target: >99%)
SELECT
    round(100.0 * sum(heap_blks_hit) /
        NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) AS cache_hit_pct
FROM pg_statio_user_tables;
```
