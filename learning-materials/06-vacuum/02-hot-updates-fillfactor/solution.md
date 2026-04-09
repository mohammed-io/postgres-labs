# Solution: HOT Updates & Fillfactor Tuning

## Complete Reference

### Baseline Checks

Before any optimization, establish your baseline:

```sql
-- 1. Current fillfactor
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'user_sessions';

-- Expected: reloptions is NULL → fillfactor=100 (default)

-- 2. Current table size and index count
SELECT
    pg_size_pretty(pg_relation_size('user_sessions')) AS table_size,
    pg_size_pretty(pg_indexes_size('user_sessions')) AS index_size,
    pg_size_pretty(pg_total_relation_size('user_sessions')) AS total_size;

-- 3. Reset statistics for clean measurement
SELECT pg_stat_reset();

-- 4. Run a representative workload: update only non-indexed column
UPDATE user_sessions SET last_active = NOW();

-- 5. Check HOT ratio with fillfactor=100
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Expected: hot_ratio_pct ≈ 0% (pages are full, no room for HOT)
```

### Applying Fillfactor

```sql
-- Step 1: Change fillfactor to 80
ALTER TABLE user_sessions SET (fillfactor = 80);

-- Step 2: Rebuild table to apply new fillfactor
-- This rewrites all pages with 20% free space per page
VACUUM FULL user_sessions;

-- Step 3: Re-analyze after rebuild
ANALYZE user_sessions;

-- Step 4: Verify fillfactor is set
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'user_sessions';
-- Expected: reloptions = {fillfactor=80}

-- Step 5: Verify table grew (expected: ~25% larger)
SELECT
    pg_size_pretty(pg_relation_size('user_sessions')) AS new_table_size;
```

### Verification After Optimization

```sql
-- Reset statistics
SELECT pg_stat_reset();

-- Same workload: update only non-indexed column
UPDATE user_sessions SET last_active = NOW();

-- Check HOT ratio with fillfactor=80
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    n_tup_upd - n_tup_hot_upd AS non_hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Expected: hot_ratio_pct ≈ 90-95%

-- Check dead tuples (should be minimal since HOT reuses space)
SELECT
    relname,
    n_dead_tup,
    n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Check page count
SELECT
    relpages AS page_count,
    reltuples AS row_estimate
FROM pg_class
WHERE relname = 'user_sessions';
```

### Demonstrating Indexed Column Breaks HOT

```sql
-- Reset stats
SELECT pg_stat_reset();

-- Update an INDEXED column (status has an index)
UPDATE user_sessions SET status = 'idle', last_active = NOW() WHERE id % 2 = 0;

-- Check: HOT ratio should be 0%
SELECT
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';

-- Expected: hot_ratio_pct = 0.0% — changing indexed column kills HOT
```

### Cleanup

```sql
-- Remove any test tables created during exploration
DROP TABLE IF EXISTS sessions_ff100;
DROP TABLE IF EXISTS sessions_ff80;
DROP TABLE IF EXISTS sessions_extreme;

-- Reset to fillfactor=100 if desired
-- ALTER TABLE user_sessions RESET (fillfactor);
-- VACUUM FULL user_sessions;

-- Or keep fillfactor=80 for ongoing experiments
SELECT pg_stat_reset();
```

### Troubleshooting

| Problem | Likely Cause | Solution |
|---------|-------------|----------|
| HOT ratio stays 0% after fillfactor change | Forgot `VACUUM FULL` | Run `VACUUM FULL user_sessions;` to rebuild pages |
| HOT ratio drops suddenly | New index on updated column | Check `pg_indexes` for new indexes on updated columns |
| Table too large after fillfactor change | fillfactor too low | Increase fillfactor (e.g., 80 → 90), rebuild |
| `VACUUM FULL` takes too long | Large table | Use `pg_repack` for online rebuild |
| HOT ratio is high but not 100% | Some rows span page boundaries | Normal — rows at page edges may not fit. Acceptable. |
| HOT works on small update but not large | Row grew too much for reserved space | Lower fillfactor or redesign to avoid row growth |
| `pg_stat_reset()` affects all tables | It's cluster-wide | Be aware in multi-table environments |
| fillfactor change has no effect | Only `ALTER TABLE` without rebuild | Must run `VACUUM FULL` or `pg_repack` after `ALTER TABLE` |
