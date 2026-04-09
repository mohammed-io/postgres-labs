# Step 1: HOT Update Mechanics

## What is a HOT Update?

When PostgreSQL updates a row, it creates a **new tuple version** on disk. Normally, this means:

1. Write the new tuple somewhere on the heap
2. Update **every index entry** to point to the new tuple location
3. Mark the old tuple as dead

A **HOT (Heap-Only Tuple) update** skips step 2 entirely. The new tuple is placed on the **same page** as the old one, and a **HOT chain** connects them. The index still points to the **original line pointer** — which now chains to the new tuple.

```
Normal UPDATE (no HOT):
┌─────────────────┐          ┌─────────────────┐
│ Page 42         │          │ Page 87         │
│                 │          │                 │
│ Old tuple ──────┼── DEAD   │ New tuple (v2)  │
│                 │          │                 │
└─────────────────┘          └─────────────────┘
        ↑                            ↑
   Index entry (stale)         Index entry (new write!)

   Result: 1 heap write + N index writes (N = number of indexes)


HOT UPDATE:
┌─────────────────────────────────┐
│ Page 42                         │
│                                 │
│ Line pointer ──→ Old tuple (DEAD)──→ New tuple (v2)  │
│                                 │
└─────────────────────────────────┘
        ↑
   Index entry (unchanged!)

   Result: 1 heap write + 0 index writes
```

### Why This Matters

A table with 5 indexes and 500 updates/second:

| Update Type | Heap Writes/sec | Index Writes/sec | Total IOPS |
|-------------|----------------|------------------|------------|
| Non-HOT | 500 | 2,500 | 3,000 |
| HOT | 500 | 0 | 500 |

That's a **6x reduction in I/O**. Plus: less WAL, less bloat, less autovacuum pressure.

---

## HOT Eligibility Rules

A HOT update is possible **only when ALL of these conditions are met**:

| Condition | Why | What Breaks It |
|-----------|-----|----------------|
| New tuple fits on **same page** | HOT chain must stay within one page | Page is full (fillfactor=100), or row grew larger |
| **No indexed column** was changed | Index still points to correct line pointer | Any indexed column in the SET clause |
| No **TOAST compression change** | TOAST pointer must remain valid | Text value compressed/decompressed differently |
| Not excluded by **BRIN index** | BRIN has special recheck rules | BRIN index on the table (rare edge case) |

### The Indexed Column Rule is the Most Important

If a table has indexes on columns `(user_id, session_token, status, last_active)`, and you run:

```sql
-- HOT ELIGIBLE: only last_active changed, and last_active IS NOT indexed
UPDATE user_sessions SET last_active = NOW() WHERE id = 42;

-- NOT HOT ELIGIBLE: status has an index
UPDATE user_sessions SET status = 'idle', last_active = NOW() WHERE id = 42;
```

Even though `last_active` isn't indexed, changing `status` (which IS indexed) prevents HOT for the **entire row**. One indexed column change poisons the whole update.

---

## The HOT Chain

When a HOT update occurs, PostgreSQL creates a chain:

```
Line pointer (item pointer) → Tuple v1 (dead) → Tuple v2 (live) → Tuple v3 (live)
```

- The **line pointer** (index entry target) never changes
- Old tuple versions in the chain are dead and will be cleaned by VACUUM
- VACUUM can prune the chain: remove dead intermediaries, updating the line pointer to point to the latest live version

### Viewing HOT Chains

```sql
-- You can see HOT chains using the pageinspect extension
CREATE EXTENSION IF NOT EXISTS pageinspect;

-- Look at tuple headers on a specific page
SELECT
    lp AS line_pointer,
    t_xmin AS xmin,
    t_xmax AS xmax,
    t_ctid AS ctid_points_to,
    CASE
        WHEN t_ctid = (lp, 0) THEN 'latest version'
        ELSE 'points to row ' || (t_ctid).offset
    END AS chain_status
FROM heap_page_items(get_raw_page('user_sessions', 0))
ORDER BY lp;
```

**Reading the output:**
- `ctid_points_to` shows `(page, offset)` — if it points to itself, it's the latest version
- If it points to another offset, it's an old version in a HOT chain
- Multiple versions on the same page = HOT updates happened

---

## Measuring HOT Updates

PostgreSQL tracks HOT statistics in `pg_stat_user_tables`:

```sql
SELECT
    relname AS table_name,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE
        WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public';
```

**Interpreting the output:**
- `hot_ratio_pct` near 100% = excellent, almost all updates are HOT
- `hot_ratio_pct` near 0% = no HOT updates, every update hits all indexes
- The gap between total and hot updates = **avoidable index writes**

---

## Mini-Experiment

```sql
-- Run this in the lab database after setup.sql

-- Reset statistics
SELECT pg_stat_reset();

-- Update only a non-indexed column (HOT eligible)
UPDATE user_sessions SET last_active = NOW();

-- Check HOT ratio — should be near 0% with fillfactor=100!
-- Why? Pages are packed full, new tuple can't fit on same page.
SELECT
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 1) AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';
```

**Think about it:** Even though we only changed a non-indexed column, HOT didn't work. Why?

<details>
<summary>Answer</summary>

Because `fillfactor=100` (the default). Every page is packed full. When the new tuple version is created, there's no room on the same page. The new tuple goes to a different page, and all index entries must be updated.

This is exactly what step-02 solves.
</details>

---

## Key Takeaways

1. **HOT updates avoid all index writes** — the biggest I/O optimization for UPDATE-heavy tables
2. **Two requirements:** same page, no indexed column changed
3. **Default fillfactor=100 kills HOT** — pages are full, new versions can't fit
4. **One indexed column change kills HOT for the entire row** — even if other columns are fine
5. **Measure before optimizing** — check `n_tup_hot_upd / n_tup_upd` ratio

Next: [step-02.md](step-02.md) — How to configure fillfactor to enable HOT updates.
