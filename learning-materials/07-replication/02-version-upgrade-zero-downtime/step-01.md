# Step 1: Understanding WAL Levels

## The Foundation of Replication

Before any replication can work, you need the right **WAL level**.

### WAL Levels

| Level | Description | Features | WAL Size |
|-------|-------------|----------|----------|
| `minimal` | Crash recovery only | Smallest | No replication |
| `replica` | Physical replication | Medium | Streaming replication |
| `logical` | Row-level changes | Largest | Streaming + Logical |

### Check Current WAL Level

```sql
-- On Postgres 17
docker exec -it pg-upgrade-17 psql -U postgres

SHOW wal_level;  -- Likely 'replica' by default
```

### Why `logical` is Required

Logical replication needs:
1. **Row-level change data** - Which rows changed?
2. **Before/after images** - Old value vs new value
3. **Column-level info** - Which columns changed?

`wal_level = replica` only logs physical changes (which bytes changed).
`wal_level = logical` logs logical changes (which rows changed).

### Change WAL Level

```sql
-- Attempt 1: Try reload (won't work)
ALTER SYSTEM SET wal_level = 'logical';
SELECT pg_reload_conf();
SHOW wal_level;  -- Still 'replica'!
```

**Question**: Why didn't `pg_reload_conf()` work?

<hr>

**Answer**:


Check `pg_settings`:
```sql
SELECT name, context, unit
FROM pg_settings
WHERE name = 'wal_level';
```

`context = 'postmaster'` means **restart required**.
This setting cannot be changed with a simple reload.


### Restart Postgres

```bash
# From docker-compose
docker-compose restart pg-17

# Or within container
docker exec pg-upgrade-17 pg_ctl -D /var/lib/postgresql/data restart
```

### Verify

```sql
SHOW wal_level;  -- Should now be 'logical'
```

---

## Think About It

1. **Why is logical WAL larger?**
   - Contains full row images, not just byte differences
   - Stores column metadata
   - Enables row filtering in replication

2. **When would you use `wal_level = minimal`?**
   - Bulk loading where you don't need replication
   - Can reduce WAL size significantly
   - Must restart to change back

3. **What happens if you have replication and set `wal_level = minimal`?**
   - Replication breaks immediately
   - Replica can't apply changes
   - Must revert to `replica` or `logical`
