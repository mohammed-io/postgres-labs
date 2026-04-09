# Step 1: What Are MultiXact IDs?

## Goal

Understand what multixact IDs are, why they exist, when they're created, and how they differ from regular transaction IDs.

## The Problem MultiXacts Solve

Consider this scenario:

```
Transaction A: SELECT * FROM orders WHERE id = 42 FOR SHARE;
Transaction B: SELECT * FROM orders WHERE id = 42 FOR SHARE;
```

Both transactions hold a **shared lock** on the same row. They both need to record "I'm locking this row." But a row's `xmax` field can only hold a single transaction ID. How do you represent *two* (or more) lock holders?

**Answer**: MultiXact IDs. A multixact (mxid) is a 32-bit number that maps to a *set* of regular transaction IDs. When multiple transactions lock the same row, PostgreSQL creates a single mxid that references all of them.

### Why Not Just Store a List of XIDs in the Row?

PostgreSQL's heap tuple header (`HeapTupleHeaderData`) has a fixed-size `t_xmax` field (4 bytes). There's no room for a variable-length list. The solution: store a single 32-bit mxid in `xmax`, and maintain a separate on-disk structure (`pg_multixact/`) that maps each mxid to its member XIDs.

### How It Works

```
Row header:  xmin = 1000,  xmax = 5 (mxid)
                                        ↓
pg_multixact/members:  mxid 5 -> [XID 1001, XID 1002, XID 1003]
pg_multixact/offsets:  mxid 5 -> offset into members file

Three transactions (1001, 1002, 1003) all hold locks on this row.
The row's xmax stores mxid 5 instead of a single XID.
```

---

## When Are MultiXacts Created?

MultiXacts are created whenever **more than one transaction** locks the same row simultaneously. This happens with:

| Lock Type | SQL | Creates Multixact? |
|-----------|-----|--------------------|
| `FOR SHARE` | `SELECT ... FOR SHARE` | Yes, when 2+ transactions lock same row |
| `FOR KEY SHARE` | `SELECT ... FOR KEY SHARE` | Yes, when 2+ transactions lock same row |
| `FOR NO KEY UPDATE` | `SELECT ... FOR NO KEY UPDATE` | Yes, with concurrent key-share locks |
| `FOR UPDATE` | `SELECT ... FOR UPDATE` | Yes, when another tx holds a share lock |

**Key insight**: A single transaction doing `SELECT FOR SHARE` creates a regular XID lock, *not* a multixact. The multixact is only created when a *second* transaction also locks the same row while the first lock is still held.

### No Multixact Created
```sql
-- Session 1 (only one locker):
BEGIN;
SELECT * FROM orders WHERE id = 42 FOR SHARE;
-- xmax = 1001 (regular XID, no multixact)
COMMIT;
```

### Multixact Created
```sql
-- Session 1:
BEGIN;
SELECT * FROM orders WHERE id = 42 FOR SHARE;
-- xmax = 1001 (regular XID for now)

-- Session 2 (while Session 1 is still open):
BEGIN;
SELECT * FROM orders WHERE id = 42 FOR SHARE;
-- xmax = mxid 1 (now a multixact: maps to [1001, 1002])
COMMIT;

-- Session 1:
COMMIT;
```

---

## On-Disk Storage

MultiXact data lives in the `pg_multixact/` directory inside your data directory:

```
$PGDATA/
  pg_multixact/
    members    — Maps each mxid to its member XIDs
    offsets    — Maps each mxid to its offset in the members file
```

As multixacts accumulate, these files grow. Unlike regular XIDs (which are stored directly in tuple headers), multixact data requires additional I/O to resolve. This is why multixact-heavy workloads can be slower than expected — every row lock check may require a lookup in `pg_multixact/members`.

---

## Your Investigation

### 1. Check Current MultiXact State

```sql
-- Current multixact ID counter
SELECT next_multixact_id::text::bigint AS next_mxid FROM pg_control_checkpoint();

-- Or use the function directly:
SELECT mxid_age(datminmxid) AS oldest_mxid_age,
       datminmxid AS min_mxid,
       datname
FROM pg_database;
```

### 2. Create a MultiXact

Open **two** psql sessions against the lab database:

```sql
-- Session 1:
BEGIN;
SELECT * FROM inventory WHERE product_id = 1 FOR SHARE;
-- Don't commit yet!

-- Session 2 (new terminal):
BEGIN;
SELECT * FROM inventory WHERE product_id = 1 FOR SHARE;
COMMIT;

-- Session 1:
-- Now check what happened to the row:
SELECT lp, t_xmin, t_xmax, t_infomask, t_infomask2
FROM heap_page_items(get_raw_page('inventory', 0))
WHERE lp = 1;
COMMIT;
```

### 3. Observe the infomask Flags

When a row has a multixact in `xmax`, these infomask bits are set:

| Flag | Meaning |
|------|---------|
| `HEAP_XMAX_IS_MULTI` (0x1000) | xmax contains a multixact ID, not a regular XID |
| `HEAP_XMAX_SHARED_LOCK` (0x0400) | The lock is a shared lock (FOR SHARE) |
| `HEAP_XMAX_EXCL_LOCK` (0x0800) | The lock is an exclusive lock (FOR UPDATE) |
| `HEAP_XMAX_KEYSHR_LOCK` (0x0200) | The lock is a key-share lock (FOR KEY SHARE) |

### 4. Check pg_multixact Directory Size

```bash
docker exec pg-multixact bash -c "du -sh /var/lib/postgresql/data/pg_multixact/"
```

Before creating multixacts, this will be small. After running `break-it.sql`, come back and check again.

---

## Think About It

1. **Why do multixacts exist instead of storing lock lists in the row?**
   - Fixed-size tuple headers prevent variable-length lock lists
   - The indirection through `pg_multixact/` allows unlimited lock holders per row
   - Trade-off: extra I/O to resolve lock membership, but keeps tuple headers compact

2. **Why is multixact wraparound more dangerous than XID wraparound?**
   - It's less known → less monitored → catches teams by surprise
   - The same 32-bit limit applies but the counter increments per *shared-lock event*, not per transaction
   - A single row locked by 50 transactions creates 1 multixact, but rapid churn on hot rows can burn through mxids fast
   - Recovery is the same painful single-user mode process

3. **Does your application create multixacts?**
   - Check for `SELECT FOR SHARE` / `SELECT FOR KEY SHARE` in query logs
   - ORM frameworks may generate these implicitly (Hibernate's `PESSIMISTIC_READ`)
   - Reporting queries that lock rows for consistency are common culprits

---

## Mini-Challenge

**Predict then verify**: If you run `SELECT FOR SHARE` on the same row from 5 concurrent sessions (without committing any), how many multixacts are created?

Hint: It's not 5. The first session creates a regular XID lock. The second session's lock converts the row's xmax to a multixact with 2 members. Each additional session adds a member to the *same* multixact. Only 1 multixact ID is created — but it maps to 5 member XIDs.

```sql
-- Verify by checking the member count:
-- (Requires the pageinspect extension)
SELECT t_xmax AS mxid,
       pg_get_multixact_members(t_xmax) AS members
FROM heap_page_items(get_raw_page('inventory', 0))
WHERE t_infomask & 4096 != 0;  -- HEAP_XMAX_IS_MULTI
```

<hr>

**Answer**: Only **1** multixact is created, with **5** member XIDs. Multixacts are per-row, not per-locker. A new mxid is created only when the row's lock state changes (new locker added, old locker removed).
