# Step 1: Understanding Autovacuum Triggers

## What Triggers Autovacuum?

Autovacuum runs when thresholds are exceeded:

| Trigger | Default | Meaning |
|---------|---------|---------|
| `autovacuum_vacuum_threshold` | 50 rows | Minimum dead tuples before vacuum |
| `autovacuum_vacuum_scale_factor` | 0.2 (20%) | Additional: 20% of table size |
| `autovacuum_analyze_threshold` | 50 rows | Minimum changes before analyze |
| `autovacuum_analyze_scale_factor` | 0.1 (10%) | Additional: 10% of table size |

### Formula

```
Vacuum triggers when: dead_tuples > threshold + (scale_factor × reltuples)

For 1M row table with defaults:
50 + (0.2 × 1,000,000) = 200,050 dead tuples needed!
```

---

## Investigation

### 1. Check Autovacuum Configuration

```sql
docker exec -it postgres-vacuum psql -U postgres

-- See all autovacuum settings
SELECT
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE '%autovacuum%'
ORDER BY name;
```

### 2. See When Autovacuum Last Ran

```sql
SELECT
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
    last_autovacuum,
    last_vacuum,
    autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC;
```

**Real output example**:
```
 tablename      | live_tuples | dead_tuples | dead_pct | last_autovacuum
----------------+-------------+-------------+----------+-------------------
 user_sessions  |      100000  |      500000  |    83.33 | 2025-01-15 10:30:00
 orders         |      50000   |       1000   |     1.96 | 2025-01-15 10:15:00
```

**Problem**: `user_sessions` has 83% dead tuples but no recent vacuum!

### 3. Check If Autovacuum is Running

```sql
-- Active autovacuum workers
SELECT
    pid,
    datname,
    relid::regclass AS table_name,
    phase,
    rollback_status
FROM pg_stat_progress_vacuum
WHERE datname IS NOT NULL;
```

### 4. Understand Table-Level Overrides

```sql
-- Check for custom autovacuum settings
SELECT
    schemaname,
    tablename,
    reloptions
FROM pg_class
JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
WHERE pg_namespace.nspname = 'public'
    AND reloptions IS NOT NULL;
```

---

## Mini-Experiment

```sql
-- Create a table with aggressive autovacuum
CREATE TABLE test_autovacuum (
    id SERIAL,
    data TEXT
) WITH (
    autovacuum_vacuum_threshold = 100,
    autovacuum_vacuum_scale_factor = 0.01  -- 1%
);

-- Insert data
INSERT INTO test_autovacuum (data)
SELECT repeat('x', 1000) FROM generate_series(1, 10000);

-- Update (creates dead tuples)
UPDATE test_autovacuum SET data = data || 'y';

-- Check: Autovacuum should run soon
SELECT * FROM pg_stat_user_tables WHERE relname = 'test_autovacuum';
```

See solution.md for how to tune for production.
