---
name: "Hint Bits & Page-Level Visibility"
category: "01-architecture"
difficulty: "advanced"
time: "40 minutes"
concepts: ["hint bits", "CLOG", "visibility map", "page inspection", "failover performance"]
---

# Hint Bits & Page-Level Visibility

## Scenario

After a planned failover to a replica, your normally-fast read queries suddenly spike from 2ms to 500ms. CPU is fine, no locks, no long queries. The replica just promoted to primary and is doing massive amounts of I/O to CLOG files.

The mystery: **hint bits weren't set on the replica**.

Every row visibility check now requires a trip to the CLOG (pg_xact) to look up whether the inserting transaction committed or aborted. On the old primary, first readers after commit had already set hint bits on the data pages — a single bit per tuple that caches the CLOG answer. The replica never ran those reads, so those bits were never set. Now every SELECT pays the price.

## Why This Lab Exists

Hint bits are one of PostgreSQL's most important yet least understood performance mechanisms. They live inside every tuple header on every data page, silently saving billions of CLOG lookups per second in a healthy database. But they are ephemeral — they are not WAL-logged by default, so replicas don't receive them. This creates a ticking time bomb for any system that fails over to a replica that hasn't seen read traffic.

Most DBAs never think about hint bits until a post-failover incident forces them to. This lab gives you hands-on experience with `pageinspect` to see hint bits directly, understand when they're set, measure their impact on performance, and learn how to prevent hint bit storms.

## Real-World Example

### 1. Stripe - Post-Failover Latency Spike

After failing over from a primary to a hot standby replica, read latency spiked 10-50x for several minutes. The cause: the replica had been handling only replication replay, not read queries. No hint bits were set on any data pages. Every visibility check required a CLOG lookup, generating massive random I/O against `pg_xact` files. The fix was pre-warming replicas with read traffic.

### 2. GitLab - Replica Promotion Performance

During a planned switchover, the promoted replica showed elevated query times. Investigation revealed that the replica's autovacuum had been running (setting hint bits as a side effect) on hot tables, but cold tables hadn't been vacuumed yet. The solution: enable `wal_log_hints` and ensure autovacuum runs on replicas too.

### 3. Amazon RDS - Multi-AZ Failover

RDS PostgreSQL multi-AZ failovers often show a brief period of elevated latency (30-120 seconds). One contributing factor is hint bit storms on the newly-promoted standby. AWS documentation recommends pre-warming read replicas before failover.

## What You Will Build

```
Phase 1: [Hint Bit Anatomy] - Inspect tuple headers and see hint bits with pageinspect
Phase 2: [Hint Bit Storms] - Simulate a failover scenario and measure the I/O impact
```

## Quick Start

```bash
cd lab && docker compose up -d
```

## Lab Flow

1. Read `step-01.md`: Hint Bit Fundamentals - understand what hint bits are and how they work
2. Read `step-02.md`: Hint Bit Storms & Failover - learn why failovers cause I/O spikes and how to prevent them
3. Run `lab/verify.sql` to validate your environment and understanding
4. Run `lab/explore.sql` to inspect tuple headers and hint bits directly
5. Run `lab/benchmark.sql` to measure the performance difference with and without hint bits
6. Try `lab/break-it.sql` - see what happens in edge cases around hint bits

## Learning Objectives

- Understand the relationship between CLOG, hint bits, and tuple visibility
- Use `pageinspect` to inspect tuple headers and observe hint bit flags
- Measure the performance impact of missing hint bits
- Diagnose and prevent hint bit storms after failover
- Understand the `wal_log_hints` GUC and when to enable it

## Your Tasks

1. Inspect tuple headers with pageinspect and identify hint bit flags
2. Observe hint bits being set on first read after commit
3. Measure the performance difference between cold and warm hint bits
4. Simulate a hint bit storm scenario

## Common Hint Bit Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Hint bit storm after failover | Read latency spikes 10-50x | Pre-warm replica with reads or autovacuum |
| Missing `wal_log_hints` | `pg_rewind` fails after failover | Enable `wal_log_hints = on` |
| Cold replica tables | Specific tables slow after promotion | Run analytical queries on replica |
| Long-running transactions | Hint bits cannot be set for recent tuples | Keep transactions short |
