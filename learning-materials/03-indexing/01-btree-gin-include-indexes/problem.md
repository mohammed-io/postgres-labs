---
name: "B-Tree, GIN & INCLUDE Indexes"
category: "03-indexing"
difficulty: "intermediate"
time: "90 minutes"
concepts: ["b-tree", "GIN", "index-only scans", "INCLUDE", "index bloat", "partial indexes"]
---

# B-Tree, GIN & INCLUDE Indexes

## Scenario

You're optimizing a real e-commerce database:
- Products table with JSONB attributes
- Orders table with date range queries
- Search queries by multiple columns
- Dashboard queries slow due to heap fetches

Your job is to select the right index types and strategies for optimal query performance.

## Why This Lab Exists

Indexing is one of the most powerful but misunderstood PostgreSQL features. Most developers know that indexes speed up reads, but they don't understand:
- Why `EXPLAIN ANALYZE` shows different execution plans
- When to use INCLUDE vs. regular indexes
- How GIN differs from B-Tree for JSONB
- When to avoid index bloat
- How partial indexes optimize specific workloads

Poor indexing decisions cause:
- Slow queries despite "having indexes"
- Excessive write overhead
- Storage bloat
- Poor scaling to high traffic

## Real-World Example

### 1. Dashboard Query Slow Despite Index

**Problem:** Query `SELECT customer_id, order_date, total FROM orders WHERE customer_id = ? ORDER BY order_date DESC LIMIT 20` is slow despite having an index on `customer_id`.

**Root cause:** EXPLAIN shows `Index Scan` with high `Buffers: shared read`. The index is used for filtering, but Postgres must fetch each row from the heap to get `order_date` and `total`.

**Solution:** `CREATE INDEX idx_orders_customer_inc ON orders(customer_id) INCLUDE (order_date, total)`

**What this teaches:** INCLUDE creates a covering index. The planner chooses `Index-Only Scan`, eliminating heap fetches. This is a massive speedup for queries that filter by one column but need multiple others.

### 2. Array Membership Queries Slow

**Problem:** Query `SELECT * FROM events WHERE tags @> ARRAY['urgent', 'vip']` results in a full table scan, 500ms response time.

**Root cause:** No index on the array column. B-Tree indexes don't support the `@>` (contains) operator efficiently.

**Solution:** `CREATE INDEX idx_events_tags_gin ON events USING GIN (tags)`

**What this teaches:** GIN (Generalized Inverted Index) is designed for arrays, JSONB, and full-text search. It supports containment (`@>`) and overlap (`&&`) operators efficiently.

### 3. Too Many Indexes Slowing Writes

**Problem:** Table has 15 indexes for "every possible query". INSERT takes 500ms due to index maintenance. Write throughput drops to 200/sec.

**Root cause:** Every INSERT, UPDATE, DELETE must update all indexes. If indexes aren't being used, they're purely overhead.

**Solution:** Remove unused indexes, use partial indexes for hot queries, use INCLUDE for covering indexes to reduce index count.

**What this teaches:** Indexes are not free. Every index slows down writes and increases storage. Design indexes based on actual query patterns, not hypothetical ones.

### 4. Index Bloat After Bulk Delete

**Problem:** Deleted old data but table/index size remains the same. Index still contains deleted entries.

**Root cause:** Index pages have free space after deletes. VACUUM doesn't reclaim index pages automatically in all cases.

**Solution:** `REINDEX CONCURRENTLY index_name` (zero downtime) or `VACUUM FULL` (locks table, downtime required).

**What this teaches:** Index bloat reduces performance and wastes storage. Monitoring `pg_stat_user_indexes` with `idx_scan` and `idx_tup_read/idx_tup_fetch` helps identify unused or bloated indexes.

## What You Will Build

```
Phase 1: [B-Tree Internals] - Understand balanced tree structure and query patterns
Phase 2: [INCLUDE Optimization] - Create covering indexes, eliminate heap fetches
Phase 3: [GIN for JSONB] - Optimize array and JSONB containment queries
Phase 4: [Specialized Indexes] - Learn partial indexes, expression indexes, and exclusion constraints
```

## Quick Start

```bash
cd postgres-deep-dive/learning-materials/03-indexing/01-btree-gin-include-indexes/lab
docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: B-Tree Internals - understand balanced tree structure and query patterns
2. Read `step-02.md`: INCLUDE Optimization - create covering indexes, eliminate heap fetches
3. Read `step-03.md`: GIN for JSONB - optimize array and JSONB containment queries
4. Read `step-04.md`: Specialized Indexes - learn partial indexes, expression indexes, exclusion constraints
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - see what happens with various index configurations

## Learning Objectives

After this lab, you will:
1. Understand when the planner chooses index vs. sequential scan
2. Create covering indexes with INCLUDE
3. Use GIN for JSONB/array queries
4. Recognize index bloat and when to reindex
5. Design indexes based on actual query patterns

## Your Tasks

### Task 1: B-Tree Internals

Understand how B-Tree indexes work and when they're used.

### Task 2: INCLUDE for Index-Only Scans

Eliminate heap fetches using INCLUDE.

### Task 3: GIN for JSONB

Optimize JSONB containment queries with GIN.

### Task 4: Partial and Expression Indexes

Create specialized indexes for specific query patterns.

## Getting Started

```bash
cd postgres-deep-dive/learning-materials/03-indexing/01-btree-gin-include-indexes/lab
docker-compose up -d
```

## Verification

```bash
docker exec postgres-index psql -U postgres -f lab/verify.sql
```
