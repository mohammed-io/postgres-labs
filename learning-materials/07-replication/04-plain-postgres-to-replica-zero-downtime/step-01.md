# Step 1: Inspect Plain Defaults

Goal: confirm this is a plain primary, not replication-ready.

## Check core settings

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SHOW hot_standby;
```

You should see defaults like:
- `wal_level = replica` (or distro default)
- `max_wal_senders = 10` may vary
- no replication user yet

## Inspect `pg_hba.conf`

```sql
SHOW hba_file;
```

Then from shell:

```bash
docker exec -it pg-plain-primary sh -lc 'cat "$PGDATA/pg_hba.conf" | tail -n 40'
```

No explicit remote replication rule should exist yet.
