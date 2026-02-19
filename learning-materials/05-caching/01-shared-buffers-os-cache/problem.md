---
name: "Shared Buffers & OS Cache"
category: "05-caching"
difficulty: "intermediate"
time: "45 minutes"
concepts: ["shared_buffers", "OS page cache", "effective_cache_size", "plan cache"]
---

# Shared Buffers & OS Cache

## Scenario

Your application is experiencing slow queries. You've tuned PostgreSQL parameters, but performance is still poor. You need to understand PostgreSQL's two-level caching architecture and why data might be cached twice.

Your job is to configure PostgreSQL's cache settings correctly and optimize query performance.

## Why This Lab Exists

PostgreSQL has two caching layers: `shared_buffers` (PostgreSQL-managed) and the OS page cache (system-managed). Most developers misunderstand:
- How much data should go in `shared_buffers`
- Why correct `effective_cache_size` is critical for query planning
- That setting `shared_buffers` too high can hurt performance
- How to measure cache hit ratios

Misconfigured cache settings lead to:
- Excessive disk I/O
- Poor query plans due to inaccurate estimates
- Wasted memory (caching data twice)
- Inconsistent performance

## Real-World Example

### 1. Tinybird - shared_buffers Configuration Insight ([Tinybird Blog](https://www.tinybird.co/blog/outgrowing-postgres-handling-increased-user-concurrency))

**Problem:** Real-world production experience challenging conventional wisdom.

**Finding:** Setting `shared_buffers` to 25% of RAM (common advice) is often excessive on high-memory systems.

**Observation:** Large shared_buffers can hurt performance because the OS page cache is often more efficient.

**Solution:** Lower shared_buffers, let OS cache handle more. Tinybird's experience: "Lower shared_buffers, let OS cache handle more."

**What this teaches:** The "25% rule" isn't one-size-fits-all. On modern servers with plenty of RAM, letting the OS cache handle frequently accessed data is often better.

### 2. Stormatics - ANALYZE Fixed Slow Query ([Stormatics Blog](https://stormatics.tech/blogs/dont-skip-analyze-a-real-world-postgresql-story))

**Problem:** Production query suddenly slowed down after data growth.

**Root cause:** **Outdated statistics** made planner choose wrong plan. `EXPLAIN ANALYZE` showed planner expected 100 rows, actual was 100K.

**Solution:** `ANALYZE table` to refresh statistics.

**What this teaches:** Cache settings affect performance, but statistics are equally important. Wrong statistics = wrong plans.

## What You Will Build

```
Phase 1: [Cache Architecture] - Understand two-level caching (Postgres + OS)
Phase 2: [Cache Hit Measurement] - Measure and optimize cache hit ratios
Phase 3: [Configuration Tuning] - Set shared_buffers, effective_cache_size correctly
Phase 4: [Plan Cache Understanding] - Learn how caching affects query plans
```

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: Cache Architecture - understand two-level caching (Postgres + OS)
2. Read `step-02.md`: Cache Hit Measurement - measure and optimize cache hit ratios
3. Read `step-03.md`: Configuration Tuning - set shared_buffers, effective_cache_size correctly
4. Read `step-04.md`: Plan Cache Understanding - learn how caching affects query plans
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with various cache configurations

## Learning Objectives

Understand PostgreSQL's two-level caching architecture.

## Cache Flow

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

## Verification

```sql
-- Cache hit ratio (target: >99%)
SELECT
    round(100.0 * sum(heap_blks_hit) /
        NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) AS cache_hit_pct
FROM pg_statio_user_tables;
```
