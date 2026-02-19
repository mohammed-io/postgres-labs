---
name: "Plain Postgres → Replica-Ready → Zero-Downtime"
category: "07-replication"
difficulty: "advanced"
time: "120 minutes"
concepts: ["postgres defaults", "wal_level", "pg_hba", "streaming replication", "base backup", "zero-downtime cutover"]
---

# Plain Postgres -> Replica-Ready -> Zero-Downtime

## Scenario

You are given a normal PostgreSQL instance with near-default settings.
Your job is to:

1. Audit defaults
2. Make primary replication-ready
3. Bootstrap replicas
4. Validate replication health
5. Practice zero-downtime switchover/failover

## Why This Lab Exists

Most tutorials start with a preconfigured primary. Real production work usually does not.
This lab focuses on the transition journey.

## What You Will Build

```
Phase 1: [Primary only]
Phase 2: [Primary] => [Replica 1] [Replica 2]
Phase 3: [App/traffic] cutover with no hard stop
```

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

1. Read `step-01.md`: inspect defaults
2. Read `step-02.md`: make primary replication-ready
3. Read `step-03.md`: start replicas + verify lag
4. Read `step-04.md`: practice zero-downtime cutover ideas
5. Run `lab/verify.sql` throughout

## Optional Traffic + Downtime Checks

```bash
python3 ../../../lab-tools/traffic-simulator.py 10 100 120 &
python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5451/appdb"
```
