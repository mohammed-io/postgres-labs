---
name: "Pages, TOAST & WAL"
category: "02-storage"
difficulty: "intermediate"
time: "75 minutes"
concepts: ["pages", "tuples", "TOAST", "WAL", "file layout", "checkpoint"]
---

# Pages, TOAST & WAL

## Scenario

You're investigating:
1. Why queries on a table with large JSONB columns are slow
2. What happens when a row exceeds 8KB
3. How WAL affects write performance
4. Understanding disk layout for backup planning

Your job is to understand how PostgreSQL physically stores data.

## Why This Lab Exists

Most tutorials focus on SQL queries and performance tuning, but storage mechanics are equally important:
- Understanding page structure helps optimize queries
- Knowing TOAST behavior explains why some columns cause slow scans
- WAL knowledge is critical for backup/recovery and replication
- Checkpoint tuning balances I/O performance and crash recovery speed

Without understanding these basics, you can't properly diagnose storage-related performance issues or design efficient backup strategies.

## Real-World Example

### 1. Large JSONB Columns Causing Slow Queries

**Problem:** A table with `metadata JSONB` averaging 50KB per row. Querying by ID takes 50ms instead of expected 5ms.

**Root cause:** Each heap fetch reads the entire 50KB TOAST chunk even though only a small portion of the JSON is needed. This is inefficient I/O.

**Solution:** Use INCLUDE indexes or select only needed columns.

**What this teaches:** TOAST stores oversized values separately. If you query a TOAST column frequently, consider INCLUDE indexes or select specific columns.

### 2. Storage Bloat After Mass Updates

**Problem:** Running `UPDATE products SET status = 'processed'` on 1M rows doubles the table size. Dead tuples not cleaned up.

**Root cause:** Autovacuum interval too long for high-write workload. Table shows `n_dead_tup > n_live_tup` in `pg_stat_user_tables`.

**Solution:** Tune autovacuum settings or run manual VACUUM.

**What this teaches:** Page splits and dead tuples accumulate over time. Understanding page layout helps diagnose fragmentation.

### 3. WAL Disk Filling Up

**Problem:** High write traffic (10K writes/sec) causes WAL to grow at 1GB/min, filling disk.

**Root cause:** Checkpoint interval too long, `wal_buffers` too small. WAL needs to accumulate enough data before checkpoints, but if they're infrequent, WAL grows without bound.

**Solution:** Adjust `checkpoint_timeout`, `max_wal_size`, and `wal_buffers`.

**What this teaches:** WAL is crucial for crash recovery and replication. If it fills disk, you lose both current data and recovery capability.

### 4. Page Splits Causing Fragmentation

**Problem:** Table with `fillfactor=100` (default). Updates cause rows to grow, needing new pages. Table has 50% empty space but no room for new updates.

**Root cause:** No space reserved for growth. When a row expands, it moves to a new page, leaving behind partially filled old pages.

**Solution:** Lower `fillfactor` to 80-90 for frequently updated tables.

**What this teaches:** Page structure with line pointers. Understanding how rows fit in pages helps optimize storage.

## What You Will Build

```
Phase 1: [Page Structure Analysis] - Examine 8KB pages, tuples, line pointers
Phase 2: [TOAST Investigation] - Create large rows, see how they're stored
Phase 3: [WAL Performance] - Measure write throughput with different settings
Phase 4: [Checkpoint Behavior] - Observe I/O patterns and recovery time
```

## Quick Start

```bash
cd postgres-deep-dive/learning-materials/02-storage/01-pages-toast-wal/lab
docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: Explore Page Structure - examine 8KB pages, tuples, line pointers
2. Read `step-02.md`: Understand TOAST - create rows larger than 8KB, see storage mechanism
3. Read `step-03.md`: WAL Impact on Performance - measure write throughput with different settings
4. Read `step-04.md`: Checkpoint Behavior - observe I/O patterns and recovery time
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens when page limits are exceeded

## Learning Objectives

Understand how PostgreSQL physically stores data on disk.

### When This Matters

1. **Large JSONB columns causing slow queries**
   - Table with `metadata JSONB` column averaging 50KB per row
   - Query `SELECT id, metadata FROM users WHERE id = ?` takes 50ms
   - Problem: Each heap fetch reads entire 50KB TOAST chunk
   - Solution: Use INCLUDE index or select only needed columns

2. **Storage bloat after mass updates**
   - `UPDATE products SET status = 'processed'` for 1M rows
   - Table size doubles: dead tuples not cleaned up
   - Investigation: `n_dead_tup > n_live_tup` in `pg_stat_user_tables`
   - Solution: Tune autovacuum or run manual VACUUM

3. **WAL disk filling up**
   - High write traffic: 10K writes/sec
   - WAL grows at 1GB/min, filling disk
   - Checkpoint interval too long, wal_buffers too small
   - Solution: Adjust `checkpoint_timeout`, `max_wal_size`

4. **Page splits causing fragmentation**
   - Table with `fillfactor=100` (default)
   - Updates cause row to grow, needs new page
   - Result: Table has 50% empty space but no room for updates
   - Solution: Lower fillfactor for frequently updated tables

## Your Tasks

### Task 1: Explore Page Structure

Examine how rows are stored within 8KB pages.

### Task 2: Understand TOAST

Create rows larger than 8KB and see how Postgres handles them.

### Task 3: WAL Impact on Performance

Measure write performance with different WAL settings.

### Task 4: Checkpoint Behavior

Observe how checkpoints affect I/O and recovery time.

## Getting Started

```bash
cd postgres-deep-dive/learning-materials/02-storage/01-pages-toast-wal/lab
docker-compose up -d
```

## Verification

```bash
docker exec postgres-storage psql -U postgres -f lab/verify.sql
```
