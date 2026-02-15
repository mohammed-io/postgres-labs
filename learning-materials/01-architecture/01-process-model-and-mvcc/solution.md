# Solution: PostgreSQL Process Model & MVCC

## Complete Answers

### Task 1: Process Model

**Identifying processes**:
```bash
docker exec postgres-arch ps aux | grep postgres

# Output breakdown:
# postgres (parent, postmaster)    - Listens for connections
# postgres: checkpointer           - Writes dirty buffers to disk
# postgres: walwriter              - Writes WAL to disk
# postgres: autovacuum launcher    - Launches autovacuum workers
# postgres: postgres postgres      - Backend processes (one per connection)
```

**Memory per connection**:
```sql
-- Check configuration
SHOW shared_buffers;      -- Shared by all (default: 128MB)
SHOW work_mem;            -- Per sort/hash operation (default: 4MB)
SHOW maintenance_work_mem; -- For vacuum operations (default: 64MB)

-- Approximate per-connection memory:
-- Base process: ~2-4MB
-- Plus work_mem × (number of sorts/hashes in query)
-- Plus temporary buffer space
```

### Task 2: MVCC Demonstration

**Non-blocking reads**:
```sql
-- Terminal 1
BEGIN;
SELECT txid_current();  -- e.g., 500
SELECT * FROM mvcc_demo WHERE id = 1;  -- Sees balance = 1000.00

-- Terminal 2 (while Terminal 1 is still in transaction)
BEGIN;
UPDATE mvcc_demo SET balance = 1500.00 WHERE id = 1;
COMMIT;  -- Transaction ID 501

-- Back to Terminal 1 (still in transaction 500)
SELECT * FROM mvcc_demo WHERE id = 1;  -- Still sees balance = 1000.00!
COMMIT;
```

**Dead tuples**:
```sql
-- Check for dead tuples
SELECT n_dead_tup, n_live_tup, n_tup_ins, n_tup_upd, n_tup_del
FROM pg_stat_user_tables
WHERE relname = 'mvcc_demo';

-- Each UPDATE creates:
-- - 1 new live tuple
-- - 1 dead tuple (old version)

-- Manual cleanup
VACUUM mvcc_demo;

-- Verify cleanup
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'mvcc_demo';
```

### Task 3: Background Processes

**Autovacuum**:
```sql
-- Check if autovacuum is running
SELECT pid, datname, relid, relname
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker';

-- What it does:
-- - Removes dead tuples
-- - Updates transaction ID wraparound protection
-- - Analyzes table statistics

-- Trigger autovacuum manually
VACUUM ANALYZE mvcc_demo;
```

**WAL Writer**:
```sql
-- Check WAL activity
SELECT pg_current_wal_lsn();  -- Current WAL position

-- What it does:
-- - Writes transaction log to disk
-- - Enables crash recovery
-- - Enables replication

-- Check WAL size
SELECT pg_size_pretty(pg_wal_file_size());
```

**Checkpointer**:
```sql
-- Check last checkpoint
SELECT * FROM pg_stat_bgwriter;

-- What it does:
-- - Writes dirty shared_buffers to disk
-- - Creates a known good point for recovery
-- - Reduces recovery time

-- Trigger checkpoint manually
CHECKPOINT;
```

### Task 4: Connection Limits

**Testing connection limits**:
```sql
-- Check max_connections
SHOW max_connections;  -- Default: 100

-- Check current connections
SELECT count(*) FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- What happens at limit?
-- Connection 101 gets: "FATAL: sorry, too many clients already"
```

**Solution: Connection Pooling**

```yaml
# docker-compose with PgBouncer
services:
  pgbouncer:
    image: pgbouncer/pgbouncer
    environment:
      - DATABASES_HOST=postgres-arch
      - POOL_MODE=transaction
      - MAX_CLIENT_CONN=400
      - DEFAULT_POOL_SIZE=25
    ports:
      - "6432:6432"
```

**Benefits**:
- 400 app connections → 25 Postgres connections
- ~16x memory savings
- Better connection reuse

---

## Key Takeaways

| Concept | Production Impact |
|---------|-------------------|
| **Process model** | Each connection = ~10MB. Limit connections or use pooling. |
| **MVCC** | Readers don't block writers, but creates dead tuples. |
| **Autovacuum** | Essential for cleaning dead tuples. Don't disable it! |
| **Long transactions** | Prevent vacuum from working. Keep them short. |
| **Connection pooling** | Required for scaling to thousands of users. |
