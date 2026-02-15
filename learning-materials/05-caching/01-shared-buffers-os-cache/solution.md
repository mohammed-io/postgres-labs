# Solution: Shared Buffers & OS Cache

## Complete Answers

### Two-Level Caching

**Question**: Which was faster - first or second run?

**Answer**: Second run is faster because:
1. Data pages already in `shared_buffers` or OS cache
2. No disk I/O needed
3. PostgreSQL can fetch from memory

### Cache Hit Ratio Targets

| Workload | Target Hit Ratio |
|----------|-----------------|
| OLTP (transactional) | >99% |
| OLAP (analytics) | >95% |
| Mixed | >98% |

### Setting effective_cache_size

```sql
-- For dedicated DB server with 16GB RAM:
ALTER SYSTEM SET effective_cache_size = '12GB';

-- For shared server (web + DB on same machine, 16GB RAM):
ALTER SYSTEM SET effective_cache_size = '4GB';  -- Leave room for web app

-- Reload config
SELECT pg_reload_conf();
```

### Recommended Settings

| RAM | shared_buffers | effective_cache_size |
|-----|----------------|----------------------|
| 4GB | 1GB | 3GB |
| 8GB | 2GB | 6GB |
| 16GB | 4GB | 12GB |
| 32GB | 8GB | 24GB |
| 64GB+ | 16GB | 48GB+ |

**Note**: `shared_buffers` beyond 8GB on Linux has diminishing returns due to OS cache.

### Double Caching Consideration

```
Data flow: Disk → OS cache → shared_buffers → query
                      ↑            ↑
                      |____________|
                       Both cache same data!
```

This isn't necessarily wasteful - OS cache is more flexible, shared_buffers gives Postgres control.
