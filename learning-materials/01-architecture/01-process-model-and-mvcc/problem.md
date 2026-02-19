---
name: "PostgreSQL Process Model & MVCC"
category: "01-architecture"
difficulty: "beginner"
time: "60 minutes"
concepts: ["process model", "client connections", "shared memory", "MVCC", "transactions", "isolation"]
---

# PostgreSQL Process Model & MVCC

## Scenario

You're a DBA investigating a production issue:
- Application reports "too many connections" errors
- Database server shows high memory usage
- Some queries appear "stuck"

Your job is to understand what's happening under the hood.

## Why This Lab Exists

Most tutorials skip the internal mechanics of how PostgreSQL handles concurrency. Understanding this is critical for:
- Diagnosing connection issues
- Planning capacity for production workloads
- Choosing the right connection pooling strategy
- Avoiding resource exhaustion from excessive processes

The process-per-connection model and MVCC are foundational to PostgreSQL's design. Without understanding them, you can't properly tune performance or troubleshoot real-world problems.

## Real-World Example

### 1. Instagram - Scaling to 300M+ Users ([Instagram Engineering](https://instagram-engineering.com/instagration-pt-2-scaling-our-infrastructure-to-multiple-data-centers-5745cbad7834))

Instagram scaled from a small startup to **300M users by 2014** while keeping PostgreSQL. Key insight: they used **manual sharding** and **connection pooling** (Redis for routing).

Memory impact: Each connection uses ~10MB of RAM. Without pooling, 1000 connections would consume ~10GB - unsustainable.

### 2. GitLab - Database Deletion Incident (2017) ([Official Postmortem](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/))

An engineer accidentally removed **300GB of production data** during routine maintenance, causing **6 hours of downtime**.

Root cause: Inadequate backup verification + insufficient operational safeguards.

What this teaches: Connection management, backup discipline, and understanding process limits are not theoretical - they prevent production disasters.

### 3. OpenAI - ChatGPT on PostgreSQL ([InfoQ](https://www.infoq.com/news/2026/02/openai-runs-chatgpt-postgres/))

Single PostgreSQL primary handling **millions of requests per day**.

They used **PgBouncer in transaction-pooling mode** to manage connections, reducing latency from **50ms to under 5ms**.

What this teaches: Connection pooling isn't an optimization - it's essential for modern applications.

## What You Will Build

```
Phase 1: [Process Model Analysis] - Understand process-per-connection, MVCC, shared memory
Phase 2: [MVCC Experiment] - Create non-blocking read/write scenarios
Phase 3: [Background Process Investigation] - Map autovacuum, WAL writer, checkpointer roles
Phase 4: [Connection Management] - Test limits and learn pooling strategies
```

## Quick Start

```bash
# Start the lab environment
cd postgres-deep-dive/learning-materials/01-architecture/01-process-model-and-mvcc/lab
docker-compose up -d

# Verify Postgres is running
docker exec postgres-arch psql -U postgres -c "SELECT version();"
```

## Lab Flow

1. Read `step-01.md`: Explore the Process Model - identify processes and memory usage
2. Read `step-02.md`: Understand MVCC in Action - create concurrent read/write scenarios
3. Read `step-03.md`: Background Process Investigation - learn autovacuum, WAL writer, checkpointer
4. Read `step-04.md`: Connection Limits - test max_connections and see connection pooling in action
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - what happens when you exceed limits?

## Learning Objectives

After completing this lab, you should be able to:
1. Explain PostgreSQL's process-per-connection model
2. Describe how MVCC enables non-blocking reads
3. Identify all background processes and their roles
4. Understand when connection pooling is necessary
5. Recognize the memory implications of many connections
6. Troubleshoot connection-related performance issues

## Prerequisites

```bash
# 1. Start the environment
cd lab
docker-compose up -d

# 2. Connect to Postgres
docker exec -it postgres-arch psql -U postgres

# 3. Check the step files if you need hints
```

## Your Tasks

### Task 1: Explore the Process Model

Connect to the running Postgres and investigate:
- How many processes are running?
- Which one is the postmaster?
- Which ones are backend processes?
- How much memory does each use?

### Task 2: Understand MVCC in Action

Create a scenario where:
- One transaction starts and reads data
- Another transaction modifies the same data
- First transaction still sees old data (snapshot isolation)
- Demonstrate non-blocking reads

### Task 3: Background Process Investigation

Identify and explain:
- What is autovacuum doing?
- What is the wal writer doing?
- What is the checkpointer doing?
- When would each become important?

### Task 4: Connection Limits

Test what happens when you exceed connection limits:
- Default `max_connections` is 100
- What happens at connection 101?
- How does connection pooling help?

## Verification

```bash
# Run verification queries
docker exec postgres-arch psql -U postgres -f lab/verify.sql
```

## Expected Outcomes

After completing this lab, you should be able to:
1. Explain PostgreSQL's process-per-connection model
2. Describe how MVCC enables non-blocking reads
3. Identify all background processes and their roles
4. Understand when connection pooling is necessary
5. Recognize the memory implications of many connections
