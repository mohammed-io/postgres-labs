# Solution: Hint Bits & Page-Level Visibility

## Complete Answers

### Task 1: Inspect Tuple Headers with pageinspect

**Goal**: See hint bits directly in tuple headers.

```sql
-- Connect
docker exec -it pg-hint-bits psql -U postgres

-- Get the first page of orders
SELECT
    lp AS offset,
    t_xmin,
    t_xmax,
    t_infomask,
    CASE WHEN t_infomask & 256 = 256 THEN 'SET' ELSE 'NOT SET' END AS xmin_committed,
    CASE WHEN t_infomask & 512 = 512 THEN 'SET' ELSE 'NOT SET' END AS xmin_invalid,
    CASE WHEN t_infomask & 1024 = 1024 THEN 'SET' ELSE 'NOT SET' END AS xmax_committed,
    CASE WHEN t_infomask & 2048 = 2048 THEN 'SET' ELSE 'NOT SET' END AS xmax_invalid
FROM heap_page_items(get_raw_page('orders', 0))
LIMIT 10;
```

**What you see**:
- `t_infomask` is a bitmask. The relevant hint bit flags are:
  - `0x0100` (256) = `HEAP_XMIN_COMMITTED` — the inserting transaction is known committed
  - `0x0200` (512) = `HEAP_XMIN_INVALID` — the inserting transaction is known aborted
  - `0x0400` (1024) = `HEAP_XMAX_COMMITTED` — the deleting transaction is known committed
  - `0x0800` (2048) = `HEAP_XMAX_INVALID` — no deletion, or deleting transaction aborted
- If `xmin_committed` is NOT SET, Postgres must check CLOG to determine visibility

### Task 2: Observe Hint Bits Being Set on First Read

**Goal**: Insert rows, check hint bits before and after a SELECT.

```sql
-- Create fresh table for clean observation
CREATE TABLE hint_observe (id serial PRIMARY KEY, data text);

-- Insert a single row in an explicit transaction
BEGIN;
INSERT INTO hint_observe (data) VALUES ('test-row');
COMMIT;

-- Check the hint bit BEFORE any SELECT reads it
SELECT
    t_xmin,
    CASE WHEN t_infomask & 256 = 256 THEN 'SET' ELSE 'NOT SET' END AS xmin_committed
FROM heap_page_items(get_raw_page('hint_observe', 0))
WHERE t_xmin IS NOT NULL;

-- Result: xmin_committed = 'NOT SET' (hint bit not yet set)

-- Now read the row (this sets the hint bit as a side effect)
SELECT * FROM hint_observe;

-- Check again
SELECT
    t_xmin,
    CASE WHEN t_infomask & 256 = 256 THEN 'SET' ELSE 'NOT SET' END AS xmin_committed
FROM heap_page_items(get_raw_page('hint_observe', 0))
WHERE t_xmin IS NOT NULL;

-- Result: xmin_committed = 'SET' (hint bit was set by the first reader)
```

**Why this matters**: The first `SELECT` after `COMMIT` is slower because it must check CLOG and then write the hint bit back to the page (dirtying the page). All subsequent reads skip the CLOG lookup entirely.

### Task 3: Measure Performance Difference

**Goal**: Compare SELECT timing with and without hint bits.

```sql
-- Create a large table with fresh data (no hint bits yet)
CREATE TABLE perf_test (id serial PRIMARY KEY, data text, created_at timestamptz default now());
INSERT INTO perf_test (data)
SELECT repeat('x', 100) FROM generate_series(1, 100000);

-- Clear shared_buffers to simulate cold cache (requires superuser)
DISCARD ALL;

-- Time a full table scan (hint bits NOT set for recent inserts)
EXPLAIN (ANALYZE, BUFFERS, TIMING) SELECT count(*) FROM perf_test;

-- Run again (hint bits now set by first scan)
EXPLAIN (ANALYZE, BUFFERS, TIMING) SELECT count(*) FROM perf_test;
```

**What you see**: The first scan shows more `shared read` blocks (CLOG lookups) and is slower. The second scan is faster because hint bits are now cached on the pages.

### Task 4: Simulate a Hint Bit Storm

**Goal**: Create a scenario where many rows have no hint bits and measure the I/O impact.

