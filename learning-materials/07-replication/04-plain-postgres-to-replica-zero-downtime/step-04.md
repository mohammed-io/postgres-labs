# Step 4: Zero-Downtime Transition Practice

Goal: simulate switchover/failover patterns without stopping all services.

## Suggested exercise

1. Run traffic against current primary (`localhost:5451`).
2. Promote replica 1.
3. Repoint traffic to promoted node.
4. Measure observed downtime.

## Promote replica

```bash
docker exec -it pg-plain-replica-1 pg_ctl promote -D /var/lib/postgresql/data
```

## Verify role change

```bash
docker exec -it pg-plain-replica-1 psql -U postgres -d appdb -c "SELECT pg_is_in_recovery();"
```

`false` means promoted primary.

## Debrief questions

- What caused downtime during endpoint switch?
- Which parts can be automated (VIP, proxy, DNS, service discovery)?
- How would you prevent split-brain in real systems?
