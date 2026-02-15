# Solution: Performance Tuning

## Real-World Tuning Scenarios

### Scenario 1: High-Traffic Web Application

**Symptoms**: Page loads slow during peak traffic.

**Diagnosis**:
```sql
-- Find slow queries
SELECT
    substr(query, 1, 60) AS query,
    calls,
    mean_exec_time AS avg_ms,
    rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY (calls * mean_exec_time) DESC
LIMIT 20;
```

**Real EXPLAIN Output (Before Fix)**:
```
Aggregate  (cost=0.00..52345.67 rows=1 width=16)
  (actual time=456.789..512.345 rows=1 loops=1)
  ->  Seq Scan on orders  (cost=0.00..50123.45 rows=500000 width=12)
       (actual time=150.234..450.123 rows=500000 loops=1)
         Filter: (created_at > NOW() - INTERVAL '30 days')
         Rows Removed by Filter: 450000
Planning Time: 0.234 ms
Execution Time: 512.567 ms
```

**Problem**: Full table scan on 500K row orders table, 450K rows filtered.

**Solution**:
```sql
-- Add partial index for recent data
CREATE INDEX idx_orders_recent
ON orders(created_at DESC)
WHERE created_at > NOW() - INTERVAL '90 days';

-- After fix: Index Scan on much smaller index
EXPLAIN ANALYZE
SELECT count(*) FROM orders
WHERE created_at > NOW() - INTERVAL '30 days';
-- Execution Time: 15.234 ms (33x faster!)
```

### Scenario 2: Connection Pool Issues

**Symptoms**: "FATAL: remaining connection slots are reserved"

**Diagnosis**:
```sql
-- Check connection usage
SELECT
    count(*) FILTER (WHERE state = 'active') AS active,
    count(*) FILTER (WHERE state = 'idle') AS idle,
    count(*) AS total,
    (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn
FROM pg_stat_activity;
```

**Result**: 90 active, 10 idle, max_connections = 100

**Problem**: Each connection = ~10MB RAM. Connection pool in app creates too many.

**Solution**:
```yaml
# docker-compose.yml with PgBouncer
services:
  postgres:
    image: postgres:17
    environment:
      - max_connections=200  # Higher for backend

  pgbouncer:
    image: pgbouncer/pgbouncer
    environment:
      - POOL_MODE=transaction
      - MAX_CLIENT_CONN=1000  # Many app connections
      - DEFAULT_POOL_SIZE=50    # Few Postgres connections
```

**Result**: 1000 app connections → 50 Postgres connections = 20× memory savings!

### Scenario 3: Memory Pressure

**Symptoms**: Queries slow when multiple users run large reports.

**Diagnosis**:
```sql
-- Check memory settings
SHOW shared_buffers;     -- 128MB (too low!)
SHOW work_mem;            -- 4MB (too low for big sorts!)
SHOW effective_cache_size; -- 128MB (underestimates!)

-- Check for disk spills
SELECT
    query,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_size
FROM pg_stat_statements
WHERE temp_bytes > 0;
```

**Solution** (for 16GB RAM server):
```sql
ALTER SYSTEM SET shared_buffers = '4GB';
ALTER SYSTEM SET effective_cache_size = '12GB';
ALTER SYSTEM SET work_mem = '64MB';
ALTER SYSTEM SET maintenance_work_mem = '1GB';

-- Reload and restart
SELECT pg_reload_conf();  -- For some settings
-- Others require restart (shared_buffers)
```

## Configuration Templates by Server Size

| RAM | shared_buffers | work_mem | effective_cache_size | maintenance_work_mem |
|-----|----------------|-----------|----------------------|---------------------|
| 4GB | 1GB | 16MB | 3GB | 256MB |
| 8GB | 2GB | 32MB | 6GB | 512MB |
| 16GB | 4GB | 64MB | 12GB | 1GB |
| 32GB | 8GB | 128MB | 24GB | 2GB |
| 64GB | 16GB | 256MB | 48GB | 4GB |

## Tuning Workflow

1. **Measure** → Use pg_stat_statements to find slow queries
2. **EXPLAIN** → Run EXPLAIN ANALYZE to see why
3. **Identify** → Find bottleneck (index missing, disk spill, lock contention)
4. **Fix** → Add index, tune config, rewrite query
5. **Verify** → Check pg_stat_statements again
6. **Repeat** → Performance tuning is iterative
