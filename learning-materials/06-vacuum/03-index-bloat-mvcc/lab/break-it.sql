-- Break-It: Index Bloat from MVCC Lab
-- 3 executable failure scenarios demonstrating index bloat

-- =============================================
-- EXPERIMENT 1: Mass UPDATE → Index Size Doubles
-- =============================================
-- What breaks: All indexes roughly double in size after a single
-- UPDATE statement. Even VACUUM cannot shrink them.
-- Prerequisites: Fresh setup (docker compose up -d)

-- Step 1: Record initial index sizes
SELECT 'EXPERIMENT 1: Mass UPDATE → Index Size Doubles' AS experiment;

SELECT
    indexrelname AS index_name,
    pg_relation_size(indexrelid) AS size_bytes_before,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size_before
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Step 2: Mass UPDATE on all rows
-- Changes 'status' (indexed) and 'metric_value' (indexed)
-- Creates dead entries in ALL 5 indexes, not just the 2 changed columns
UPDATE dashboard_metrics
SET status = 'archived',
    metric_value = metric_value * 1.01,
    updated_at = NOW();

-- Step 3: VACUUM (cleans heap, NOT indexes)
VACUUM dashboard_metrics;

-- Step 4: Observe — indexes are now roughly 2x their original size
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size_after,
    (pgstatindex(indexrelname)).avg_leaf_density AS leaf_density,
    (pgstatindex(indexrelname)).leaf_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Expected: All indexes roughly doubled. avg_leaf_density ~50%.
-- The index on 'status' shows the most bloat because every row
-- moved from one of 5 values to 'archived' — massive page splits.

-- Step 5: See the impact on index-only scans
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*)
FROM dashboard_metrics
WHERE status = 'archived'
GROUP BY status;
-- Expected: High Heap Fetches. The visibility map can't cover
-- pages that still have dead tuple references from the old entries.

-- Recovery: Rebuild indexes
-- REINDEX INDEX CONCURRENTLY idx_dashboard_status;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_metric_name;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_source;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_recorded_at;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_value;


-- =============================================
-- EXPERIMENT 2: DELETE 90% → Index Still Same Size
-- =============================================
-- What breaks: Deleting 90% of rows barely reduces index size.
-- Dead entries are marked reusable but pages remain allocated.
-- Prerequisites: Fresh setup or after Experiment 1 recovery

SELECT 'EXPERIMENT 2: DELETE 90% → Index Still Same Size' AS experiment;

-- Step 1: Record sizes before DELETE
SELECT
    indexrelname AS index_name,
    pg_relation_size(indexrelid) AS size_bytes_before,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size_before,
    (pgstatindex(indexrelname)).leaf_pages AS leaf_pages_before
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT count(*) AS rows_before FROM dashboard_metrics;

-- Step 2: Delete 90% of rows (keep only 10%)
DELETE FROM dashboard_metrics WHERE id % 10 != 0;

-- Step 3: VACUUM (marks space reusable, does NOT compact)
VACUUM dashboard_metrics;

-- Step 4: Observe — index barely shrunk despite 90% row removal
SELECT
    indexrelname AS index_name,
    pg_relation_size(indexrelid) AS size_bytes_after,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size_after,
    (pgstatindex(indexrelname)).avg_leaf_density AS leaf_density,
    (pgstatindex(indexrelname)).leaf_pages AS leaf_pages_after,
    (pgstatindex(indexrelname)).empty_pages,
    (pgstatindex(indexrelname)).deleted_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT count(*) AS rows_after FROM dashboard_metrics;

-- Expected: Index size barely changed. leaf_pages similar.
-- empty_pages and deleted_pages may be high.
-- avg_leaf_density is very low (lots of dead entries still in pages).
-- The index is now ~10x larger than it needs to be for 50K rows.

-- Step 5: Query performance on the shrunken table
EXPLAIN (ANALYZE, BUFFERS)
SELECT status, count(*)
FROM dashboard_metrics
GROUP BY status;
-- Expected: Still reads many index pages even though 90% of
-- entries are dead. The B-tree structure hasn't changed.

-- Recovery: Rebuild
-- REINDEX TABLE CONCURRENTLY dashboard_metrics;
-- Or individually:
-- REINDEX INDEX CONCURRENTLY idx_dashboard_status;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_metric_name;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_source;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_recorded_at;
-- REINDEX INDEX CONCURRENTLY idx_dashboard_value;


