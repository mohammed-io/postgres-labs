# Solution: B-Tree, GIN & INCLUDE Indexes

## Complete Answers

### Task 1: B-Tree Indexes

**When index is used**:
```sql
-- Uses index: Equality on indexed column
EXPLAIN ANALYZE
SELECT * FROM products WHERE sku = 'SKU-50000';

-- Uses index: Range query
EXPLAIN ANALYZE
SELECT * FROM products WHERE price BETWEEN 100 AND 200;

-- Does NOT use index efficiently: Function on column
EXPLAIN ANALYZE
SELECT * FROM products WHERE LOWER(sku) = 'sku-50000';
-- Fix: Index on expression or use COLLATE

-- Multi-column index usage
CREATE INDEX idx_products_category_price ON products(category, price);

-- Uses index: Leading column specified
WHERE category = 'Electronics'

-- Uses index partially: Leading column with inequality
WHERE category = 'Electronics' AND price > 100

-- Does NOT use index: Leading column missing
WHERE price > 100
```

### Task 2: INCLUDE for Index-Only Scans

**Creating covering index**:
```sql
-- Dashboard query optimization
-- Original: Slow (heap fetches)
SELECT customer_id, order_date, status
FROM orders
WHERE created_at > NOW() - INTERVAL '7 days';

-- Solution: INCLUDE
CREATE INDEX idx_orders_dashboard
ON orders(created_at DESC)
INCLUDE (customer_id, status);

-- Run VACUUM to update visibility map
VACUUM ANALYZE orders;

-- Now: Index-Only Scan, no heap access
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, order_date, status
FROM orders
WHERE created_at > NOW() - INTERVAL '7 days';
```

**Benefits**:
- Eliminates heap fetches
- Reduces I/O
- Faster queries for dashboards/reports

**Trade-off**: Larger index size

### Task 3: GIN for JSONB

**JSONB query optimization**:
```sql
-- Slow without GIN
SELECT * FROM events WHERE properties @> '{"page": "/page/500"}';

-- Create GIN
CREATE INDEX idx_events_properties ON events USING GIN (properties);

-- Now fast
EXPLAIN ANALYZE
SELECT * FROM events WHERE properties @> '{"page": "/page/500"}';

-- Check index size (expect 2-3x table size)
SELECT pg_size_pretty(pg_relation_size('idx_events_properties'));
```

**GIN operators**:
| Operator | Meaning | Example |
|----------|---------|---------|
| `@>` | Contains | `col @> '{"a": 1}'` |
| `?` | Key exists | `col ? 'key'` |
| `?&` | All keys exist | `col ?& array['a','b']` |
| `?|` | Any key exists | `col ?| array['a','b']` |

---

## Index Strategy Cheatsheet

| Query Pattern | Index Type |
|---------------|------------|
| `WHERE col = value` | B-Tree |
| `WHERE col > value` | B-Tree |
| `WHERE col IN (1,2,3)` | B-Tree |
| `WHERE col @> '{1}'` | GIN |
| `WHERE col::jsonb ? 'key'` | GIN |
| `WHERE text_col LIKE 'prefix%'` | B-Tree (with opclass) |
| `ORDER BY col LIMIT n` | B-Tree |
| `SELECT cols FROM table WHERE col` | B-Tree with INCLUDE |

---

## Key Takeaways

1. **B-Tree**: Default, use for most queries
2. **GIN**: Essential for JSONB/array containment
3. **INCLUDE**: Eliminates heap fetches for covering queries
4. **Partial indexes**: Smaller, faster for specific queries
5. **Index bloat**: REINDEX CONCURRENTLY to fix without locks
