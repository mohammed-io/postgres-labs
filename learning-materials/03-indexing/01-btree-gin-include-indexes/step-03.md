# Step 3: GIN Indexes for JSONB/Arrays

## Understanding GIN

**GIN** = Generalized Inverted Index

Unlike B-Tree (one entry per row), GIN stores:
- Each array element → list of rows containing it
- Each JSONB key → list of rows containing it

### Use Cases

| Data Type | GIN Use |
|-----------|---------|
| `array` | `@>` (contains), `&&` (overlap), `=` |
| `jsonb` | `@>`, `?`, `?&`, `?|` (contains operators) |
| `tsvector` | Full-text search `@@` |

---

## Investigation

### 1. JSONB Containment Without GIN

```sql
docker exec -it postgres-index psql -U postgres

-- Create events table with JSONB
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    user_id BIGINT,
    event_type TEXT,
    properties JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert 100K events with JSONB data
INSERT INTO events (user_id, event_type, properties)
SELECT
    (random() * 10000)::bigint,
    (ARRAY ['page_view', 'click', 'signup', 'purchase'])[floor(random() * 4 + 1)],
    jsonb_build_object(
        'page', format('/page/%s', floor(random() * 1000)),
        'referrer', (ARRAY ['google', 'twitter', 'direct'])[floor(random() * 3 + 1)],
        'session_id', md5(random()::text)
    )
FROM generate_series(1, 100000);

ANALYZE events;

-- Slow query: Find events with specific JSONB property
EXPLAIN ANALYZE
SELECT * FROM events
WHERE properties @> '{"page": "/page/500"}';

-- Result: Sequential scan! Slow.
```

### 2. Create GIN Index

```sql
-- GIN index on JSONB column
CREATE INDEX idx_events_properties ON events USING GIN (properties);

ANALYZE events;

-- Now try again
EXPLAIN ANALYZE
SELECT * FROM events
WHERE properties @> '{"page": "/page/500"}';

-- Result: Bitmap Index Scan! Much faster.
```

### 3. GIN Index Size vs. Performance

```sql
-- Check index size
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'events';

-- GIN indexes are LARGE (2-3x data size)
-- But enable fast JSONB queries
```

### 4. Partial GIN (Smaller, Faster)

```sql
-- Only index specific JSONB keys
CREATE INDEX idx_events_properties_page
ON events USING GIN (properties jsonb_path_ops);

-- Or use expression index
CREATE INDEX idx_events_properties_extracted
ON events USING GIN ((properties->>'page') gin_trgm_ops);

-- Smaller index, faster lookups for specific queries
```

### 5. Array Queries with GIN

```sql
-- Table with array column
CREATE TABLE posts (
    id SERIAL PRIMARY KEY,
    title TEXT,
    tags TEXT[]
);

INSERT INTO posts (title, tags)
SELECT
    'Post ' || i,
    ARRAY [
        (ARRAY ['postgres', 'database', 'sql', 'performance'])[floor(random() * 4 + 1)],
        (ARRAY ['tutorial', 'guide', 'tips'])[floor(random() * 3 + 1)]
    ]
FROM generate_series(1, 10000) AS s(i);

-- Without index: Slow array search
EXPLAIN ANALYZE
SELECT * FROM posts WHERE tags @> ARRAY['postgres'];

-- Create GIN index
CREATE INDEX idx_posts_tags ON posts USING GIN (tags);

ANALYZE posts;

-- With index: Fast!
EXPLAIN ANALYZE
SELECT * FROM posts WHERE tags @> ARRAY['postgres'];
```

---

## GIN Options

| Setting | Values | Trade-off |
|---------|--------|-----------|
| `fastupdate` | on/off | On = faster inserts, slower queries |
| `gin_pending_list_limit` | bytes | Larger = less maintenance, more RAM |

```sql
-- Check GIN settings
SHOW gin_pending_list_limit;  -- Default 4MB

-- Create with options
CREATE INDEX idx_events_properties_fast
ON events USING GIN (properties)
WITH (fastupdate = on, gin_pending_list_limit = '16MB');
```

---

## Mini-Challenge

**Query**: Find all events where `properties` contains `{"referrer": "google"}` AND user_id = 123.

**What indexes help?**

<hr>

**Answer**:


```sql
-- Option 1: Two indexes
CREATE INDEX idx_events_user_id ON events(user_id);
CREATE INDEX idx_events_properties ON events USING GIN (properties);

-- Option 2: Combined (but GIN doesn't support multi-column like B-Tree)
-- The user_id filter uses regular index, JSONB uses GIN
-- Postgres will combine with Bitmap AND
```

```sql
EXPLAIN ANALYZE
SELECT * FROM events
WHERE user_id = 123 AND properties @> '{"referrer": "google"}';

-- Should show: Bitmap AND combining both indexes
```
