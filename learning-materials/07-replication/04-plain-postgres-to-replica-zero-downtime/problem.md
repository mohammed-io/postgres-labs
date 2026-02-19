---
name: "Plain Postgres → Replica-Ready → Zero-Downtime"
category: "07-replication"
difficulty: "advanced"
time: "120 minutes"
concepts: ["postgres defaults", "wal_level", "pg_hba", "streaming replication", "base backup", "zero-downtime cutover", "replication slots", "split-brain prevention"]
---

# Plain Postgres -> Replica-Ready -> Zero-Downtime

## Scenario

You are a DBA at a fintech company. The primary PostgreSQL server has been running for months with near-default settings. Management now requires a high-availability setup with read replicas and the ability to failover with minimal downtime.

Your job is to:

1. Audit the current configuration
2. Make the primary replication-ready
3. Bootstrap replicas with proper protection
4. Validate replication health
5. Practice zero-downtime switchover/failover

## Why This Lab Exists

Most tutorials start with a preconfigured primary server. Real production work usually does not. This lab focuses on the **transition journey** - taking a plain, default-configured PostgreSQL instance and transforming it into a robust, HA-ready system.

The skills learned here apply to:
- Setting up disaster recovery for existing databases
- Migrating from single-node to HA architecture
- Understanding what makes replication "production-ready"

## Real-World Example

**The GitLab Database Incident (2017)**

GitLab experienced a major outage where they lost production data during a database failover. Key lessons:

1. **No replication slots**: When the primary came under load, WAL segments were recycled faster than replicas could consume them
2. **Async replication without monitoring**: Replication lag wasn't monitored, so they didn't know replicas were falling behind
3. **No verified failback procedure**: When they tried to recover, they accidentally deleted the wrong data
4. **Split-brain confusion**: Multiple replicas at different states caused confusion about which had the most recent data

**What this lab teaches to prevent:**
- Using replication slots to prevent WAL recycling
- Monitoring replication lag in real-time
- Having tested failover AND failback procedures
- Verifying data consistency after any topology change

**Other real-world scenarios:**
- **AWS RDS**: Uses replication slots by default for a reason
- **Heroku Postgres**: Requires explicit HA setup for production databases
- **Production outages**: Often caused by misconfigured pg_hba.conf or missing replication user

## What You Will Build

```
Phase 1: [Primary only] - Audit and configure
Phase 2: [Primary] => [Replica 1] [Replica 2] - With slots!
Phase 3: [App/traffic] cutover with verification
Phase 4: Failback capability - Rejoin old primary
```

## Key Concepts Covered

| Concept | Why It Matters |
|---------|----------------|
| `wal_level` | Must be `replica` or `logical` for streaming |
| Replication slots | Prevent WAL recycling during replica lag |
| `pg_hba.conf` | Replication connections need explicit rules |
| `pg_basebackup` | Physical copy with `-R` for auto-configuration |
| Split-brain | Two primaries = data divergence = disaster |

## Quick Start

```bash
cd lab
docker compose up -d
```

Open psql on primary:

```bash
docker exec -it pg-plain-primary psql -U postgres -d appdb
```

## Lab Flow

1. Read `step-01.md`: Inspect defaults and identify gaps
2. Read `step-02.md`: Make primary replication-ready (including slots!)
3. Read `step-03.md`: Bootstrap replicas and verify streaming
4. Read `step-04.md`: Practice zero-downtime cutover and split-brain prevention
5. Run `lab/verify.sql` throughout to check your progress
6. Try `lab/break-it.sql` to understand failure modes

## Optional Traffic + Downtime Checks

For realistic testing:

```bash
python traffic-simulator.py 10 100 120 &
python downtime-monitor.py "postgres://postgres:postgres@localhost:5451/appdb"
```

## Success Criteria

- [ ] Primary configured with `wal_level=replica`, slots, and pg_hba rules
- [ ] Two replicas streaming with minimal lag (<1 second)
- [ ] Replication slots are active (check `pg_replication_slots`)
- [ ] Zero-downtime cutover achieved (<5 seconds disruption)
- [ ] Data consistency verified after promotion
- [ ] Failback procedure tested and documented
