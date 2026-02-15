# Step 1: Exploring the Process Model

## Understanding PostgreSQL's Architecture

PostgreSQL uses a **process-per-client** model. This is different from threads (MySQL) or async (Node.js).

### Key Concept: Postmaster → Backend Process Fork

When a client connects:
1. Client connects to postmaster (port 5432)
2. Postmaster authenticates the client
3. Postmaster **forks** a new backend process
4. Client communicates directly with the backend process
5. Postmaster goes back to listening for new connections

**Important**: Each fork creates a COPY of the parent process memory. That's why each connection uses ~10MB even before doing any work!

---

## Your Investigation

### 1. Check Running Processes

```bash
# From inside the container
docker exec -it postgres-arch bash

# See all Postgres processes
ps aux | grep postgres

# You should see something like:
# postgres   123  0.0  0.0  12345  6789 ?  Ss   12:00   0:00 /usr/local/bin/postgres
# postgres   456  0.0  0.0  12345  6789 ?  Ss   12:00   0:00 postgres: checkpointer
# postgres   789  0.0  0.0  12345  6789 ?  Ss   12:00   0:00 postgres: walwriter
# postgres   012  0.0  0.0  12345  6789 ?  Ss   12:00   0:00 postgres: autovacuum launcher
```

**Questions**:
1. Which process is the postmaster? (Look for the one with no extra label after "postgres:")
2. Which processes are background processes? (Look for labels like "checkpointer", "walwriter", "autovacuum")
3. How much memory (VSZ, RSS) is each process using?

### 2. Examine Process Details

```bash
# See detailed memory usage
ps aux --sort=-rss | grep postgres | head -10

# Check the postmaster PID
pgrep -f "^postgres" | head -1
```

**Understanding the columns**:
- `VSZ` = Virtual Memory Size (memory claimed, includes shared)
- `RSS` = Resident Set Size (actual physical RAM used)
- The difference often represents shared memory

### 3. Create Backend Processes

```sql
-- Connect to Postgres
docker exec -it postgres-arch psql -U postgres

-- Check current connections
SELECT pid, usename, application_name, state, query_start
FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- Open a SECOND terminal and connect again
-- docker exec -it postgres-arch psql -U postgres

-- Run the query again - notice the extra backend process
```

Now check from the host:
```bash
docker exec postgres-arch ps aux | grep postgres
```

You should see additional `postgres: postgres postgres [local] idle` processes!

### 4. Measure Per-Connection Memory

```sql
-- Check shared memory size (shared by all processes)
SHOW shared_buffers;  -- Usually 128MB default

-- Check work_mem (per-operation memory)
SHOW work_mem;  -- Usually 4MB default

-- Check maintenance_work_mem
SHOW maintenance_work_mem;  -- Usually 64MB default
```

**The Formula**:
```
Per-connection RAM ≈ Base process (~2-4MB)
                  + work_mem (per sort/hash operation)
                  + temporary buffers
                  + (some portion of shared_buffers is counted in RSS)

For 100 connections with 1 sort each using default work_mem:
100 × (4MB + 4MB) = ~800MB minimum
```

---

## Think About It

1. **Why does Postgres use processes instead of threads?**
   - Processes are isolated (crash in one doesn't affect others)
   - Easier to program and debug
   - Better for stability
   - Trade-off: Higher memory overhead

2. **What happens at 1000 connections?**
   - ~10GB RAM minimum just for process overhead
   - Context switching becomes expensive
   - Solution: Connection pooling (PgBouncer)

3. **How can you see the "fork" happening?**
   - Watch `pg_stat_activity` while connecting new clients
   - Each new client = new row with new `pid`

---

## Mini-Challenge

**Predict then verify**: If you open 10 simultaneous psql connections, how many NEW processes will you see?

```bash
# In one terminal, open 10 connections
for i in {1..10}; do
  docker exec postgres-arch psql -U postgres -c "SELECT 'Connection $i' AS status;" &
done
wait

# Check process count
docker exec postgres-arch ps aux | grep "postgres:" | grep -v "grep" | wc -l
```

Did you get what you expected?

<hr>

**Answer**:


You should see about 10 new `postgres: postgres postgres [local] idle` processes.
Each `psql` connection spawned a new backend process via fork.