-- =============================================
-- EXPERIMENT 3: Repeated Small Updates → Gradual Bloat Accumulation
-- =============================================
-- What breaks: Over time, small batch updates accumulate bloat.
-- Each batch adds dead entries and causes page splits.
-- Autovacuum is OFF in this lab, simulating misconfigured production.
-- Prerequisites: Fresh setup (restart: docker compose down && docker compose up -d)

SELECT 'EXPERIMENT 3: Repeated Small Updates → Gradual Bloat' AS experiment;

-- Step 1: Record initial state
SELECT
    indexrelname AS index_name,
    pg_relation_size(indexrelid) AS size_bytes_initial,
    (pgstatindex(indexrelname)).avg_leaf_density AS initial_density
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Step 2: Simulate a week of batch updates (10 rounds)
-- Each round updates ~10% of rows with random status changes

-- Round 1
UPDATE dashboard_metrics SET status = 'warning', updated_at = NOW()
WHERE id % 10 = 0;
VACUUM dashboard_metrics;

-- Round 2
UPDATE dashboard_metrics SET status = 'critical', updated_at = NOW()
WHERE id % 10 = 1;
VACUUM dashboard_metrics;

-- Round 3
UPDATE dashboard_metrics SET status = 'active', updated_at = NOW()
WHERE id % 10 = 2;
VACUUM dashboard_metrics;

-- Round 4
UPDATE dashboard_metrics SET metric_value = metric_value + random(), updated_at = NOW()
WHERE id % 10 = 3;
VACUUM dashboard_metrics;

-- Round 5
UPDATE dashboard_metrics SET status = 'warning', updated_at = NOW()
WHERE id % 10 = 4;
VACUUM dashboard_metrics;

-- Round 6
UPDATE dashboard_metrics SET metric_value = metric_value * 0.99, updated_at = NOW()
WHERE id % 10 = 5;
VACUUM dashboard_metrics;

-- Round 7
UPDATE dashboard_metrics SET status = 'archived', updated_at = NOW()
WHERE id % 10 = 6;
VACUUM dashboard_metrics;

-- Round 8
UPDATE dashboard_metrics SET tags = tags || '{"batch":"8"}', updated_at = NOW()
WHERE id % 10 = 7;
VACUUM dashboard_metrics;

-- Round 9
UPDATE dashboard_metrics SET status = 'active', updated_at = NOW()
WHERE id % 10 = 8;
VACUUM dashboard_metrics;

-- Round 10
UPDATE dashboard_metrics SET metric_value = metric_value + 1, updated_at = NOW()
WHERE id % 10 = 9;
VACUUM dashboard_metrics;

-- Step 3: Observe gradual bloat accumulation
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS current_size,
    round((pgstatindex(indexrelname)).avg_leaf_density, 1) AS current_density,
    (pgstatindex(indexrelname)).leaf_pages AS current_leaf_pages,
    (pgstatindex(indexrelname)).empty_pages,
    (pgstatindex(indexrelname)).deleted_pages
FROM pg_stat_user_indexes
WHERE relname = 'dashboard_metrics'
ORDER BY (pgstatindex(indexrelname)).avg_leaf_density;

-- Expected: Each round added dead entries and caused page splits.
-- idx_dashboard_status shows the most bloat (updated in rounds 1,2,3,5,7,9).
-- idx_dashboard_value shows moderate bloat (updated in rounds 4,6,10).
-- idx_dashboard_metric_name shows least bloat (never directly updated,
-- but still grew because new heap tuples = new index entries even for
-- unchanged columns — unless HOT applies).

-- Step 4: Compare query performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT source, status, count(*), avg(metric_value)
FROM dashboard_metrics
WHERE source = 'prod-api-01'
    AND recorded_at > NOW() - INTERVAL '90 days'
GROUP BY source, status;
-- Expected: More buffer reads than the initial state.
-- The index is physically larger so scans traverse more pages.

-- Key insight from Experiment 3:
-- Even with regular VACUUM after each batch, indexes accumulate bloat.
-- The gradual pattern is the most realistic production scenario.
-- This is why scheduled REINDEX (e.g., weekly during low traffic)
-- is essential for UPDATE-heavy tables.

-- Recovery: Rebuild all indexes
-- REINDEX TABLE CONCURRENTLY dashboard_metrics;
