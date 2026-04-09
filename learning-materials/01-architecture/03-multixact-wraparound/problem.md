---
name: "MultiXact ID Wraparound"
category: "01-architecture"
difficulty: "advanced"
time: "40 minutes"
concepts: ["multixact", "mxid", "wraparound", "SELECT FOR SHARE", "row locking", "freeze"]
---

# MultiXact ID Wraparound

## Scenario

Your application uses `SELECT FOR SHARE` to implement optimistic locking — a pattern where multiple transactions can read a row concurrently while preventing modifications until all readers release their locks. After running for months without proper autovacuum tuning, you start seeing warnings about multixact ID wraparound in the logs:

```
WARNING: database "production_db" must be vacuumed within 17700598 transactions
HINT: To avoid a database shutdown, execute a database-wide VACUUM of that database.
```

Unlike regular transaction ID (XID) wraparound — which every DBA knows about — almost no one on your team has heard of multixacts. The documentation is sparse, the monitoring dashboards don't track it, and the autovacuum settings you tuned for XID wraparound don't fully apply. You need to understand what multixacts are, why they're accumulating, and how to prevent the looming disaster before the database stops accepting commands entirely.

## Why This Lab Exists

MultiXact ID wraparound is the **lesser-known cousin** of XID wraparound, and it's more dangerous precisely because it's less understood. Here's why:

1. **Most monitoring misses it.** Standard dashboards track `age(datfrozenxid)` but skip `age(dat_minmxid)`. Your database can be in perfect health by XID metrics while silently approaching multixact wraparound.

2. **It's triggered by legitimate patterns.** `SELECT FOR SHARE` and `SELECT FOR KEY SHARE` are valid concurrency-control mechanisms. ORM frameworks like Hibernate use them for version checking. You don't need a bug to trigger this — you need scale.

3. **The failure mode is catastrophic.** When mxid wraps without vacuum, PostgreSQL stops accepting writes entirely with `database is not accepting commands to avoid wraparound`. Recovery requires starting in single-user mode and running `VACUUM FREEZE` — potentially hours of downtime.

4. **Autovacuum has separate knobs.** The settings `autovacuum_multixact_freeze_max_age` and `autovacuum_multixact_freeze_table_age` are independent from their XID counterparts. Tuning one doesn't tune the other.

## Real-World Examples

### 1. Braintree Payment Processing (PayPal) — Shared Locking for Consistency

Payment processors like Braintree use shared row locks (`SELECT FOR SHARE`) to ensure that when multiple parts of a system read a transaction record simultaneously, no modification can occur until all readers are done. At scale — millions of transactions — this creates enormous numbers of multixact IDs. If autovacuum isn't configured to freeze multixacts aggressively, the `pg_multixact` directory grows unbounded and wraparound looms.

### 2. Hibernate ORM Applications — Implicit FOR SHARE

Many Java applications using Hibernate with optimistic locking generate `SELECT ... FOR UPDATE` or `SELECT ... FOR SHARE` queries under the hood when using `LockModeType.PESSIMISTIC_READ`. Developers writing JPA code often don't realize each lock attempt creates multixact entries. A large-scale deployment with hundreds of concurrent sessions locking the same rows can burn through mxid space faster than XID space.

### 3. PostgreSQL Mailing List Incident Reports

Multiple incidents reported on `pgsql-general` and `pgsql-admin` follow the same pattern:
- Database runs fine for months
- Warnings about multixact wraparound appear in logs but go unnoticed
- No monitoring for `dat_minmxid` age
- Database suddenly stops accepting commands
- Recovery in single-user mode takes hours on large tables
- Post-mortem reveals `SELECT FOR SHARE` usage in reporting queries

The common thread: teams had XID wraparound monitoring but zero multixact monitoring.

## What You Will Learn