```sql
-- Step 1: Create table and insert data in many transactions
CREATE TABLE storm_test (id serial PRIMARY KEY, data text);
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        INSERT INTO storm_test (data) VALUES ('row-' || i);
    END LOOP;
END $$;

-- Step 2: Check how many tuples lack hint bits
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 0) AS missing_hint_bits,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 0) / count(*), 1) AS missing_pct
FROM heap_page_items(get_raw_page('storm_test', 0))
WHERE t_xmin IS NOT NULL;

-- Step 3: Check CLOG-related I/O stats before reading
SELECT
    relname,
    heap_blks_read,
    heap_blks_hit,
    coalesce(heap_blks_hit::float / nullif(heap_blks_read + heap_blks_hit, 0) * 100, 0) AS hit_ratio_pct
FROM pg_statio_user_tables
WHERE relname = 'storm_test';

-- Step 4: Read all rows (this triggers hint bit setting + CLOG lookups)
SELECT count(*) FROM storm_test;

-- Step 5: Check I/O stats after
SELECT
    relname,
    heap_blks_read,
    heap_blks_hit,
    coalesce(heap_blks_hit::float / nullif(heap_blks_read + heap_blks_hit, 0) * 100, 0) AS hit_ratio_pct
FROM pg_statio_user_tables
WHERE relname = 'storm_test';

-- Step 6: Verify hint bits are now set
SELECT
    count(*) AS total_tuples,
    count(*) FILTER (WHERE t_infomask & 256 = 256) AS has_hint_bits,
    round(100.0 * count(*) FILTER (WHERE t_infomask & 256 = 256) / count(*), 1) AS hint_bit_pct
FROM heap_page_items(get_raw_page('storm_test', 0))
WHERE t_xmin IS NOT NULL;
```

### Hint Bit Flag Reference

| Bit | Hex | Decimal | Name | Meaning |
|-----|-----|---------|------|---------|
| 8 | 0x0100 | 256 | HEAP_XMIN_COMMITTED | Inserting transaction committed |
| 9 | 0x0200 | 512 | HEAP_XMIN_INVALID | Inserting transaction aborted |
| 10 | 0x0400 | 1024 | HEAP_XMAX_COMMITTED | Deleting transaction committed |
| 11 | 0x0800 | 2048 | HEAP_XMAX_INVALID | Row not deleted or delete aborted |

### Preventing Hint Bit Storms

| Strategy | How | Trade-off |
|----------|-----|-----------|
| Read traffic on replicas | Route some reads to replicas | Application changes needed |
| Autovacuum on replicas | Runs by default, sets hint bits | Extra I/O on replica |
| Pre-warm before failover | Run `SELECT count(*) FROM table` on replica | Planned failover only |
| `wal_log_hints = on` | Logs hint bit changes to WAL | More WAL volume (~10-20%) |

### Troubleshooting Table

| Symptom | Cause | Check | Fix |
|---------|-------|-------|-----|
| Slow reads after failover | Missing hint bits | `pg_statio_user_tables` for high `heap_blks_read` | Pre-warm with reads |
| `pg_rewind` fails | `wal_log_hints` off | `SHOW wal_log_hints` | Enable and restart |
| Elevated I/O after bulk INSERT | No hint bits on new rows | pageinspect on first page | Read the table once to set bits |
| Autovacuum not setting hint bits | Long-running transaction | `pg_stat_activity` for idle-in-transaction | Kill or configure timeout |

### Monitoring Query for Hint Bit Storms

```sql
-- Track I/O spikes that may indicate hint bit storms
SELECT
    schemaname,
    relname,
    heap_blks_read,
    heap_blks_hit,
    CASE
        WHEN heap_blks_read + heap_blks_hit > 0
        THEN round(100.0 * heap_blks_hit / (heap_blks_read + heap_blks_hit), 2)
        ELSE 0
    END AS cache_hit_ratio,
    idx_blks_read,
    idx_blks_hit
FROM pg_statio_user_tables
ORDER BY heap_blks_read DESC;
```

### Key Takeaways

1. **Hint bits are a performance cache, not a correctness mechanism**. PostgreSQL always produces correct answers with or without them — it's just slower without.
2. **The first reader after commit pays the CLOG lookup cost** and sets the hint bit for all future readers. This is why the first read after a commit is slightly slower.
3. **Replicas don't inherit hint bits** because they're not WAL-logged by default. This is the root cause of post-failover I/O storms.
4. **`wal_log_hints = on` is essential for `pg_rewind`** and recommended for any system using replication.
5. **Autovacuum sets hint bits as a side effect** — another reason to never disable it.
