# Step 4: Zero-Downtime Transition Practice

Goal: simulate switchover/failover patterns without stopping all services, and understand split-brain prevention.

## Understanding Zero-Downtime

"Zero-downtime" means **application disruption < 5 seconds**. Sources of downtime:

| Phase | Downtime Source | Mitigation |
|-------|-----------------|------------|
| Pre-promotion | None | - |
| Promotion | ~1-2 seconds | `pg_promote()` is fast |
| DNS/VIP switch | 0-30 seconds | Use VIP or connection pooler |
| App reconnect | Variable | Connection pooling, retries |

## Exercise: Simulate Zero-Downtime Cutover

1. Start traffic against current primary (`localhost:5451`):
   ```bash
   python3 ../../../lab-tools/traffic-simulator.py 10 100 120 &
   python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5451/appdb"
   ```

2. Verify replica is caught up:
   ```bash
   docker exec -it pg-plain-primary psql -U postgres -d appdb -c "
   SELECT application_name, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
   FROM pg_stat_replication;
   "
   ```

3. Promote replica-1:
   ```bash
   docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data
   ```

4. Verify promotion succeeded:
   ```bash
   docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
   # Should return 'f' (false = primary)
   ```

5. Repoint traffic to new primary (manual step):
   - Stop traffic-simulator
   - Restart with new connection string: `localhost:5452`

## Split-Brain Prevention

**Split-brain** = two primaries accepting writes independently. Data divergence is catastrophic.

### How Split-Brain Occurs

```
Scenario: Network partition between Primary and Replica
1. Primary still running, but isolated from Replica
2. Replica's replication stops, WAL lag grows
3. Someone promotes Replica (thinking Primary is dead)
4. Both are now accepting writes → DIVERGENCE
```

### Prevention Strategies

| Strategy | How It Works | Trade-offs |
|----------|--------------|------------|
| **STONITH (Shoot The Other Node In The Head)** | Power off/fence old primary before promoting | Requires out-of-band management |
| **Consensus (Patroni, etcd)** | Only promote if majority agrees | External dependency |
| **Witness Server** | Third node arbitrates | Additional infrastructure |
| **Manual: Verify old primary is DOWN** | Ensure old primary truly unreachable | Human error risk |

### Manual Split-Brain Prevention (This Lab)

Before promoting ANY replica:

```bash
# 1. Verify primary is truly down
docker exec -it pg-plain-primary pg_isready
# Expected: "pg_isready: could not connect to server"

# 2. Check from replica's perspective
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "
SELECT status FROM pg_stat_wal_receiver;
"
# Should show stopped/disconnected

# 3. Ensure old primary cannot come back
docker stop pg-plain-primary  # Physically stop it

# 4. ONLY THEN promote
docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data
```

### After Promotion: What About Other Replicas?

Replica-2 is still trying to connect to old primary. Fix it:

```bash
# Stop replica-2
docker stop pg-plain-replica-2

# Update its primary_conninfo to point to new primary
# (In production, use recovery.conf or postgresql.auto.conf)

# For this lab, rebuild replica-2 from new primary:
docker exec -it pg-plain-replica-2 bash -c "
rm -rf /var/lib/postgresql/data/*
export PGPASSWORD=replicator_pass
pg_basebackup -h pg-plain-replica-1 -D /var/lib/postgresql/data -U replicator -P -w -R
"
docker start pg-plain-replica-2
```

## Data Consistency Verification

After any failover/switchover, verify data integrity:

```bash
# On new primary
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "
SELECT 'accounts' AS tbl, COUNT(*) AS rows FROM accounts
UNION ALL
SELECT 'ledger', COUNT(*) FROM ledger;
"
```

Compare with expected values. If discrepancies exist, investigate:
- Was all WAL replayed before promotion?
- Did any transactions get lost during the switch?

## Cleanup and Reset (Re-run the Lab)

To start fresh:

```bash
# Stop all containers
docker compose --profile replicas down

# Remove volumes (WARNING: destroys all data)
docker volume rm postgres-deep-dive_primary-data \
                 postgres-deep-dive_replica1-data \
                 postgres-deep-dive_replica2-data 2>/dev/null || true

# Start fresh
docker compose up -d

# Wait for primary to be ready
sleep 5
docker exec -it pg-plain-primary pg_isready -U postgres -d appdb
```

## Debrief Questions

1. **What caused downtime during endpoint switch?**
   - DNS TTL? VIP failover? Connection string update?

2. **Which parts can be automated?**
   - VIP management (keepalived, AWS Elastic IP)
   - Connection pooler (PgBouncer, Pgpool-II)
   - Orchestration (Patroni, Stolon, pg_auto_failover)

3. **How would you prevent split-brain in production?**
   - Use Patroni with etcd for consensus
   - Use cloud provider's managed PostgreSQL (RDS, Cloud SQL)
   - Implement STONITH with IPMI/iLO

4. **What's your RPO (Recovery Point Objective)?**
   - Async replication: potentially seconds of data loss
   - Sync replication: zero data loss, but higher latency

## Next Steps

- Try the `break-it.sql` scenarios
- Experiment with synchronous replication
- Practice the failback procedure (rejoining old primary)
