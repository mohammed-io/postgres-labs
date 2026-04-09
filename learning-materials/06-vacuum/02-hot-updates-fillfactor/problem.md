---
name: "HOT Updates & Fillfactor Tuning"
category: "06-vacuum"
difficulty: "advanced"
time: "45 minutes"
concepts: ["HOT updates", "fillfactor", "heap-only tuple", "write amplification", "page space"]
---

# HOT Updates & Fillfactor Tuning

## Scenario

You're a DBA at a SaaS company. The `user_sessions` table tracks active users across 50,000 concurrent sessions. On every HTTP request, the `last_active` column is updated — that's **~500 updates/second** hitting a single table.

The table has 5 indexes:
- Primary key on `id`
- Index on `user_id`
- Index on `session_token` (lookup)
- Index on `status` (filtering)
- Index on `last_active` (range scan for expiry)

Even though only `last_active` changes, all 5 indexes get rewritten on every UPDATE. Your autovacuum can barely keep up. I/O throughput is 3x what it should be.

**Why?** PostgreSQL's default `fillfactor=100` packs pages completely full. When a row is updated, the new version almost never fits on the same page — so PostgreSQL writes a new heap tuple *and* updates every single index entry. This is **write amplification**.

You need to understand **HOT (Heap-Only Tuple) updates** — PostgreSQL's mechanism for updating a row without touching any index — and configure `fillfactor` to make HOT updates possible.

## Why This Lab Exists

Non-HOT updates are one of the biggest hidden costs in PostgreSQL:

| Problem | Impact |
|---------|--------|
| Every UPDATE rewrites all index entries | 5 indexes × 500 updates/sec = 2,500 index writes/sec |
| Dead tuples accumulate faster | Autovacuum falls behind |
| Table + indexes bloat rapidly | Disk usage grows 3-5x |
| WAL volume explodes | Replication lag increases |
| CPU wasted on index traversal | Query throughput degrades |

A single `fillfactor` change can eliminate most of this overhead. But it only works if you understand **when HOT is eligible** and **what trade-offs you're making**.

## Real-World Examples

### Example 1: Session Table Write Amplification

**Problem:** A SaaS app updates `user_sessions.last_active` on every request. With 5 indexes and `fillfactor=100`, zero HOT updates occur. Every UPDATE causes 6 page writes (1 heap + 5 index).

**Fix:** Set `fillfactor=80` on the table. HOT update ratio jumps to ~95%. Write I/O drops by 80%.

**Lesson:** If you're updating non-indexed columns on a table with multiple indexes, HOT updates are the single biggest optimization you can make.

### Example 2: Status Column Updates Kill HOT

**Problem:** Same session table, but a developer adds an index on `status` and starts toggling `status` between `'active'` and `'idle'`. HOT ratio drops to 0% overnight.

**Fix:** Remove the index on `status` if it's not needed for queries. Or accept the cost and budget for more I/O.

**Lesson:** Changing **any indexed column** prevents HOT updates for the entire row. Even one indexed column change kills HOT for all other columns too.

### Example 3: Fillfactor Too Low

**Problem:** A DBA sets `fillfactor=50` on a 100M-row table "just to be safe." Table size doubles from 40GB to 80GB. Sequential scans take twice as long. Cache hit ratio drops.

**Fix:** Set `fillfactor=85` instead. HOT ratio stays at ~80%, but table only grows 18%.

**Lesson:** Fillfactor is a trade-off. Every point below 100 wastes space. Measure your actual HOT ratio and pick the smallest reduction that gives acceptable results.

## What You Will Learn

```
Phase 1: [HOT Mechanics]     - Understand when and why HOT updates work
Phase 2: [Fillfactor Tuning] - Configure fillfactor and measure the results
```

## Quick Start

```bash
cd lab && docker-compose up -d

# Wait for healthcheck
docker exec -it pg-hot-updates psql -U postgres -d labdb -c "SELECT 1"
```

## Lab Flow

1. Read `step-01.md` — Understand HOT update mechanics and eligibility rules
2. Run `lab/setup.sql` — Create the `user_sessions` table with indexes and data
3. Run `lab/explore.sql` — Inspect HOT statistics and page contents
4. Read `step-02.md` — Learn fillfactor tuning and trade-offs
5. Run `lab/benchmark.sql` — Measure update throughput at different fillfactor values
6. Run `lab/verify.sql` — Validate your understanding with checks
7. Run `lab/break-it.sql` — See what happens when you break HOT eligibility

## Learning Objectives

- Explain what a HOT update is and why it avoids index writes
- List all conditions required for HOT eligibility
- Query `pg_stat_user_tables` to measure HOT ratios
- Configure `fillfactor` for a table and explain the trade-off
- Identify when HOT updates are *not* possible (indexed column changes)
- Diagnose write amplification from non-HOT updates

## Prerequisites

- Completion of `06-vacuum/01-autovacuum-bloat-visibility-map` (or equivalent MVCC knowledge)
- Understanding that UPDATE creates a new tuple version
- Basic familiarity with `pg_stat_user_tables`

## Your Tasks

1. Set up the lab environment
2. Observe HOT vs non-HOT updates in action
3. Tune fillfactor and measure the impact
4. Understand when HOT breaks down
5. Break things intentionally to deepen understanding
