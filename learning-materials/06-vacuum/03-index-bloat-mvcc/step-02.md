# Step 2: Detecting Index Bloat and When to REINDEX

## Goal

Learn to measure index bloat accurately, understand when to intervene, and choose the right REINDEX strategy.

---

## Detection: Three Methods

### Method 1: pgstatindex() — Direct Fragmentation Measurement

The most accurate way to measure index bloat. Requires the `pgstattuple` extension.

```sql
-- Detailed fragmentation report for one index
SELECT * FROM pgstatindex('idx_dashboard_status');
```

Key fields to watch:

| Field | Healthy | Bloated | Meaning |
|-------|---------|---------|---------|
| `avg_leaf_density` | 90%+ | <50% | How full leaf pages are on average |
| `leaf_pages` | Matches expected | 2-3x expected | Number of leaf-level B-tree pages |
| `empty_pages` | 0 | >0 | Pages allocated but containing no data |
| `deleted_pages` | 0 | >0 | Pages awaiting deallocation |

**Rule of thumb:** If `avg_leaf_density` < 50%, the index needs a REINDEX.

### Method 2: pg_stat_user_indexes — Scan Efficiency

Monitor how effectively your indexes are being used:

```sql
SELECT
    indexrelname AS index_name,
    idx_scan AS total_scans,
    idx_tup_read AS entries_read,
    idx_tup_fetch AS heap_tuples_fetched,
    CASE
        WHEN idx_tup_read > 0
        THEN round(idx_tup_fetch::numeric / idx_tup_read, 3)
        ELSE 0
    END AS fetch_ratio,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY idx_tup_read DESC;
```

**Reading the ratio:**
- `idx_tup_read`: Number of index entries read during scans
- `idx_tup_fetch`: Number of heap tuples fetched (for non-index-only scans)
- If `idx_tup_read >> idx_tup_fetch`: Many dead entries read from index but skipped at heap
- High `idx_tup_read` relative to actual result size = index contains many dead entries

### Method 3: Size Comparison — Quick Sanity Check

```sql
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_size_pretty(pg_relation_size('dashboard_metrics')) AS table_size,
    round(
        100.0 * pg_relation_size(indexrelid)
        / pg_relation_size('dashboard_metrics'),
        1
    ) AS pct_of_table
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;
```

An index larger than the table (or larger than expected for the column cardinality) is a sign of bloat.

---

## Index-Only Scan Degradation

Index-only scans are the canary in the coal mine for index bloat. Here's why:

**How index-only scans work:**
1. Read entries from the index
2. Check the visibility map — if the heap page is all-visible, skip the heap fetch
3. Return data directly from the index

**How bloat breaks this:**
1. Dead index entries point to dead heap tuples on pages that may still have live tuples
2. Those pages aren't all-visible in the visibility map (because they contain dead tuples)
3. Even after VACUUM, if the index still has entries pointing to many different pages, more heap pages need to be all-visible
4. The executor falls back to heap fetches for every index entry it's unsure about

```sql
-- Check if index-only scans are degrading
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'active'
GROUP BY status;
```

Look for:
- `Index Only Scan` → good, reading from index alone
- `Heap Fetches: N` → N should be near 0 for an optimal index-only scan
- If Heap Fetches is high, the visibility map doesn't cover the relevant pages

---

## Fixing Index Bloat

### Option 1: REINDEX INDEX (Blocking)

```sql
REINDEX INDEX idx_dashboard_status;
```

- **Lock:** `ACCESS EXCLUSIVE` on the index — blocks all reads and writes on the table
- **Speed:** Fastest rebuild method
- **When to use:** Maintenance windows, tables that can tolerate downtime

### Option 2: REINDEX INDEX CONCURRENTLY (Non-Blocking)

```sql
REINDEX INDEX CONCURRENTLY idx_dashboard_status;
```

- **Lock:** Only brief `SHARE UPDATE EXCLUSIVE` locks — table remains readable and writable
- **How it works:** Builds a new index alongside the old one, then atomically swaps
- **Overhead:** Takes longer, uses more disk space (old + new index exist simultaneously)
- **When to use:** Production systems, 24/7 availability requirements, large indexes

**Trade-off comparison:**

