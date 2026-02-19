# Step 3: Bootstrap Replicas

Goal: start two replicas from base backup and verify streaming.

## Start replica services

```bash
docker compose --profile replicas up -d
```

## Verify on primary

```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb -c "SELECT application_name, client_addr, state, sync_state FROM pg_stat_replication;"
```

## Verify replicas are read-only

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SHOW transaction_read_only;"
docker exec -it pg-plain-replica-2 psql -U postgres -d appdb -c "SHOW transaction_read_only;"
```

## Check lag

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"
```
