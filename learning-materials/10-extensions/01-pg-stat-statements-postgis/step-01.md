# Step 1: pg_stat_statements - Query Profiling

## The Essential Extension

`pg_stat_statements` tracks execution statistics for all queries run on your database.

**It's the first tool to reach for slow query issues.**

---

## Investigation

### 1. Enable pg_stat_statements

```sql
docker exec -it postgres-ext psql -U postgres

-- Enable extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify it's loaded
SELECT * FROM pg_available_extensions
WHERE name = 'pg_stat_statements';
```

### 2. Run Some Queries to Generate Stats

```sql
-- Fast query
SELECT count(*) FROM products;

-- Slow query (intentionally bad)
SELECT count(*) FROM products
WHERE name LIKE '%test%';  -- Can't use index!

-- Create some load
SELECT * FROM products ORDER BY random() LIMIT 100;
```

### 3. View Query Statistics

```sql
-- All queries tracked
SELECT
    queryid,
    substr(query, 1, 50) AS query_preview,
    calls,
    total_exec_time / 1000 AS total_sec,
    mean_exec_time AS avg_ms,
    stddev_exec_time AS std_dev_ms,
    rows
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**Real output example**:
```
  query_preview       | calls | total_sec | avg_ms | std_dev_ms
----------------------+-------+-----------+--------+------------
SELECT * FROM prod... |   500 |     25.5  |  51.0  |      12.3
SELECT COUNT(*) FRO... |    50 |      0.5  |  10.0  |       2.1
SELECT * FROM prod... |  1000 |      2.0  |   2.0  |       0.5
```

**Analysis**:
- First query: 51ms avg, 12ms std dev → Variable performance (might be caching)
- Second query: 10ms avg → Consistent
- Third query: 2ms avg → Fast, predictable

### 4. Track Query Over Time

```sql
-- Reset stats to measure fresh
SELECT pg_stat_statements_reset(0);

-- ... run queries ...

-- Check again
SELECT queryid, calls, mean_exec_time
FROM pg_stat_statements;
```

### 5. Find Full Table Scans

```sql
-- Queries with many rows returned
SELECT
    substr(query, 1, 60) AS query_preview,
    calls,
    rows,
    100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS cache_hit_pct
FROM pg_stat_statements
WHERE rows > 1000
ORDER BY rows DESC;
```

**Real output**:
```
      query_preview       | rows    | cache_hit_pct
----------------------+---------+--------------
 SELECT * FROM orders     | 500000  |         25.5  ← Low cache hit!
 SELECT * FROM products   | 100000  |         98.2  ← Good
```

**Action**: Investigate the orders query - likely missing index.

---

## Real-World Usage

**Scenario**: Dashboard slow after deployment.

```sql
-- Find queries in last hour
SELECT
    substr(query, 1, 80) AS query,
    calls,
    mean_exec_time AS avg_ms
FROM pg_stat_statements
WHERE calls > 100
    AND mean_exec_time > 50  -- Slower than 50ms
ORDER BY mean_exec_time DESC;
```

**Result**: Found new query with `LIKE '%term%'` causing full table scan.

**Fix**:
```sql
-- Add pg_trgm extension for fuzzy search
CREATE EXTENSION pg_trgm;

-- Create GIN index
CREATE INDEX idx_products_name_trgm
ON products USING gin (name gin_trgm_ops);

-- Now LIKE '%term%' uses index!
```

See solution.md for more extension examples.