| Aspect | REINDEX | REINDEX CONCURRENTLY |
|--------|---------|---------------------|
| Write lock | Yes (blocks all writes) | No |
| Read lock | Yes (blocks all reads) | Brief locks only |
| Duration | Faster | Slower (2x-3x) |
| Disk usage | Same size temporarily | 2x index size during rebuild |
| Failure | Clean rollback | Leaves INVALID index if interrupted |
| Can run in transaction | Yes | No |

### Option 3: VACUUM FULL (Nuclear Option)

```sql
VACUUM FULL dashboard_metrics;
```

- **Lock:** `ACCESS EXCLUSIVE` on the entire table — blocks everything
- **Side effect:** Rebuilds ALL indexes as part of table rewrite
- **When to use:** When both table AND all indexes are bloated and you have a maintenance window
- **Avoid:** If only indexes are bloated (use REINDEX instead — faster, more targeted)

### Option 4: pg_repack (External Tool)

```sql
-- Requires pg_repack extension
-- Not available in this lab's Docker image
```

- Rebuilds tables and indexes with minimal locking
- Requires additional extension and disk space
- Best for production environments where even REINDEX CONCURRENTLY is too slow

---

## Monitoring Query: Find Top Bloated Indexes

Run this periodically to catch bloat early:

```sql
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS scans,
    idx_tup_read AS tuples_read,
    coalesce(
        round(
            (pgstatindex(indexrelname)).avg_leaf_density
        ),
        0
    ) AS avg_leaf_density_pct,
    CASE
        WHEN (pgstatindex(indexrelname)).avg_leaf_density < 50 THEN 'CRITICAL'
        WHEN (pgstatindex(indexrelname)).avg_leaf_density < 70 THEN 'WARNING'
        ELSE 'OK'
    END AS bloat_status
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
    AND pg_relation_size(indexrelid) > 1024 * 1024  -- only indexes > 1MB
ORDER BY (pgstatindex(indexrelname)).avg_leaf_density
    NULLS LAST;
```

---

## Prevention Strategies

### 1. Tune fillfactor for UPDATE-Heavy Tables

```sql
ALTER TABLE dashboard_metrics SET (fillfactor = 75);
```

Leaves 25% free space per page for HOT updates. Only helps for updates that don't change indexed columns.

### 2. Tune autovacuum Aggressiveness

```sql
ALTER TABLE dashboard_metrics SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 1000
);
```

More frequent vacuuming = dead index entries cleaned up sooner = less opportunity for page splits.

### 3. Avoid Updating Indexed Columns Unnecessarily

```sql
-- BAD: Updates indexed column even when value unchanged
UPDATE dashboard_metrics SET status = status WHERE id = 100;

-- GOOD: Only update when value actually changes
UPDATE dashboard_metrics SET status = 'warning'
WHERE id = 100 AND status != 'warning';
```

### 4. Schedule Periodic REINDEX During Low Traffic

For known high-update tables, schedule a weekly `REINDEX CONCURRENTLY` during off-peak hours as preventive maintenance.

---

## Key Decision Flowchart

```
Index bloat detected?
├── Only indexes bloated?
│   ├── Can tolerate write lock? → REINDEX INDEX
│   └── Must stay online? → REINDEX INDEX CONCURRENTLY
├── Both table and indexes bloated?
│   ├── Can tolerate full lock? → VACUUM FULL
│   └── Must stay online? → pg_repack
└── Just starting to bloat?
    └── Tune fillfactor + autovacuum (prevention)
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Index-only scan has high Heap Fetches | Visibility map not covering pages | VACUUM (updates VM), then check if index is still bloated |
| REINDEX CONCURRENTLY failed | Left INVALID index behind | `DROP INDEX <name>_ccnew`; re-run REINDEX |
| Index keeps re-bloating after REINDEX | Autovacuum too infrequent | Tune per-table autovacuum settings |
| avg_leaf_density shows 0 | Extension not installed or wrong name | `CREATE EXTENSION pgstattuple`; check index name spelling |
| REINDEX takes too long | Very large index | Consider REINDEX CONCURRENTLY in smaller batches or pg_repack |

Now run `lab/benchmark.sql` to see the performance difference REINDEX makes, and `lab/verify.sql` to validate your understanding.
