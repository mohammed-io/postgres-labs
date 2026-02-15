# Solution: Pages, TOAST & WAL

## Complete Answers

### Task 1: Page Structure

**Page inspection**:
```sql
-- See ctid (physical location)
SELECT id, ctid FROM page_test;

-- Count pages
SELECT relpages FROM pg_class WHERE relname = 'page_test';

-- Page size is always 8KB
SHOW block_size;  -- 8192 bytes
```

**Key formulas**:
- Table size ≈ pages × 8KB
- ctid = (page_number, offset) where page_number starts at 0

### Task 2: TOAST

**Identify TOAST tables**:
```sql
SELECT
    t.relname AS table_name,
    pg_toast.relname AS toast_table,
    pg_size_pretty(pg_total_relation_size(t.relname::regclass)) AS main_size,
    pg_size_pretty(pg_total_relation_size(pg_toast.oid::regclass)) AS toast_size
FROM pg_class t
JOIN pg_class pg_toast ON t.reltoastrelid = pg_toast.oid
WHERE t.reltoastrelid != 0;
```

**TOAST thresholds**:
- Default `toast_tuple_target` = 2048 bytes (2KB)
- Column is compressed first
- If still > 2KB, moved to TOAST table
- TOAST table also uses 8KB pages

### Task 3: WAL Performance

**WAL settings for write performance**:
```sql
-- Faster writes (less safe)
SET synchronous_commit = off;      -- Don't wait for WAL to disk
SET wal_compression = on;          -- Compress WAL
SET wal_buffers = '256MB';         -- More WAL in memory

-- Slower writes (safer)
SET synchronous_commit = on;       -- Wait for WAL flush
SET full_page_writes = on;         -- Write full pages (safer)

-- Benchmark
\timing on
BEGIN;
INSERT INTO wal_test SELECT generate_series(1, 10000);
COMMIT;
```

### Task 4: Checkpoint Behavior

**Checkpoint impact**:
```sql
-- Checkpoint settings
SHOW checkpoint_timeout;        -- 5 minutes default
SHOW checkpoint_completion_target; -- 0.5 (50% of interval)

-- Force checkpoint
CHECKPOINT;

-- Check checkpoint stats
SELECT * FROM pg_stat_bgwriter;

-- Key metrics:
-- checkpoints_req: Number of requested checkpoints (bad)
-- checkpoints_timed: Number of scheduled checkpoints (good)
-- buffers_checkpoint: Buffers written during checkpoint
```

---

## Key Takeaways

| Concept | Key Point |
|---------|-----------|
| **8KB Pages** | Fundamental I/O unit. Rows spanning pages = more I/O. |
| **ctid** | Physical location. Changes on UPDATE. Don't rely on it. |
| **TOAST** | Large values moved to separate table. Main table keeps pointer. |
| **TOAST Penalty** | Accessing TOASTed columns = extra I/O. |
| **WAL** | Write-Ahead Log enables crash recovery. |
| **synchronous_commit** | Can disable for speed, risk data loss on crash. |
| **Checkpoints** | Flush dirty buffers to disk. Balance between I/O spread and recovery time. |
