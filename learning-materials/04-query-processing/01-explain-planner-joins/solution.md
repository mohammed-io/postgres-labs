# Solution: Query Processing

## Key Takeaways

### Join Algorithms

| Algorithm | When Used | Characteristics |
|-----------|-----------|-----------------|
| **Nested Loop** | Small table × large table with index | O(N×M), good for few rows |
| **Hash Join** | Large tables, equality join | Builds hash table, O(N+M) |
| **Merge Join** | Large sorted inputs | Requires sort or index, O(N+M) |

### Reading Plans

```sql
-- Look for:
- Actual time vs Cost (mismatch = bad statistics)
- Rows (estimated vs actual)
- Buffers (shared hit = cache, read = disk)
- Heap Fetches (high = consider INCLUDE)
```

### Fixing Bad Plans

1. **Update statistics**: `ANALYZE table;`
2. **Increase statistics target**: `ALTER TABLE ... ALTER COLUMN SET STATISTICS 1000;`
3. **Use CTEs** to materialize intermediate results
4. **Join order hints**: Not available in Postgres! (unlike Oracle)
5. **JIT compilation**: Can speed up complex expressions
