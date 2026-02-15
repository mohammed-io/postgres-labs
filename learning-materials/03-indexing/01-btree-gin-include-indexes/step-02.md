# Step 2: INCLUDE for Index-Only Scans

## The Problem: Heap Fetches

Even with an index, Postgres often fetches the full row from the heap (main table).

**Why?** MVCC requires checking visibility (is this tuple visible to my transaction?)

**Solution**: INCLUDE stores extra columns in the index, avoiding heap access.

### Index-Only Scan Conditions

1. All columns needed must be in the index
2. Visibility map must show all pages as "all visible"
3. Index must contain the columns you're selecting

---

## Investigation

### 1. Without INCLUDE (Index Scan)

```sql
docker exec -it postgres-index psql -U postgres

-- Regular index
CREATE INDEX idx_products_price ON products(price);

ANALYZE products;

-- Query: Only selects price (indexed column)
EXPLAIN (ANALYZE, BUFFERS)
SELECT price FROM products WHERE price > 500;

-- Look for: "Index Scan using idx_products_price"
-- Despite only needing indexed column, may still access heap!
```

**Why?** Visibility map may not be updated yet.

### 2. With INCLUDE (Index-Only Scan)

```sql
-- Drop old index
DROP INDEX idx_products_price;

-- Create index with INCLUDE
CREATE INDEX idx_products_price_inc ON products(price) INCLUDE (id, sku);

-- Make visibility map accurate
VACUUM ANALYZE products;

-- Now try again
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, sku, price FROM products WHERE price > 500;

-- Look for: "Index Only Scan"
-- No heap access! All data from index.
```

### 3. Real-World Dashboard Query

```sql
-- Dashboard: Show orders by date with status
-- Without INCLUDE: Slow due to heap fetches
EXPLAIN ANALYZE
SELECT id, created_at, status
FROM orders
WHERE created_at > NOW() - INTERVAL '7 days';

-- With INCLUDE: Fast!
CREATE INDEX idx_orders_created_inc
ON orders(created_at)
INCLUDE (id, status);

VACUUM ANALYZE orders;

EXPLAIN ANALYZE
SELECT id, created_at, status
FROM orders
WHERE created_at > NOW() - INTERVAL '7 days';

-- Should see: "Index Only Scan"
```

### 4. When INCLUDE Doesn't Help

```sql
-- Need column NOT in index
EXPLAIN ANALYZE
SELECT id, sku, name, price FROM products WHERE price > 500;

-- Falls back to Index Scan (name not in index)
```

### 5: Index Size Comparison

```sql
-- Compare sizes
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND relname = 'products';

-- INCLUDE indexes are larger (store more columns)
-- But can be much faster for specific queries
```

---

## INCLUDE vs Regular Index Column

| Aspect | Regular Column | INCLUDE |
|--------|----------------|---------|
| Used for search/filter | Yes | No |
| Used for sort | Yes | No |
| Stored for retrieval | Yes | Yes |
| Affects index size | Yes | Yes |
| Can be unique | Yes | No |

**Rule**: Put search columns in regular part, retrieval columns in INCLUDE.

---

## Mini-Challenge

You have a query:

```sql
SELECT customer_id, order_date, total_amount
FROM orders
WHERE customer_id = 123
ORDER BY order_date DESC
LIMIT 10;
```

**Create optimal index with INCLUDE**:

<hr>

**Answer**:


```sql
CREATE INDEX idx_orders_customer_date
ON orders(customer_id, order_date DESC)
INCLUDE (total_amount);
```

Explanation:
- `customer_id`: For WHERE filter
- `order_date`: For ORDER BY (and index ordering)
- `total_amount`: Included for retrieval (no heap fetch)
