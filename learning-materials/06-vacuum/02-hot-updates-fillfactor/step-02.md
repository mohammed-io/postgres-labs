# Step 2: Fillfactor Tuning

## What is Fillfactor?

`fillfactor` controls how much of each 8KB page is available for data. The rest is reserved as free space for future HOT updates.

```
fillfactor = 100 (default):
┌───────────────────────────────────────────────┐
│ Data Data Data Data Data Data Data Data Data  │ ← 100% full
│                                               │ ← 0% free
└───────────────────────────────────────────────┘
No room for HOT updates → new tuple goes to different page


fillfactor = 80:
┌───────────────────────────────────────────────┐
│ Data Data Data Data Data Data Data            │ ← 80% data
│                                               │
│          [Free space for HOT updates]         │ ← 20% reserved
└───────────────────────────────────────────────┘
New tuple fits on same page → HOT update possible!


fillfactor = 50:
┌───────────────────────────────────────────────┐
│ Data Data Data Data                           │ ← 50% data
│                                               │
│                                               │
│          [Way too much free space]            │ ← 50% wasted
└───────────────────────────────────────────────┘
HOT works great, but you're wasting 50% of disk and RAM
```

---

## The Trade-off

| fillfactor | Space Used | HOT Eligibility | Best For |
|-----------|------------|-----------------|----------|
| 100 (default) | 100% | Almost never | Insert-only, read-mostly |
| 95 | 105% | Seldom | Very light updates |
| 90 | 111% | Moderate | Moderate update workloads |
| 85 | 118% | Good | Typical OLTP |
| 80 | 125% | High | Heavy update workloads |
| 70 | 143% | Very High | Extreme update workloads |
| 50 | 200% | Near 100% | Almost never appropriate |

**"Space Used"** is relative: a table that's 10GB at fillfactor=100 becomes ~12.5GB at fillfactor=80.

### How to Choose

1. **Measure your current HOT ratio** (from step-01)
2. **Estimate row growth** on UPDATE — if the updated row is larger, you need more free space
3. **Count your indexes** — more indexes = more benefit from HOT
4. **Start at 90** — conservative default for OLTP
5. **Go to 80 only if** updates are the dominant operation AND you have disk headroom
6. **Never go below 70** unless you have a very specific reason

---

## Setting Fillfactor

### On a New Table

```sql
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    last_active TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT
) WITH (fillfactor = 80);
```

### On an Existing Table

```sql
-- Change the setting
ALTER TABLE user_sessions SET (fillfactor = 80);

-- MUST rebuild the table for it to take effect!
-- VACUUM FULL rewrites all pages with the new fillfactor
VACUUM FULL user_sessions;

-- Alternatively, use pg_repack for zero-downtime rebuild
-- pg_repack --table user_sessions -d labdb
```

**Critical:** `ALTER TABLE ... SET (fillfactor)` only changes the setting. Existing pages remain packed at 100%. You **must** rebuild the table with `VACUUM FULL` or `pg_repack` to repack pages with free space.

---

## Measuring the Impact

### Before and After Comparison

```sql
-- Step 1: Reset statistics
SELECT pg_stat_reset();

-- Step 2: Run your typical workload
UPDATE user_sessions SET last_active = NOW() WHERE id % 10 = 0;

-- Step 3: Check HOT ratio
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_ratio_pct,
    pg_size_pretty(pg_relation_size(relid)) AS table_size
FROM pg_stat_user_tables
WHERE relname = 'user_sessions';
```

### Expected Results

| fillfactor | HOT Ratio | Table Size (100K rows) | Index Writes Saved |
|-----------|-----------|----------------------|-------------------|
| 100 | ~0% | ~12 MB | 0% |
| 90 | ~60-70% | ~13 MB | ~65% |
| 80 | ~90-95% | ~15 MB | ~92% |
| 70 | ~98%+ | ~17 MB | ~98% |

*Actual numbers depend on row size and update pattern.*

---

## Checking Current Fillfactor

```sql
SELECT
    relname,
    reloptions
FROM pg_class
WHERE relname = 'user_sessions';

-- Or more explicitly:
SELECT
    c.relname,
    array_to_string(c.reloptions, ', ') AS options,
    CASE
        WHEN c.reloptions @> ARRAY['fillfactor=80'] THEN 'fillfactor=80'
        WHEN c.reloptions @> ARRAY['fillfactor=90'] THEN 'fillfactor=90'
        WHEN c.reloptions IS NULL OR NOT EXISTS (
            SELECT 1 FROM unnest(c.reloptions) o WHERE o LIKE 'fillfactor=%'
        ) THEN 'fillfactor=100 (default)'
        ELSE 'custom fillfactor'
    END AS fillfactor_setting
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
    AND c.relkind = 'r';
```

