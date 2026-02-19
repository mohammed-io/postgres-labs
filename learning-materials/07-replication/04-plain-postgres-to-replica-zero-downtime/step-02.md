# Step 2: Make Primary Replica-Friendly

Goal: configure primary for streaming replicas.

## 1) Create replication role

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass';
```

## 2) Set replication-related params

```sql
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET wal_keep_size = '1GB';
```

Restart primary to apply static settings:

```bash
docker restart pg-plain-primary
```

## 3) Allow replica network access in `pg_hba.conf`

```bash
docker exec -it pg-plain-primary sh -lc "echo 'host replication replicator 0.0.0.0/0 md5' >> \"$PGDATA/pg_hba.conf\""
docker exec -it pg-plain-primary sh -lc "echo 'host replication replicator ::/0 md5' >> \"$PGDATA/pg_hba.conf\""
docker exec -it pg-plain-primary psql -U postgres -d appdb -c 'SELECT pg_reload_conf();'
```

## 4) Re-check

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
```
