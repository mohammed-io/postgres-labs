# Step 1: How MVCC Creates Dead Index Entries

## Goal

Understand why every UPDATE creates dead entries in B-tree indexes, and why regular VACUUM doesn't fully solve index bloat.

---

## MVCC and Indexes: The Mechanism

When you UPDATE a row in PostgreSQL, the engine doesn't modify the existing row in place. Instead:

1. A **new tuple** is inserted into the heap (table)
2. The **old tuple** is marked as dead (by setting `xmax`)
3. For **each index** on the table, a **new index entry** is inserted pointing to the new tuple
4. The **old index entry** is marked as dead (but not removed)

```
Before UPDATE:
  Heap page 42:  [tuple v1 (id=100, status='active')]
  Index page 5:  [entry: 'active' → heap(42, v1)]

After UPDATE ... SET status = 'warning' WHERE id = 100:
  Heap page 42:  [tuple v1 (DEAD)]  [tuple v2 (id=100, status='warning')]
  Index page 5:  [entry: 'active' → heap(42, v1) DEAD]
  Index page 8:  [entry: 'warning' → heap(42, v2)]    ← new page if page 5 full
```

### Critical Insight: Every Index Gets a New Entry

Even if you only change `status`, the index on `metric_name` also gets a new entry pointing to the new heap tuple. The old entry for `metric_name` is marked dead.

```
UPDATE dashboard_metrics SET status = 'warning' WHERE id = 100;

Affects ALL 5 indexes:
  idx_dashboard_metric_name  → new entry (same value, new heap pointer)
  idx_dashboard_status       → new entry (new value 'warning')
  idx_dashboard_source       → new entry (same value, new heap pointer)
  idx_dashboard_recorded_at  → new entry (same value, new heap pointer)
  idx_dashboard_value        → new entry (same value, new heap pointer)
```

**5 dead index entries created from a single UPDATE** that changed only 1 indexed column.

---

## HOT Updates: The Exception

PostgreSQL has an optimization called **Heap-Only Tuple (HOT)** updates. When ALL of these conditions are true:

1. The new tuple fits on the **same heap page** as the old one
2. **No indexed column was changed**
3. There's enough free space on the page (controlled by `fillfactor`)

Then PostgreSQL skips creating new index entries entirely. The old tuple points to the new tuple via a chain, and the index still points to the original location.

```
HOT update (only non-indexed column changed, same page):
  Heap page 42:  [tuple v1 → HOT chain → tuple v2 → tuple v3]
  Index page 5:  [single entry pointing to page 42]  ← no new index entries!
```

**Problem:** HOT doesn't help when you update indexed columns like `status` or `metric_value`. And if pages are full (default `fillfactor=100`), even non-indexed updates can't use HOT because there's no room on the same page.

### Tuning for HOT

```sql
-- Leave 30% free space on each page for HOT updates
ALTER TABLE dashboard_metrics SET (fillfactor = 70);

-- Now non-indexed column updates (tags, updated_at) can use HOT
-- Reduces index bloat for those updates
```

**Trade-off:** Lower fillfactor means each heap page holds fewer rows, so sequential scans read more pages. Only use on tables with heavy UPDATE workloads.

---

## Why Regular VACUUM Doesn't Fix Index Bloat

Regular `VACUUM` does two things for indexes:

1. **Ambulatory index cleanup**: During the table vacuum pass, it marks dead index entries as `LP_DEAD` so they can be reused for future insertions at the same point in the B-tree key space.
2. **No compaction**: It does NOT merge underfull pages, reorder entries, or shrink the index. Page splits from the past remain forever.

```
Index before VACUUM:
  Page 5: [entry1, DEAD, entry3, DEAD, DEAD, entry6, DEAD, entry8]

Index after VACUUM:
  Page 5: [entry1, (reusable), entry3, (reusable), (reusable), entry6, (reusable), entry8]
  Page 5 is still allocated, still traversed during scans.
```

The index is still the same size. The dead slots are reusable, but the page count hasn't changed. An index scan still visits the same number of pages.

### B-tree Page Splits

When an index page is full and a new entry belongs on that page, PostgreSQL splits it:

```
Before split:
  Page 5: [a, b, c, d, e, f, g, h]  (100% full)

After inserting 'ci':
  Page 5: [a, b, c, d]              (50% full)
  Page 9: [ci, e, f, g, h]          (62.5% full)
```

Two pages where there was one. `VACUUM` cannot merge them back. Only `REINDEX` rebuilds the B-tree from scratch with optimal page fill.

---

## Investigation

### 1. See Index Sizes After Setup

```sql
-- Connect to the lab database
-- docker exec -it pg-index-bloat psql -U postgres -d labdb

SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### 2. Check Fragmentation with pgstatindex()

```sql
SELECT
    'idx_dashboard_status' AS index_name,
    pg_size_pretty(pg_relation_size('idx_dashboard_status')) AS size,
    pgstatindex('idx_dashboard_status');
```

The `pgstatindex()` function returns:
- `avg_leaf_density`: How full leaf pages are (100% = perfect, <50% = heavily bloated)
- `leaf_pages`: Number of leaf pages
- `internal_pages`: Number of internal (branch) pages
- `empty_pages`: Pages with no data (worst kind of bloat)
- `deleted_pages`: Pages marked for deletion but not reclaimed

### 3. Generate Some Bloat and Re-measure

```sql
-- Note current index sizes
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics';

-- Update all rows (changes status — indexed column, no HOT possible)
UPDATE dashboard_metrics SET status = 'archived', updated_at = NOW();

-- VACUUM to clean up heap, but NOT compact indexes
VACUUM dashboard_metrics;

-- Check index sizes again — they should have grown
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics';

-- Check fragmentation
SELECT * FROM pgstatindex('idx_dashboard_status');
```

---

## Key Takeaways

| Fact | Implication |
|------|-------------|
| Every UPDATE creates new entries in ALL indexes | Updating 1 row can create 5+ dead index entries |
| HOT updates skip index entry creation | Only works for non-indexed columns on same page |
| Regular VACUUM marks dead entries reusable but doesn't compact | Index size never shrinks with VACUUM alone |
| B-tree page splits create permanent fragmentation | REINDEX is the only fix |
| `fillfactor` controls HOT eligibility | Lower to 70-80% for UPDATE-heavy tables |

See `step-02.md` for how to detect and fix index bloat.
