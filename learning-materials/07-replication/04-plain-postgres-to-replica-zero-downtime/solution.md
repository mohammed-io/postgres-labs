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

Restart primary to apply static settings:

```bash
docker restart pg-plain-primary
```

Wait for it to come back up:

```bash
docker exec -it pg-plain-primary pg_isready -U postgres -d appdb
```

## 3) Create replication slots (RECOMMENDED)

Replication slots guarantee WAL retention until the replica catches up.
Without slots, if a replica falls behind, WAL can be recycled and replication breaks.

```sql
SELECT pg_create_physical_replication_slot('replica_1_slot');
SELECT pg_create_physical_replication_slot('replica_2_slot');
```

Verify slots exist:

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

## 5) Re-check configuration

```sql
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SELECT slot_name, slot_type, active FROM pg_replication_slots;
```

## 6) Start replicas

The docker-compose.yml handles pg_basebackup automatically. The `-R` flag creates
standby.signal and configures primary_conninfo, but we need to specify the slot:

```bash
docker compose --profile replicas up -d
```

Verify replication on primary:

```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
SELECT application_name, client_addr, state, sync_state, 
       sent_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;
"
```

Verify slots are now active:

```sql
SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;
```

## 7) Verify replicas are read-only

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
docker exec -it pg-plain-replica-2 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
```

Both should return `t` (true = in recovery mode = replica).

## 8) Check replication lag

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "
SELECT 
    now() - pg_last_xact_replay_timestamp() AS lag,
    pg_last_wal_receive_lsn() AS received,
    pg_last_wal_replay_lsn() AS replayed;
"
```

## 9) Zero-Downtime Cutover Procedure

### Option A: Planned Switchover (Recommended for maintenance)

1. **Stop application writes to current primary:**
   ```bash
   # Either stop the app, or use pg_ctl pause (requires superuser)
   ```

2. **Verify replica has caught up:**
   ```bash
   docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
   SELECT application_name, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
   FROM pg_stat_replication;
   "
   # Lag should be 0 or very small
   ```

3. **Promote replica-1 to primary:**
   ```bash
   docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data
   ```

4. **Verify promotion:**
   ```bash
   docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
   # Should return 'f' (false = primary)
   ```

5. **Switch application traffic:**
   - Update connection string from `localhost:5451` to `localhost:5452`
   - Or update VIP/DNS to point to new primary

6. **Measure actual downtime:**
   ```bash
   python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5452/appdb"
   ```

### Option B: Emergency Failover (When primary crashes)

1. **Verify primary is down:**
   ```bash
   docker exec -it pg-plain-primary pg_isready
   # Should fail
   ```

2. **Promote the most caught-up replica:**
   ```bash
   # Check which replica has latest data
   docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT pg_last_wal_replay_lsn();"
   docker exec -it pg-plain-replica-2 psql -U postgres -d appdb -c "SELECT pg_last_wal_replay_lsn();"
   
   # Promote the one with higher LSN
   docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data
   ```

3. **Redirect traffic immediately.**

## 10) Failback Procedure (Rejoining old primary)

After a switchover, the old primary can be converted to a replica:

1. **Stop the old primary:**
   ```bash
   docker stop pg-plain-primary
   ```

2. **Remove old data (it's stale now):**
   ```bash
   docker exec -it pg-plain-primary rm -rf /var/lib/postgresql/data/*
   ```

3. **Take a new base backup from the new primary:**
   ```bash
   docker exec -it pg-plain-primary bash -c "
   export PGPASSWORD=replicator_pass
   pg_basebackup -h pg-plain-replica-1 -D /var/lib/postgresql/data -U replicator -P -w -R
   "
   ```

4. **Start as replica:**
   ```bash
   docker start pg-plain-primary
   ```

## 11) Cleanup and Reset (To re-run the lab)

```bash
# Stop all containers
docker compose --profile replicas down

# Remove volumes to reset data
docker volume rm postgres-deep-dive_primary-data postgres-deep-dive_replica1-data postgres-deep-dive_replica2-data 2>/dev/null || true

# Start fresh
docker compose up -d
```

## Data Consistency Verification After Cutover

After promoting a replica, verify data integrity:

```sql
-- Check row counts match expectations
SELECT 'accounts' AS table_name, COUNT(*) AS rows FROM accounts
UNION ALL
SELECT 'ledger', COUNT(*) FROM ledger;

-- Check for data corruption
SET enable_seqscan = off;
SELECT COUNT(*) FROM accounts WHERE id IS NULL;  -- Should be 0
SELECT COUNT(*) FROM ledger WHERE id IS NULL;    -- Should be 0

-- Verify recent transactions exist
SELECT MAX(created_at) FROM ledger;
SELECT MAX(updated_at) FROM accounts;
```

## Synchronous Replication (Optional - Zero Data Loss)

For zero data loss guarantees, configure synchronous replication:

```sql
-- On the new primary after promotion:
ALTER SYSTEM SET synchronous_commit = on;
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (pg-plain-replica-2)';
SELECT pg_reload_conf();
```

This ensures every commit waits for at least one replica to confirm write.

Trade-offs:
- **Pros:** Zero data loss on primary failure
- **Cons:** Higher write latency (waits for replica ACK)
