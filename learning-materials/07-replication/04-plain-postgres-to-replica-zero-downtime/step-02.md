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

## 3) Create replication slots (RECOMMENDED)

Replication slots track how far each replica has progressed. They guarantee
that WAL files won't be recycled until the replica catches up.

Without slots: If a replica falls behind, the primary might delete WAL it still needs → replication breaks.

```sql
SELECT pg_create_physical_replication_slot('replica_1_slot');
SELECT pg_create_physical_replication_slot('replica_2_slot');
```

Verify:

```sql
SELECT slot_name, slot_type, active FROM pg_replication_slots;
```

## 4) Allow replica network access in `pg_hba.conf`

```bash
docker exec -it pg-plain-primary sh -lc "echo 'host replication replicator 0.0.0.0/0 md5' >> \"$PGDATA/pg_hba.conf\""
docker exec -it pg-plain-primary sh -lc "echo 'host replication replicator ::/0 md5' >> \"$PGDATA/pg_hba.conf\""
docker exec -it pg-plain-primary psql -U postgres -d appdb -c 'SELECT pg_reload_conf();'
```

Verify the rule was added:

```bash
docker exec -it pg-plain-primary sh -lc 'cat "$PGDATA/pg_hba.conf" | grep replication'
```

## 5) Re-check

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SELECT slot_name, slot_type, active FROM pg_replication_slots;
```

## 6) (Optional) Synchronous Replication for Zero Data Loss

If your application requires zero data loss on failover:

```sql
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (pg-plain-replica-1)';
SELECT pg_reload_conf();
```

Trade-offs:
- **Pro:** No committed transactions lost on primary crash
- **Con:** Higher write latency (waits for replica acknowledgment)
