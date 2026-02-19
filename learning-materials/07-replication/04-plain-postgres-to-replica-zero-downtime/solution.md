# Solution Guide

This is a reference path, not the only valid implementation.

## 1) Baseline checks

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
```

## 2) Configure primary

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET wal_keep_size = '1GB';
```

```bash
docker restart pg-plain-primary
docker exec -it pg-plain-primary sh -lc "echo 'host replication replicator 0.0.0.0/0 md5' >> \"$PGDATA/pg_hba.conf\""
docker exec -it pg-plain-primary sh -lc "echo 'host replication replicator ::/0 md5' >> \"$PGDATA/pg_hba.conf\""
docker exec -it pg-plain-primary psql -U postgres -d appdb -c 'SELECT pg_reload_conf();'
```

## 3) Start replicas

```bash
docker compose --profile replicas up -d
```

```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "SELECT application_name, state FROM pg_stat_replication;"
```

## 4) Simulate zero-downtime cutover

```bash
docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data
```

Then switch client endpoint to replica-1 and validate writes.
