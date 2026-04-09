---
name: "Index Bloat from MVCC"
category: "06-vacuum"
difficulty: "advanced"
time: "45 minutes"
concepts: ["index bloat", "MVCC", "dead index entries", "REINDEX", "index-only scans", "pgstatindex"]
---

# Index Bloat from MVCC

## Scenario

You're investigating why a dashboard query that used to take 5ms now takes 200ms. The query uses an index-only scan on `dashboard_metrics`, but `EXPLAIN ANALYZE` shows it's falling back to heap fetches instead of serving everything from the index.

The table has been heavily updated for months — status changes, metric_value corrections, tag updates. Regular `VACUUM` runs on schedule, keeping the table itself reasonably clean. But the indexes? They've quietly accumulated thousands of dead entries and fragmented pages. Index bloat is the culprit.

## Why This Lab Exists

Table bloat gets all the attention, but index bloat is its own distinct problem:

- **Indexes bloat independently of tables.** A regular `VACUUM` marks dead tuples for reuse in the heap, but it does NOT compact indexes. Index dead entries are only reclaimed lazily during subsequent index scans or during a full index vacuum pass.
- **Every UPDATE creates a new index entry** — even if the indexed column didn't change — unless PostgreSQL can use a HOT (Heap-Only Tuple) update. HOT only works when the new row fits on the same page AND no indexed column was modified.
- **Index bloat degrades index-only scans.** These scans rely on the visibility map to skip heap fetches. When an index page contains many dead entries pointing to dead heap tuples, the visibility map can't mark those pages as all-visible, forcing the executor to visit the heap for every entry.
- **B-tree page splits cause fragmentation.** When a page is 100% full (default fillfactor for indexes), inserting a new entry that belongs on that page causes a page split — the page is halved and a new page is allocated. This creates internal fragmentation that `VACUUM` cannot fix.
- **Detection is different from table bloat.** You need `pgstatindex()` to measure actual index fragmentation — `pg_stat_user_tables.n_dead_tup` only tracks heap dead tuples.

Without understanding index bloat, you'll misdiagnose performance problems: you'll see slow queries, blame the planner, add more indexes (making things worse), or try `VACUUM FULL` unnecessarily.

## Real-World Example

### Dashboard Metrics Table — Gradual Degradation

**Problem:** A metrics dashboard queries `dashboard_metrics` for the latest CPU usage across all servers. The query plan shows `Index Only Scan using idx_dashboard_status on dashboard_metrics`. After 6 months of constant updates (status changes, value corrections), the query regresses from 5ms to 200ms.

**Root cause:** Every `UPDATE` to `status` or `metric_value` creates a new index entry in the corresponding B-tree. The old entry is marked dead but not removed. Over time, the index grows to 2-3x its optimal size. The index-only scan must traverse more pages, and because many index entries point to non-all-visible heap pages, it falls back to heap fetches.

**Why VACUUM alone doesn't fix it:** Regular `VACUUM` marks dead heap tuples as reusable and updates the visibility map, but it does NOT compact or rebuild indexes. It performs a "lazy" index cleanup pass that marks dead index entries as reclaimable, but B-tree page fragmentation (from splits) persists until a `REINDEX`.

**Solution:** `REINDEX INDEX CONCURRENTLY idx_dashboard_status` rebuilds the index without locking the table for writes. Query returns to 5ms.

**What this teaches:** Index maintenance is separate from table maintenance. You need dedicated monitoring and tooling for index health.

## What You Will Build

```
Phase 1: [Index Bloat Mechanics]  - Understand how MVCC creates dead index entries
Phase 2: [Detection & REINDEX]    - Measure bloat with pgstatindex(), fix with REINDEX
```

## Quick Start

```bash
cd lab && docker compose up -d
# Wait for healthcheck to pass
docker exec -it pg-index-bloat psql -U postgres -d labdb
```

## Lab Flow

1. Read `step-01.md`: How MVCC Creates Dead Index Entries — understand the mechanism
2. Run `lab/break-it.sql` experiments 1-3 to generate real index bloat
3. Run `lab/explore.sql` to measure the bloat you've created
4. Read `step-02.md`: Detecting Index Bloat & When to REINDEX — learn detection and fixes
5. Run `lab/benchmark.sql` to compare performance before and after REINDEX
6. Run `lab/verify.sql` to validate your understanding
7. Check `solution.md` for the complete reference

## Learning Objectives

- Understand why MVCC creates dead entries in B-tree indexes
- Distinguish index bloat from table bloat (different causes, different fixes)
- Use `pgstatindex()` to measure index fragmentation
- Know when to use `REINDEX`, `REINDEX CONCURRENTLY`, or `VACUUM FULL`
- Understand why index bloat degrades index-only scans specifically
- Monitor `pg_stat_user_indexes` for early warning signs

## Index Bloat vs Table Bloat

| Aspect | Table Bloat | Index Bloat |
|--------|-------------|-------------|
| Cause | Dead tuples from UPDATE/DELETE | Dead entries + page splits in B-tree |
| Detection | `pg_stat_user_tables.n_dead_tup` | `pgstatindex()` — `avg_leaf_density` |
| Fixed by | `VACUUM` (reuses space) or `VACUUM FULL` (compacts) | `REINDEX` (rebuilds) or `REINDEX CONCURRENTLY` |
| Regular VACUUM | Marks dead space reusable | Lazy cleanup of dead index entries, no compaction |
| Impact | Sequential scans slower, more I/O | Index scans traverse more pages, index-only scans degrade |

## Your Tasks

1. Generate index bloat through realistic UPDATE patterns
2. Measure fragmentation with `pgstatindex()`
3. Compare query performance before and after REINDEX
4. Understand when REINDEX CONCURRENTLY is worth the overhead
