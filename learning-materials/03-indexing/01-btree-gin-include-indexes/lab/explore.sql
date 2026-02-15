-- Explore Indexing

\echo '=== Explore 1: Index Size Comparison ==='
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size,
    idx_scan AS scans,
    CASE WHEN idx_scan = 0 THEN 'UNUSED!' END AS warning
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;

\echo ''
\echo '=== Explore 2: Duplicate or Redundant Indexes ==='
WITH index_columns AS (
    SELECT
        indexrelid,
        indrelid,
        array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum)) AS columns
    FROM pg_index ix
    JOIN pg_attribute a ON a.attrelid = ix.indrelid AND a.attnum = ANY(ix.indkey)
    JOIN pg_class c ON c.oid = ix.indexrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
    GROUP BY indexrelid, indrelid
)
SELECT
    i1.indexrelname::regclass AS index1,
    i2.indexrelname::regclass AS index2,
    i1.columns AS cols1,
    i2.columns AS cols2,
    CASE
        WHEN i1.columns = i2.columns THEN 'DUPLICATE!'
        WHEN i1.columns <@ i2.columns THEN 'REDUNDANT (covered by index2)'
        WHEN i2.columns <@ i1.columns THEN 'REDUNDANT (covered by index1)'
    END AS status
FROM index_columns i1
JOIN index_columns i2 ON i1.indrelid = i2.indrelid AND i1.indexrelid < i2.indexrelid
WHERE i1.columns <@ i2.columns OR i2.columns <@ i1.columns OR i1.columns = i2.columns;

\echo ''
\echo '=== Explore 3: Index Bloat Detection ==='
SELECT
    schemaname,
    tablename,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    CASE
        WHEN idx_scan > 0 AND idx_tup_fetch > 0 THEN
            round(100.0 * idx_tup_fetch / idx_tup_read, 2)
        ELSE 0
    END AS fetch_ratio_pct
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

\echo ''
\echo '=== Explore 4: Missing Indexes (high seq scan tables) ==='
SELECT
    schemaname,
    relname AS table_name,
    seq_scan AS seq_scans,
    seq_tup_read AS tuples_read,
    n_live_tup AS live_tuples,
    round(100.0 * seq_tup_read / NULLIF(n_live_tup, 0), 2) AS read_ratio_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND seq_scan > 100
    AND seq_tup_read > 10000
ORDER BY seq_tup_read DESC;

\echo ''
\echo '=== Explore 5: JSONB Index Operators ==='
\echo 'GIN index operators for JSONB:'
\echo '  @>  : Contains (JSONB)'
\echo '  <@  : Contained by'
\echo '  ?   : Key exists'
\echo '  ?|  : Any key exists'
\echo '  ?&  : All keys exist'
\echo '  @@  : tsvector match'

-- Test JSONB operators
SELECT
    properties->>'page' AS page_value,
    properties ? 'referrer' AS has_referrer_key,
    properties @> '{"referrer": "google"}' AS contains_google_referrer
FROM events
LIMIT 5;
