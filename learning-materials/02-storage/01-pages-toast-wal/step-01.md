# Step 1: Page Structure

## Understanding 8KB Pages

PostgreSQL stores data in **8KB pages** (default). This is a fundamental unit of I/O.

### Page Layout

```
+------------------+
|  Page Header     |  24 bytes - LSN, checksum, etc.
+------------------+
|  Line Pointers   |  2 bytes each - point to tuples
+------------------+
|  Free Space      |  Grows/shrinks as tuples added/removed
+------------------+
|  Tuple Data      |  Actual row data (grows upward)
+------------------+
```

### Key Concepts

- **ctid** = Physical location of a tuple `(page_number, offset_within_page)`
- Pages are numbered from 0
- Line pointers grow from the top down
- Tuple data grows from the bottom up

---

## Investigation

### 1. See Page Numbers and Offsets

```sql
-- Connect to postgres
docker exec -it postgres-storage psql -U postgres

-- Create test table
CREATE TABLE page_test (
    id SERIAL,
    name TEXT
);

INSERT INTO page_test (name) VALUES ('Alice'), ('Bob'), ('Charlie');

-- Check physical location (ctid)
SELECT id, name, ctid, pg_size_pretty(pg_column_size(name)) AS name_size
FROM page_test;
```

**Output example**:
```
 id |  name   | ctid  | name_size
----+---------+-------+-----------
  1 | Alice   | (0,1) | 8192 bytes
  2 | Bob     | (0,2) | 8192 bytes
  3 | Charlie | (0,3) | 8192 bytes
```

### 2. See How Many Pages Your Table Uses

```sql
-- Get page count
SELECT
    relname,
    relpages AS pages,
    reltuples AS approx_tuples,
    pg_size_pretty(pg_relation_size('page_test')) AS total_size
FROM pg_class
WHERE relname = 'page_test';
```

### 3. Fill a Page

```sql
-- Insert enough rows to fill pages
INSERT INTO page_test (name)
SELECT 'User_' || generate_series(1, 1000);

-- Check again
SELECT relpages, pg_size_pretty(pg_relation_size('page_test'))
FROM pg_class WHERE relname = 'page_test';

-- Sample output: ~8KB per page
-- 1000 small rows might use ~10 pages
```

### 4. Update and ctid Change

```sql
-- Find a row's ctid
SELECT id, ctid FROM page_test WHERE id = 1;

-- Update it
UPDATE page_test SET name = 'Updated_Alice' WHERE id = 1;

-- Check ctid again
SELECT id, ctid FROM page_test WHERE id = 1;
```

**Question**: Did the ctid change?

<hr>

**Answer**:


Maybe! If there's room on the same page, it stays. If not, it moves to a new page.
The old tuple becomes dead (MVCC).


---

## Mini-Experiment: Page Fragmentation

```sql
-- Create a scenario that causes page splits
CREATE TABLE fragmentation_test (
    id SERIAL PRIMARY KEY,
    data TEXT
) WITH (fillfactor = 50);  -- Leave pages half empty

-- Insert rows
INSERT INTO fragmentation_test (data)
SELECT repeat('x', 100) FROM generate_series(1, 1000);

-- Update many rows (might cause moves)
UPDATE fragmentation_test SET data = data || 'y';

-- Check table bloat
SELECT
    pg_size_pretty(pg_total_relation_size('fragmentation_test')) AS size,
    relpages
FROM pg_class WHERE relname = 'fragmentation_test';
```