---

## When Fillfactor Won't Help

Fillfactor only helps when updates are **HOT-eligible**. It cannot fix:

| Situation | Why Fillfactor Doesn't Help |
|-----------|---------------------------|
| Updating an indexed column | HOT requires NO indexed column changes |
| Row grows significantly on update | Reserved space may not be enough |
| Insert-only workload | No updates = no HOT needed |
| Small table (fits in cache) | I/O cost is minimal anyway |

### Anti-Pattern: Indexing Everything

```sql
-- BAD: Every column has an index
CREATE INDEX idx_sessions_uid ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(session_token);
CREATE INDEX idx_sessions_status ON user_sessions(status);
CREATE INDEX idx_sessions_last_active ON user_sessions(last_active);
CREATE INDEX idx_sessions_ip ON user_sessions(ip_address);

-- Now ANY column update = no HOT, regardless of fillfactor
```

**Best practice:** Only index columns used in WHERE clauses. If an index exists only for occasional reporting, consider dropping it or using a partial index.

---

## Mini-Experiment

```sql
-- Compare fillfactor 100 vs 80 side by side

-- Create two identical tables
CREATE TABLE sessions_ff100 (LIKE user_sessions INCLUDING ALL);
CREATE TABLE sessions_ff80 (LIKE user_sessions INCLUDING ALL);
ALTER TABLE sessions_ff80 SET (fillfactor = 80);

-- Populate both
INSERT INTO sessions_ff100 SELECT * FROM user_sessions;
INSERT INTO sessions_ff80 SELECT * FROM user_sessions;

-- Rebuild ff80 table to apply fillfactor
VACUUM FULL sessions_ff80;

-- Reset stats
SELECT pg_stat_reset();

-- Run identical updates
UPDATE sessions_ff100 SET last_active = NOW() WHERE id % 5 = 0;
UPDATE sessions_ff80 SET last_active = NOW() WHERE id % 5 = 0;

-- Compare HOT ratios
SELECT
    relname,
    n_tup_upd AS total_updates,
    n_tup_hot_upd AS hot_updates,
    CASE WHEN n_tup_upd > 0
        THEN round(100.0 * n_tup_hot_upd / n_tup_upd, 1)
        ELSE 0
    END AS hot_pct,
    pg_size_pretty(pg_relation_size(relid)) AS size
FROM pg_stat_user_tables
WHERE relname IN ('sessions_ff100', 'sessions_ff80')
ORDER BY relname;

-- Cleanup
DROP TABLE sessions_ff100;
DROP TABLE sessions_ff80;
```

---

## Real-World Guidance

### Decision Tree

```
Is the table UPDATE-heavy?
├── No → Keep fillfactor=100 (default)
└── Yes
    ├── Are updated columns indexed?
    │   ├── Yes → Fillfactor won't help. Remove unnecessary indexes first.
    │   └── No
    │       ├── How many indexes on the table?
    │       │   ├── 1-2 → fillfactor=90 is likely enough
    │       │   └── 3+ → fillfactor=80 gives significant savings
    │       └── How update-heavy?
    │           ├── Moderate (10% of rows/hour) → fillfactor=90
    │           ├── Heavy (50%+ of rows/hour) → fillfactor=80
    │           └── Extreme (>100% of rows/hour) → fillfactor=70-75
```

### Production Checklist

- [ ] Measure current HOT ratio before changing anything
- [ ] Identify which columns are updated most frequently
- [ ] Verify updated columns are NOT indexed
- [ ] Calculate space overhead (table will grow by `100/fillfactor - 1`%)
- [ ] Schedule `VACUUM FULL` or `pg_repack` during maintenance window
- [ ] Measure HOT ratio after change
- [ ] Monitor table size and query performance for 1 week

---

## Key Takeaways

1. **fillfactor reserves free space on each page** for future HOT updates
2. **Default fillfactor=100 means zero free space** → HOT almost never works
3. **You must rebuild the table** after changing fillfactor (VACUUM FULL / pg_repack)
4. **fillfactor=80 is the sweet spot** for most UPDATE-heavy OLTP tables
5. **Fillfactor cannot fix indexed column updates** — HOT requires no indexed columns changed
6. **Measure before and after** — don't guess, check `n_tup_hot_upd / n_tup_upd`
