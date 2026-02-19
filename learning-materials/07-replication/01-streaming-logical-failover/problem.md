---
name: "Streaming, Logical & Failover"
category: "07-replication"
difficulty: "advanced"
time: "90 minutes"
concepts: ["streaming replication", "logical replication", "failover", "promotion"]
---

# Streaming, Logical & Failover

## Scenario

Your production database needs high availability and read scalability. You need:
- Read replicas to handle read-heavy workloads
- Disaster recovery capability
- Zero-downtime failover if the primary crashes

Your job is to implement streaming and logical replication, then practice failover procedures.

## Why This Lab Exists

Replication is critical for production PostgreSQL databases:
- **Streaming replication** enables read scaling and disaster recovery
- **Logical replication** allows selective replication of data
- **Failover procedures** ensure zero-downtime when the primary fails
- **Monitoring replication lag** prevents data loss or performance issues

Without proper replication, you have a single point of failure. And without understanding how to failover, you risk hours of downtime during outages.

## Real-World Example

### 1. GitLab - 6 Hours of Data Lost ([GitLab Blog](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/))

**Date:** January 31, 2017

**Problem:** An engineer accidentally deleted the production database instead of the replica.

**Result:** 300GB of data lost, 6 hours of production data permanently gone, ~18 hours of downtime.

**Root cause:** Human error combined with inadequate safeguards (no delayed replication, no backup verification).

**Solution implemented:** After this incident, GitLab implemented delayed replication as disaster recovery strategy.

**What this teaches:** Accidents happen. You need automatic recovery mechanisms like delayed replicas to prevent catastrophic data loss.

### 2. GitLab - Delayed Replication for DR ([GitLab Blog](https://about.gitlab.com/blog/delayed-replication-for-disaster-recovery-with-postgresql/))

**After 2017 incident:** GitLab implemented delayed replication.

**How it works:** Replica is delayed (e.g., 1 hour behind) by setting `recovery_min_apply_delay = '1h'`. This provides a recovery window for accidental deletions.

**Benefits:** Protects against human error and some types of data corruption.

**What this teaches:** Delayed replicas are a simple, effective disaster recovery strategy that many companies use in production.

### 3. AWS - Delayed Read Replicas for RDS ([AWS Database Blog](https://aws.amazon.com/blogs/database/using-delayed-read-replicas-for-amazon-rds-for-postgresql-disaster-recovery/))

**Official AWS guidance** on using delayed replicas for disaster recovery.

**Production best practices:**
- Monitor replication lag actively
- Test failover procedures regularly
- Have manual failover procedures documented
- Verify data consistency after failover

**What this teaches:** Replication sounds simple in theory, but production requires rigorous procedures and monitoring.

## What You Will Build

```
Phase 1: [Streaming Replication] - Setup and verify physical replicas
Phase 2: [Logical Replication] - Setup selective data replication
Phase 3: [Replication Monitoring] - Track lag and health
Phase 4: [Failover Practice] - Promote replicas and simulate failovers
```

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: Streaming Replication - setup and verify physical replicas
2. Read `step-02.md`: Logical Replication - setup selective data replication
3. Read `step-03.md`: Replication Monitoring - track lag and health
4. Read `step-04.md`: Failover Practice - promote replicas and simulate failovers
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with various failure scenarios

## Learning Objectives

Master PostgreSQL replication for high availability and scaling.

## Replication Architecture

```
Primary (write) → WAL Streaming → Replica(s) (read)
                  → Logical Publication → Subscriber
```

## Your Tasks

1. Setup streaming replication
2. Setup logical replication
3. Practice failover/promotion
4. Understand replication lag

## Key Commands

```sql
-- Primary: Check replication status
SELECT * FROM pg_stat_replication;

-- Replica: Check lag
SELECT NOW() - pg_last_xact_replay_timestamp() AS lag;

-- Create publication
CREATE PUBLICATION mypub FOR ALL TABLES;

-- Create subscription
CREATE SUBSCRIPTION mysub
CONNECTION 'host=primary port=5432 dbname=mydb'
PUBLICATION mypub;
```

## Downtime Monitor

```bash
# While testing failover, run:
python downtime-monitor.py "postgres://postgres:postgres@localhost:5432/postgres"
```
