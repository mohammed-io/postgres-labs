# Step 2: TOAST - The Oversized-Attribute Storage Technique

## What is TOAST?

Postgres pages are 8KB. What if a row is bigger than 8KB?

**TOAST** = The Oversized-Attribute Storage Technique

- Large column values are stored in a separate **TOAST table**
- Main table stores a pointer (like a foreign key reference)
- Compression is applied first (pGLZ algorithm)
- Only compressed values over ~2KB get TOAST'd

### TOAST Threshold

```sql
SHOW toast_tuple_target;  -- Default: 2KB
```

If a column value (compressed) exceeds this, it gets moved to TOAST.

---

## Investigation

### 1. Create a Row That TOASTs

```sql
docker exec -it postgres-storage psql -U postgres

-- Create table with potentially large column
CREATE TABLE toast_test (
    id SERIAL,
    name TEXT,           -- Won't TOAST (small)
    huge_data TEXT,      -- Will TOAST (large)
    json_data JSONB      -- Can TOAST
);

-- Insert a small row
INSERT INTO toast_test (name, huge_data, json_data)
VALUES ('Small row', 'hello', '{"key": "value"}');

-- Check storage
SELECT
    pg_column_size(name) AS name_bytes,
    pg_column_size(huge_data) AS huge_bytes,
    pg_column_size(json_data) AS json_bytes,
    pg_total_relation_size('toast_test') AS table_bytes
FROM toast_test
WHERE id = 1;
```

### 2. Force TOAST

```sql
-- Insert data larger than 2KB
INSERT INTO toast_test (name, huge_data, json_data)
VALUES (
    'Large row',
    repeat('x', 10000),  -- 10KB of 'x'
    ('{"data": "' || repeat('y', 5000) || '"}')::jsonb
);

-- Check storage again
SELECT
    pg_column_size(huge_data) AS huge_column_bytes,
    pg_total_relation_size('toast_test') AS table_bytes,
    pg_total_relation_size('pg_toast.pg_toast_' || (SELECT oid FROM pg_class WHERE relname = 'toast_test')) AS toast_bytes
FROM toast_test
WHERE id = 2;
```

### 3. Inspect TOAST Table

```sql
-- Find the TOAST table name
SELECT
    relname AS main_table,
    pg_toast.relname AS toast_table
FROM pg_class t
JOIN pg_class pg_toast ON t.reltoastrelid = pg_toast.oid
WHERE t.relname = 'toast_test';

-- Query the TOAST table directly (requires superuser)
SELECT
    pg_size_pretty(pg_column_size(chunk_id)) AS chunk_size
FROM pg_toast.pg_toast_12345  -- Replace with actual TOAST table name
LIMIT 5;
```

### 4. TOAST and Performance

```sql
-- Query that touches TOASTed data (slow!)
EXPLAIN ANALYZE
SELECT id, huge_data
FROM toast_test
WHERE huge_data LIKE '%xxxx%';

-- Query that only touches main table (fast!)
EXPLAIN ANALYZE
SELECT id, name
FROM toast_test
WHERE name = 'Large row';
```

**Key Insight**: Accessing TOASTed columns requires extra I/O to the TOAST table.

---

## TOAST Storage Options

```sql
-- Check TOAST strategies
SELECT
    relname,
    CASE reltoastrelid
        WHEN 0 THEN 'No TOAST needed (columns all small)'
        ELSE reltoastrelid::regclass::text
    END AS toast_table,
    reltoastrelid AS toast_oid
FROM pg_class
WHERE relname LIKE 'toast%';

-- TOAST has 4 strategies:
-- 1. PLAIN - Don't toast, don't compress
-- 2. EXTENDED - Allow toast, allow compression (default)
-- 3. EXTERNAL - Allow toast, no compression (good for long text)
-- 4. MAIN - Allow compression but discourage toast

-- Example: Change TOAST strategy
ALTER TABLE toast_test ALTER COLUMN huge_data SET STORAGE EXTENDED;
ALTER TABLE toast_test ALTER COLUMN name SET STORAGE PLAIN;
```

---

## Mini-Challenge

**Predict**: If you have a table with 1 million rows, each with a 50KB JSONB column:
- How large will the main table be (approximately)?
- How large will the TOAST table be?
- What happens when you SELECT just the ID column?

<hr>

**Answer**:


- Main table: ~8MB (1M × ~8 bytes per row for ID + pointer)
- TOAST table: ~50GB (1M × 50KB)
- SELECT ID only touches main table (~8MB I/O), doesn't read TOAST!
