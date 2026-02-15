# Solution: Autovacuum, Bloat & Visibility Map

## Complete Answers

### Real-World Scenarios & Solutions

#### Scenario 1: High-Write Queue Table

**Problem**: `job_queue` table processes jobs then deletes them. Table grows despite deletes.

```sql
-- Solution: Aggressive autovacuum for this table
ALTER TABLE job_queue SET (
    autovacuum_vacuum_threshold = 50,
    autovacuum_vacuum_scale_factor = 0.01,   -- 1%
    autovacuum_analyze_threshold = 50,
    autovacuum_analyze_scale_factor = 0.01   -- 1%
);
```

**Why**: Default settings require 20% changes. For 1M row table = 200K jobs! Aggressive settings keep table size managed.

#### Scenario 2: Bulk Update Nightly

**Problem**: Nightly batch updates 1M rows. Table bloats 2x.

```sql
-- Before bulk update
ALTER TABLE nightly_batch SET (autovacuum_enabled = off);

-- Do updates
UPDATE nightly_batch SET processed = true WHERE created_at > NOW() - INTERVAL '1 day';

-- After: Manual vacuum immediately
VACUUM ANALYZE nightly_batch;
ALTER TABLE nightly_batch SET (autovacuum_enabled = on);
```

**Why**: Disabling autovacuum prevents it from interfering with bulk operation. Manual vacuum afterward cleans up immediately.

#### Scenario 3: Long-Running Report

**Problem**: Analytics query runs for 2 hours. Autovacuum blocked.

```sql
-- Check for blocking transactions
SELECT
    pid,
    usename,
    state,
    state_change,
    NOW() - state_change AS duration,
    query
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
    AND state_change < NOW() - INTERVAL '5 minutes';

-- Kill if needed
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = <long-running-pid>;
```

**Prevention**:
- Use READ COMMITTED isolation (allows vacuum to work)
- Break long queries into chunks
- Use cursors with WITH HOLD for large result sets

### Bloat Reduction Strategies

| Strategy | When to Use | Command |
|----------|-------------|---------|
| Regular autovacuum | Ongoing maintenance | Tune per-table settings |
| Manual vacuum | After large deletes | `VACUUM table;` |
| VACUUM FULL | Maintenance window only | `VACUUM FULL table;` |
| Reindex | Index bloat | `REINDEX TABLE table;` |
| pg_repack | Zero-downtime rebuild | External tool |

### Recommended Settings by Table Type

| Table Type | vacuum_threshold | vacuum_scale_factor |
|-----------|------------------|---------------------|
| Small (<10K rows) | 50 | 0.1 |
| Medium (10K-1M) | 100 | 0.05 |
| Large (>1M) | 1000 | 0.01 |
| High-write | 50 | 0.01 |

### Monitoring Query

```sql
-- Comprehensive bloat monitoring
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    n_dead_tup,
    n_live_tup,
    round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
    autovacuum_count,
    last_autovacuum
FROM pg_stat_user_tables
WHERE n_live_tup > 0
    AND (
        n_dead_tup > 10000  -- More than 10K dead tuples
        OR (100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0) > 10)  -- Or >10% dead
    )
ORDER BY dead_pct DESC;
```
