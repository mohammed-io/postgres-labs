# Step 3: Bootstrap Replicas

Goal: start two replicas from base backup and verify streaming replication.

## Understanding pg_basebackup

The `pg_basebackup` command creates a physical copy of the primary's data directory:

| Flag | Meaning |
|------|---------|
| `-h` | Primary host |
| `-D` | Target data directory |
| `-U` | Replication user |
| `-P` | Show progress |
| `-w` | No password prompt (uses PGPASSWORD env) |
| `-R` | Create standby.signal + primary_conninfo |
| `-X stream` | Stream WAL during backup (vs `-X fetch`) |
| `--slot` | Use replication slot (prevents WAL recycling) |

**Why `-X stream` over `-X fetch`?**
- `fetch`: WAL collected at end of backup (can fail if WAL recycled)
- `stream`: WAL streamed in parallel (safer, no window for recycling)

## Start replica services

```bash
docker compose --profile replicas up -d
```

This runs the bootstrap commands defined in docker-compose.yml. Watch the logs:

```bash
docker compose --profile replicas logs -f postgres-replica-1
```

## Verify on primary

Check that replicas are connected:

```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
SELECT application_name, client_addr, state, sync_state
FROM pg_stat_replication;
"
```

Expected output:
```
 application_name  | client_addr | state   | sync_state
-------------------+-------------+---------+------------
 pg-plain-replica-1| 172.x.x.x   | streaming| async
 pg-plain-replica-2| 172.x.x.x   | streaming| async
```

## Verify replication slots are active

```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
"
```

Both slots should show `active = t`.

## Verify replicas are read-only

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
docker exec -it pg-plain-replica-2 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
```

Both should return `t` (true = in recovery = standby).

## Check replication lag

On primary:
```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
SELECT application_name, 
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag
FROM pg_stat_replication;
"
```

On replica:
```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "
SELECT now() - pg_last_xact_replay_timestamp() AS lag;
"
```

Lag should be sub-second for an idle system.

## Verify data consistency

Compare row counts (should match):

```bash
# On primary
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "SELECT COUNT(*) FROM accounts;"

# On replica
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT COUNT(*) FROM accounts;"
```

## Test replication in action

1. Write to primary:
```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
INSERT INTO accounts (owner, balance) VALUES ('test_user', 100.00);
"
```

2. Immediately read from replica:
```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "
SELECT * FROM accounts WHERE owner = 'test_user';
"
```

You should see the new row (may need to retry once if lag > 0).

## Check WAL receiver on replica

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "
SELECT status, sender_host, sender_port, received_lsn, latest_end_lsn
FROM pg_stat_wal_receiver;
"
```

Status should be `streaming`.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Replica won't start | pg_hba.conf has replication rule? |
| "no pg_hba.conf entry" | Check `SHOW hba_file;` and verify rules |
| WAL recycling error | Slots exist? `wal_keep_size` adequate? |
| Connection refused | Primary running? Network reachable? |
| Lag keeps growing | Network bandwidth? Disk I/O on replica? |
