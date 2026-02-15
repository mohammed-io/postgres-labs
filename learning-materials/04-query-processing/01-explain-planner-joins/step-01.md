# Step 1: Reading EXPLAIN Output

## EXPLAIN Options

```sql
-- Basic plan (no execution)
EXPLAIN SELECT * FROM products WHERE price > 100;

-- With actual execution times
EXPLAIN ANALYZE SELECT * FROM products WHERE price > 100;

-- With buffer usage (I/O)
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE price > 100;

-- With verbose details
EXPLAIN (ANALYZE, VERBOSE, BUFFERS) SELECT * FROM products WHERE price > 100;
```

## Understanding Plan Nodes

| Node Type | Meaning |
|-----------|---------|
| Seq Scan | Read entire table |
| Index Scan | Read via index, then fetch rows |
| Index Only Scan | Index has all data (no heap fetch) |
| Bitmap Scan | Use bitmap from index, then fetch rows |
| Nested Loop | For each row in A, find matching in B |
| Hash Join | Build hash table of A, probe with B |
| Merge Join | Both inputs sorted, merge together |

## Cost vs Actual Time

```
Cost = 0.00..1234.56 (startup cost..total cost)
Actual time = 0.123..45.678 ms (actual execution time)
```

**Cost**: Planner's estimate (used for optimization)
**Actual time**: Real execution time (from ANALYZE)

## Mini-Test

```sql
EXPLAIN ANALYZE
SELECT p.name, o.order_date
FROM products p
JOIN orders o ON p.id = o.product_id
WHERE p.category = 'Electronics';
```

What join algorithm was used? Why?
