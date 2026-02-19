---
name: "Read Replicas & Failover (Zero Downtime)"
category: "07-replication"
difficulty: "advanced"
time: "90 minutes"
concepts: ["streaming replication", "read replicas", "failover", "promotion"]
---

# Read Replicas & Failover

## Scenario

Your application reads from the primary database, but you need:
- **Read replicas** to offload read queries from the primary
- **Write scaling** across multiple primaries (sharding)
- **Zero-downtime failover** if the primary crashes

Your job is to setup read replicas, monitor them, and practice failover procedures.

## Why This Lab Exists

Streaming replication is the standard way to scale reads and provide disaster recovery:
- **Read scaling:** Route read queries to replicas
- **Disaster recovery:** Promote replica if primary fails
- **Offline workloads:** Run analytical queries on replicas without affecting primary
- **Geographic distribution:** Replicate to different regions for low-latency reads

Without replicas, you're limited to the primary's capacity. With replicas, you can scale reads horizontally and protect against single points of failure.

## Real-World Example

### Read Scaling for High-Traffic Applications

**Problem:** E-commerce site with 10,000 queries/second. All queries hit the primary, causing high latency.

**Solution:** Add 3 read replicas, configure PgBouncer to route reads to replicas. Primary handles only writes.

**Result:** Write latency unchanged, read latency reduced 70%.

**What this teaches:** Read scaling requires routing logic. PgBouncer or similar proxies are essential for production.

### Zero-Downtime Failover

**Problem:** Primary server hardware fails at 3 AM.

**Solution:**
1. Detect primary failure (automated health checks)
2. Promote most up-to-date replica
3. Redirect traffic to new primary
4. Rebuild failed primary as replica

**Result:** Users notice nothing. Downtime is seconds.

**What this teaches:** Failover needs automation. Manual failover takes too long for production outages.

## What You Will Build

```
Phase 1: [Replica Setup] - Setup streaming replicas
Phase 2: [Read Query Routing] - Test read queries on replicas
Phase 3: [Replication Monitoring] - Track lag and health
Phase 4: [Failover Practice] - Promote replicas and simulate failures
Phase 5: [Traffic Simulation] - Run traffic during failover
```

## Quick Start

```bash
cd lab
docker-compose up -d

# Monitor downtime
python downtime-monitor.py "postgres://postgres:postgres@localhost:5435/appdb" &

# Simulate traffic
python traffic-simulator.py 10 100 120 &
```

## Lab Flow

1. Read `step-01.md`: Replica Setup - setup streaming replicas
2. Read `step-02.md`: Read Query Routing - test read queries on replicas
3. Read `step-03.md`: Replication Monitoring - track lag and health
4. Read `step-04.md`: Failover Practice - promote replicas and simulate failures
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with various failure scenarios

## Learning Objectives

Master streaming replication for read scaling and failover.

## Architecture

```
          [App]
            |
      +-----+-----+
      |     |     |
   [Primary] [Replica 1]
  writes    reads
      |
      +---> [Replica 2]
            reads
```

## Your Tasks

1. Setup streaming replication (physical)
2. Monitor replication lag
3. Test read queries on replicas
4. Practice failover (promote replica to primary)
5. Use downtime monitor to verify zero downtime

## Key Commands

```sql
-- Primary: Check replication status
SELECT * FROM pg_stat_replication;

-- Replica: Check lag
SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;

-- Failover: Promote replica
docker exec pg-replica-1 pg_ctl promote -D /var/lib/postgresql/data;
```

## Real-World Production Patterns

| Pattern | Use Case | Trade-offs |
|---------|----------|------------|
| **Single primary, multiple replicas** | Most common | Simple, but primary is bottleneck for writes |
| **Multi-primary (sharding)** | High write throughput | Complex routing, eventual consistency issues |
| **Hot standby** | Continuous backup | Always up-to-date, but writes disabled |
| **Delayed replica** | Disaster recovery | Manual failover, risk of data loss |

## Failover Best Practices

1. **Monitor actively:** Never assume replicas are caught up
2. **Test regularly:** Run failover drills quarterly
3. **Document procedures:** Everyone should know the steps
4. **Automate health checks:** Don't wait for users to report issues
5. **Verify after failover:** Check data consistency before redirecting traffic
