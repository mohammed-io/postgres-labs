-- Benchmark: Index Performance

\echo '=== Benchmark: B-Tree vs GIN vs No Index ==='
\timing on

-- Test 1: No index (sequential scan)
DROP TABLE IF EXISTS benchmark_products;
CREATE TABLE benchmark_products (
    id SERIAL,
    sku TEXT,
    attributes JSONB
);

INSERT INTO benchmark_products (sku, attributes)
SELECT
    'SKU-' || i,
    jsonb_build_object('color', (ARRAY ['red', 'blue', 'green'])[floor(random() * 3 + 1)])
FROM generate_series(1, 100000) AS s(i);

ANALYZE benchmark_products;

\echo 'Query 1: B-Tree lookup (no index yet)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM benchmark_products WHERE sku = 'SKU-50000';

-- Create B-Tree index
CREATE INDEX idx_bench_sku ON benchmark_products(sku);
ANALYZE benchmark_products;

\echo 'Query 2: B-Tree lookup (with index)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM benchmark_products WHERE sku = 'SKU-50000';

-- Test GIN for JSONB
\echo 'Query 3: JSONB lookup (no index)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM benchmark_products WHERE attributes @> '{"color": "red"}';

-- Create GIN index
CREATE INDEX idx_bench_attributes ON benchmark_products USING GIN (attributes);
ANALYZE benchmark_products;

\echo 'Query 4: JSONB lookup (with GIN index)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM benchmark_products WHERE attributes @> '{"color": "red"}';

\timing off

\echo ''
\echo '=== Index Size Comparison ==='
SELECT
    indexrelname::regclass AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'benchmark_products';
