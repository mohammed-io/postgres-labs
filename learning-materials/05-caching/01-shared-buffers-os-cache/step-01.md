# Step 1: Two-Level Caching

## Understanding PostgreSQL's Cache Architecture

PostgreSQL uses **two levels of caching**:

```
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL Process                         │
│                                                             │
│  ┌──────────────────┐        ┌──────────────────────┐     │
│  │ shared_buffers   │        │   query plans        │     │
│  │  (PostgreSQL     │  Miss   │   (catalog cache)     │     │
│  │   managed)       │────────>│                       │     │
│  └──────────────────┘        └──────────────────────┘     │
│           │                                            │
│           │ read(8KB page)                           │
│           ▼                                            │
│  ┌──────────────────────────────────────────────────────┐│
│  │              OS Page Cache (system)                  ││
│  │              (Linux: pagecache)                      ││
│  └──────────────────────────────────────────────────────┘│
│           │                                            │
│           │ Miss                                      │
│           ▼                                            │
│  ┌──────────────────┐                                    │
│  │     Disk         │                                    │
│  │   (storage)      │                                    │
│  └──────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

### Key Insight

The same 8KB page can exist in **both** `shared_buffers` AND OS cache. This is called "double caching."

---

## Investigation

### 1. Check Cache Settings

```sql
docker exec -it postgres-cache psql -U postgres

-- View cache configuration
SELECT
    name,
    setting,
    unit,
    context,
    short_desc
FROM pg_settings
WHERE name LIKE '%cache%' OR name LIKE '%buffer%'
ORDER BY name;
```

**Key settings explained**:
- `shared_buffers`: Memory Postgres uses for caching (default: 128MB)
- `effective_cache_size`: Planner's estimate of TOTAL cache (Postgres + OS)
- `wal_buffers`: Memory for WAL before writing to disk

### 2. Measure Cache Hit Ratio

```sql
-- Table-level cache stats
SELECT
    schemaname,
    tablename,
    heap_blks_read AS disk_reads,
    heap_blks_hit AS cache_hits,
    round(100.0 * heap_blks_hit /
        NULLIF(heap_blks_hit + heap_blks_read, 0), 2) AS hit_ratio_pct
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 0
ORDER BY hit_ratio_pct;
```

**Real output example**:
```
 tablename  | disk_reads | cache_hits | hit_ratio_pct
------------+------------+------------+--------------
 products   |        123 |     98765  |        99.88
 orders     |       4521 |     45678  |        91.01
```

**Target**: >99% for OLTP workloads

### 3. Understanding effective_cache_size

```sql
-- What planner thinks is available
SHOW effective_cache_size;

-- Check if it matches your system
-- Rule: ~75% of RAM (for dedicated DB server)
-- On a 16GB server: effective_cache_size should be ~12GB
```

**Why this matters**: If `effective_cache_size` is too low, planner prefers seq scans. If too high, may overestimate index benefits.

### 4. See Plan Cache in Action

```sql
-- Prepared statements use plan cache
PREPARE get_product AS SELECT * FROM products WHERE id = $1;

EXECUTE get_product(1);
EXECUTE get_product(2);
EXECUTE get_product(3);

-- Check if plan was cached
SELECT
    query,
    calls,
    rows
FROM pg_stat_statements
WHERE query LIKE '%get_product%';
```

---

## Mini-Experiment

```sql
-- Force cache miss then hit
\timing on

-- First run (cache miss)
SELECT count(*) FROM products WHERE price > 500;

-- Second run (cache hit)
SELECT count(*) FROM products WHERE price > 500;

\timing off
```

Which was faster? Why? (See solution.md for explanation)
