-- Break-it: Index Issues

\echo '=== Break-it 1: Create Unused Indexes ==='

-- These indexes won't be used!
CREATE INDEX idx_products_id ON products(id);  -- Primary key exists
CREATE INDEX idx_products_id_sku ON products(id, sku);  -- Redundant with just sku

-- Check unused indexes
SELECT
    indexrelname,
    idx_scan,
    CASE WHEN idx_scan = 0 THEN 'UNUSED!' END AS status
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan;

\echo ''
\echo '=== Break-it 2: Index Bloat ==='

-- Create bloat through updates
CREATE TABLE bloat_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO bloat_test (data)
SELECT repeat('x', 1000) FROM generate_series(1, 10000);

-- Create index
CREATE INDEX idx_bloat_test_updated ON bloat_test(updated_at);

-- Update many times (causes index bloat)
UPDATE bloat_test SET updated_at = NOW(), data = data || 'y';

-- Check bloat
SELECT
    pg_size_pretty(pg_relation_size('idx_bloat_test_updated')) AS index_size,
    pg_stat_get_dead_tuples('idx_bloat_test_updated'::regclass) AS dead_tuples;

\echo ''
\echo '=== Break-it 3: Too Many Indexes Slow Down Writes ==='

-- Create table with many indexes
CREATE TABLE many_indexes (
    id SERIAL PRIMARY KEY,
    col1 TEXT,
    col2 TEXT,
    col3 TEXT,
    col4 TEXT
);

CREATE INDEX idx_many_1 ON many_indexes(col1);
CREATE INDEX idx_many_2 ON many_indexes(col2);
CREATE INDEX idx_many_3 ON many_indexes(col3);
CREATE INDEX idx_many_4 ON many_indexes(col4);
CREATE INDEX idx_many_12 ON many_indexes(col1, col2);
CREATE INDEX idx_many_34 ON many_indexes(col3, col4);
CREATE INDEX idx_many_123 ON many_indexes(col1, col2, col3);

\echo 'Inserting with 7 indexes...'
\timing on
INSERT INTO many_indexes (col1, col2, col3, col4)
SELECT
    md5(random()::text),
    md5(random()::text),
    md5(random()::text),
    md5(random()::text)
FROM generate_series(1, 10000);
\timing off

\echo 'Each INSERT must update 7 indexes!'

\echo ''
\echo '=== Cleanup ==='
DROP TABLE IF EXISTS bloat_test;
DROP TABLE IF EXISTS many_indexes;
DROP INDEX IF EXISTS idx_products_id, idx_products_id_sku;
