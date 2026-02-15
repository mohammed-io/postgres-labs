# Step 1: Finding Slow Queries with pg_stat_statements

## The Most Important Extension

`pg_stat_statements` tracks query performance across your database.

**It's essential for production.**

---

## Investigation

### 1. Enable pg_stat_statements

```sql
docker exec -it postgres-perf psql -U postgres

-- Enable extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify
SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';
```

### 2. Find Your Slowest Queries

```sql
-- Top 10 slowest by average time
SELECT
    substr(query, 1, 50) AS query_preview,
    calls,
    total_exec_time / 1000 AS total_sec,
    mean_exec_time AS avg_ms,
    max_exec_time AS max_ms,
    rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**Real output example**:
```
      query_preview       | calls | total_sec | avg_ms | max_ms
---------------------------+-------+-----------+--------+--------
 SELECT * FROM orders WHE... |   500 |     125.5 |  251.0 |  5000
 SELECT * FROM users LEFT ... |   100 |      50.0 |  500.0 |  1000
 SELECT COUNT(*) FROM pro... |    50 |       2.5 |   50.0 |   100
```

**Analysis**:
- First query: 251ms average, 5 seconds worst case → BAD
- Second query: 500ms worst case → Needs investigation
- Third query: Aggregation, might need index

### 3. Find Queries Called Frequently

```sql
-- High call count + slow = optimization target
SELECT
    substr(query, 1, 60) AS query_preview,
    calls,
    mean_exec_time AS avg_ms,
    total_exec_time / 1000 AS total_sec
FROM pg_stat_statements
WHERE calls > 100
ORDER BY total_exec_time DESC
LIMIT 10;
```

**Why**: A query called 1000 times taking 10ms = 10 seconds total. Optimize this one!

### 4. Find Queries Reading Too Many Rows

```sql
SELECT
    substr(query, 1, 60) AS query_preview,
    calls,
    rows,
    100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS cache_hit_pct
FROM pg_stat_statements
WHERE rows > 1000
ORDER BY rows DESC
LIMIT 10;
```

**Real output example**:
```
      query_preview       | calls |   rows    | cache_hit_pct
---------------------------+-------+-----------+--------------
 SELECT * FROM orders     |  1000 | 10000000  |         45.5
 SELECT * FROM products   |   500 |   500000  |         89.2
```

**Problem**: Query reads 10M rows! Only 45% cache hit.

### 5. Reset Statistics (After Optimization)

```sql
-- Reset stats for specific query
SELECT pg_stat_statements_reset($queryid);

-- Or reset all (careful!)
SELECT pg_stat_statements_reset(0);
```

---

## Real-World Investigation Workflow

**User Report**: "Dashboard is slow"

1. Find the query:
   ```sql
   -- Find dashboard queries
   SELECT * FROM pg_stat_statements
   WHERE query LIKE '%dashboard%';
   ```

2. Examine the plan:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS)
   SELECT ... FROM dashboard_query;
   ```

3. Identify bottleneck:
   - Seq Scan → Add index
   - High buffers read → Increase cache hit
   - Sort/Hash → Increase work_mem

4. Fix and verify:
   ```sql
   CREATE INDEX idx_dashboard_user_id ON dashboard(user_id);

   -- Check improvement
   SELECT mean_exec_time FROM pg_stat_statements
   WHERE queryid = <query_id>;
   ```

See solution.md for configuration tuning.
