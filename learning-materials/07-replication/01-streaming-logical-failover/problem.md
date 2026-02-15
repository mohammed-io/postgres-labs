---
name: "Streaming, Logical & Failover"
category: "07-replication"
difficulty: "advanced"
time: "90 minutes"
concepts: ["streaming replication", "logical replication", "failover", "promotion"]
---

# Streaming, Logical & Failover

## Learning Objectives

Master PostgreSQL replication for high availability and scaling.

## Why This Matters

| Need | Solution |
|------|----------|
| Read replicas | Streaming replication |
| Selective replication | Logical replication |
| Disaster recovery | Async/Sync replication |
| Zero-downtime upgrades | Logical replication switchover |

## Real World Use

### Verified Real-World Cases

**1. GitLab - 6 Hours of Data Lost ([GitLab Blog](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/))**
   - Date: January 31, 2017
   - Engineer accidentally deleted **production database** instead of replica
   - 300GB of data lost, 6 hours of production data permanently gone
   - ~18 hours of downtime
   - Root cause combination: Human error + inadequate safeguards
   - Led to industry-wide changes in DB operational practices
   - Now uses delayed replication as disaster recovery strategy

**2. GitLab - Delayed Replication for DR ([GitLab Blog](https://about.gitlab.com/blog/delayed-replication-for-disaster-recovery-with-postgresql/))**
   - After 2017 incident, implemented delayed replication
   - Protects against accidental deletions/drops
   - Replica is delayed (e.g., 1 hour behind) giving recovery window
   - Real-world protection against human error

**3. AWS - Delayed Read Replicas for RDS ([AWS Database Blog](https://aws.amazon.com/blogs/database/using-delayed-read-replicas-for-amazon-rds-for-postgresql-disaster-recovery/))**
   - Official AWS guidance on delayed replicas for disaster recovery
   - Production best practices for managing delayed replicas
   - Use case: Recovery from accidental data corruption/deletion

## Architecture

```
Primary (write) → WAL Streaming → Replica(s) (read)
                 → Logical Publication → Subscriber
```

## Your Tasks

1. Setup streaming replication
2. Setup logical replication
3. Practice failover/promotion
4. Understand replication lag

## Quick Start

```bash
cd lab && docker-compose up -d
```

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
python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5432/postgres"
```