```
Phase 1: [Understand MultiXacts]    — What they are, when they're created, how they differ from XIDs
Phase 2: [Detect Wraparound Risk]   — Monitor dat_minmxid age, understand freeze thresholds
Phase 3: [Simulate the Problem]     — Create rapid multixact accumulation, watch age climb
Phase 4: [Prevent and Fix]          — Proper autovacuum settings, manual freeze, monitoring queries
```

## Quick Start

```bash
# Start the lab environment
cd postgres-deep-dive/learning-materials/01-architecture/03-multixact-wraparound/lab
docker compose up -d

# Wait for Postgres to be healthy
docker exec pg-multixact pg_isready -U postgres

# Run setup
docker exec pg-multixact psql -U postgres -d labdb -f /docker-entrypoint-initdb.d/01-setup.sql

# Verify the environment
docker exec pg-multixact psql -U postgres -d labdb -c "SELECT version();"
```

## Lab Flow

1. Read `step-01.md`: Understand what MultiXact IDs are and when they're created
2. Read `step-02.md`: Learn how to detect and prevent mxid wraparound
3. Run `lab/setup.sql`: Create tables and seed data with multixact-prone patterns
4. Run `lab/explore.sql`: Discover multixact state in your database
5. Run `lab/benchmark.sql`: Measure the overhead of shared locking patterns
6. Run `lab/break-it.sql`: Trigger rapid multixact accumulation and observe the consequences
7. Run `lab/verify.sql`: Validate your understanding with comprehensive checks

## Learning Objectives

After completing this lab, you should be able to:

1. Explain what a multixact ID is and why it exists (multiple transactions locking the same row)
2. Identify when multixacts are created in your own workload
3. Monitor `age(dat_minmxid)` alongside `age(datfrozenxid)`
4. Configure autovacuum settings for multixact freeze independently
5. Diagnose and fix multixact wraparound before it causes an outage
6. Understand why multixact wraparound is more dangerous than regular XID wraparound

## Prerequisites

- Basic understanding of PostgreSQL MVCC (see `01-process-model-and-mvcc` lab)
- Familiarity with `VACUUM`, `VACUUM FREEZE`, and autovacuum concepts
- Comfortable running SQL queries and reading system catalogs

## Your Tasks

### Task 1: Observe Multixact Creation

Create a scenario where multiple concurrent transactions lock the same row with `SELECT FOR SHARE`. Observe the multixact ID assigned to the row's `xmax` field.

### Task 2: Monitor MultiXact Age

Query `pg_database` to check the age of `dat_minmxid` for all databases. Understand what constitutes a dangerous age and set up alerting thresholds.

### Task 3: Simulate Rapid Accumulation

Use the `break-it.sql` scenarios to create thousands of multixact entries rapidly. Watch the mxid counter climb and observe autovacuum's response (or lack thereof with misconfigured settings).

### Task 4: Fix and Prevent

Apply the correct autovacuum settings, run manual `VACUUM FREEZE`, and verify that the multixact age drops back to safe levels.

## Verification

```bash
docker exec pg-multixact psql -U postgres -d labdb -f /docker-entrypoint-initdb.d/01-setup.sql
# Then run verify.sql
docker exec pg-multixact psql -U postgres -d labdb -f lab/verify.sql
```

## Expected Outcomes

After completing this lab, you should understand:

| Concept | Key Insight |
|---------|-------------|
| **MultiXact ID** | Maps multiple XIDs to a single ID when rows have shared locks |
| **32-bit limit** | Same wraparound problem as regular XIDs at ~2 billion |
| **xmax storage** | Multixact IDs are stored in the row's `xmax` field with special infomask flags |
| **pg_multixact directory** | Stores member data on disk; grows with multixact creation |
| **Detection** | Monitor `age(dat_minmxid)` in `pg_database` — warn at 100M, critical at 150M |
| **Prevention** | `autovacuum_multixact_freeze_max_age`, `autovacuum_multixact_freeze_table_age` |
| **Recovery** | Single-user mode `VACUUM FREEZE` — same painful process as XID wraparound |
