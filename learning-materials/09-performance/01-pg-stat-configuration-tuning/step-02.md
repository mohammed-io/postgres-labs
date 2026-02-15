# Step 2: Configuration Tuning

## Key Configuration Parameters

| Setting | Default | For OLTP | For Analytics | For Low RAM |
|---------|---------|----------|---------------|-------------|
| `shared_buffers` | 128MB | 25% of RAM (up to 8GB) | 4-8GB | 1GB |
| `effective_cache_size` | 128MB | 75% of RAM | 70% of RAM | 2GB |
| `work_mem` | 4MB | 16-64MB | 256MB-1GB | 4MB |
| `maintenance_work_mem` | 64MB | 512MB-2GB | 2GB+ | 128MB |
| `checkpoint_completion_target` | 0.5 | 0.7-0.9 | 0.9 | 0.7 |
| `random_page_cost` | 4.0 | 1.1 (SSD) | 1.1 (SSD) | 2.0 |

---

## Investigation

### 1. Current Configuration Check

```sql
docker exec -it postgres-perf psql -U postgres

-- Show all settings
SHOW ALL;

-- Show specific settings
SHOW shared_buffers;
SHOW work_mem;
SHOW effective_cache_size;
SHOW random_page_cost;
SHOW checkpoint_completion_target;
```

### 2. Tune work_mem

**Problem**: Sort operations spilling to disk.

**Sign**: High `temp_bytes` in `pg_stat_statements`.

```sql
-- Check for disk spills
SELECT
    query,
    calls,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_statements
WHERE temp_bytes > 0
ORDER BY temp_bytes DESC
LIMIT 10;
```

**Solution**: Increase `work_mem` per operation:

```sql
-- Per session
SET work_mem = '256MB';

-- Per function
CREATE FUNCTION my_function()
RETURNS void AS $$
BEGIN
    SET LOCAL work_mem = '256MB';
    -- Do heavy sorting...
END;
$$ LANGUAGE plpgsql;

-- Globally (restart required)
ALTER SYSTEM SET work_mem = '64MB';
SELECT pg_reload_conf();
```

**Caution**: `work_mem` is per SORT/HASH operation. A query with 5 hash joins uses 5× work_mem!

### 3. Tune Checkpoint Settings

**Problem**: Frequent checkpoints causing I/O spikes.

```sql
-- Check checkpoint stats
SELECT
    checkpoints_timed,
    checkpoints_req,
    checkpoint_write_time,
    checkpoint_sync_time,
    buffers_checkpoint,
    buffers_written_by_backend,
    buffers_clean
FROM pg_stat_bgwriter;
```

**Solution**: Spread out checkpoint I/O:

```sql
ALTER SYSTEM SET checkpoint_completion_target = 0.9;  -- Spread over 90% of interval
ALTER SYSTEM SET checkpoint_timeout = '15min';           -- Less frequent checkpoints
```

### 4. Tune random_page_cost

**Problem**: Planner not using indexes on SSD.

```sql
-- Current setting
SHOW random_page_cost;  -- Default: 4.0

-- For SSD, cost of random I/O is closer to sequential
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET seq_page_cost = 1.0;
```

**Impact**: Planner more likely to use indexes on SSD storage.

### 5. Tune Autovacuum for Performance

**Problem**: Autovacuum not keeping up with write workload.

```sql
-- Make autovacuum more aggressive
ALTER SYSTEM SET autovacuum_max_workers = 4;
ALTER SYSTEM SET autovacuum_naptime = '5s';
```

---

## Real-World Tuning Scenario

**Problem**: E-commerce site slow after Black Friday sale.

**Investigation**:
```sql
-- Find slow queries
SELECT * FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 5;

-- Result: Full table scans on orders table
```

**Solution**:
```sql
-- Add missing index
CREATE INDEX idx_orders_customer_date
ON orders(customer_id, created_at DESC);

-- Increase work_mem for large sorts
ALTER SYSTEM SET work_mem = '128MB';

-- Check result
SELECT mean_exec_time
FROM pg_stat_statements
WHERE query LIKE '%orders%';
-- Dropped from 500ms to 5ms!
```

See solution.md for complete tuning guide.
