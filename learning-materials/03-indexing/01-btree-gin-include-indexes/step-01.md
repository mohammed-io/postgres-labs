# Step 1: B-Tree Index Internals

## Understanding B-Tree

B-Tree is PostgreSQL's default index type. It's a **balanced tree** structure.

### Key Properties

| Property | Value | Meaning |
|----------|-------|---------|
| Height | ~3-4 levels | 3-4 disk reads to find any row |
| Structure | Balanced | All leaf nodes at same level |
| Order | Sorted | Enables range queries |
| Operations | O(log n) | Fast lookups regardless of size |

### When B-Tree is Used

- `=`, `<>`, `<`, `>`, `<=`, `>=` comparisons
- `BETWEEN`, `IN`, `IS NULL`
- `ORDER BY`, `DISTINCT` on indexed column
- Pattern matching: `LIKE 'prefix%'` (not `'%suffix'`)

---

## Investigation

### Setup

```sql
docker exec -it postgres-index psql -U postgres

-- Create test table
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    sku TEXT,
    name TEXT,
    price DECIMAL(10,2),
    category TEXT,
    in_stock BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert 100K products
INSERT INTO products (sku, name, price, category, in_stock)
SELECT
    'SKU-' || i,
    'Product ' || i,
    (random() * 1000)::decimal(10,2),
    (ARRAY ['Electronics', 'Clothing', 'Home', 'Toys'])[floor(random() * 4 + 1)],
    random() > 0.3
FROM generate_series(1, 100000) AS s(i);

ANALYZE products;
```

### 1. Sequential Scan vs Index Scan

```sql
-- Without index: Sequential scan
EXPLAIN ANALYZE
SELECT * FROM products WHERE sku = 'SKU-50000';

-- Create index
CREATE INDEX idx_products_sku ON products(sku);

ANALYZE products;

-- With index: Index scan
EXPLAIN ANALYZE
SELECT * FROM products WHERE sku = 'SKU-50000';
```

**Compare**: Look for "Seq Scan" vs "Index Scan" and execution time.

### 2. When Postgres Chooses Seq Scan Anyway

```sql
-- Small table or many rows = seq scan might be faster
EXPLAIN ANALYZE
SELECT * FROM products WHERE price < 10;
```

**Real Output Example**:
```
Seq Scan on products  (cost=0.00..22350.00 rows=50000 width=120)
               (actual time=0.123..245.678 rows=49523 loops=1)
  Filter: (price < 10)
  Rows Removed by Filter: 50477
Planning Time: 0.123 ms
Execution Time: 246.234 ms
```

**Why Seq Scan?** Random I/O for index (50K lookups) + heap fetch > sequential table scan.

**Rule of thumb**: If query returns >5-10% of rows, seq scan is often faster.

### 3. Index-Only Scan vs Index Scan

```sql
-- This requires heap access (index scan)
EXPLAIN ANALYZE
SELECT id, sku FROM products WHERE sku = 'SKU-50000';

-- Why? Need to fetch the row to verify visibility (MVCC)

-- With INCLUDE (next step), we can avoid heap access!
```

### 4. Multi-Column Index Order

```sql
-- Index on (category, price)
CREATE INDEX idx_products_category_price ON products(category, price);

-- Uses index: category specified
EXPLAIN ANALYZE
SELECT * FROM products WHERE category = 'Electronics';

-- Uses index: both specified
EXPLAIN ANALYZE
SELECT * FROM products WHERE category = 'Electronics' AND price > 100;

-- Does NOT use index efficiently: only price specified
EXPLAIN ANALYZE
SELECT * FROM products WHERE price > 100;
```

**Key Rule**: For multi-column index, leading column must be in WHERE clause.

### 5. Index on Expression

```sql
-- Index on computed expression
CREATE INDEX idx_products_sku_lower ON products(LOWER(sku));

-- Now this uses the index
EXPLAIN ANALYZE
SELECT * FROM products WHERE LOWER(sku) = 'sku-50000';
```

---

## Mini-Challenge

**Predict then verify**: Which queries use the index `idx_products_category_price`?

Run `EXPLAIN ANALYZE` on each query and check for "Index Scan" vs "Seq Scan".

```sql
-- Index: (category, price)

-- Query A
EXPLAIN ANALYZE
SELECT * FROM products WHERE category = 'Electronics' ORDER BY price;

-- Query B
EXPLAIN ANALYZE
SELECT * FROM products WHERE price > 500;

-- Query C
EXPLAIN ANALYZE
SELECT * FROM products WHERE category = 'Clothing' AND price BETWEEN 10 AND 100;

-- Query D
EXPLAIN ANALYZE
SELECT * FROM products WHERE category IN ('Electronics', 'Toys');
```

Check `solution.md` for the answers and explanation.
