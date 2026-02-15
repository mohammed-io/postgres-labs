# Solution: Extensions

## Real-World Scenarios

### Scenario 1: PostGIS Store Finder

**Requirements**: Find nearest stores to user's location.

```sql
-- Schema
CREATE TABLE stores (
    id SERIAL PRIMARY KEY,
    name TEXT,
    address TEXT,
    geom GEOMETRY(Point, 4326),  -- lon/lat
    open_hours JSONB
);

-- Index for spatial queries
CREATE INDEX idx_stores_geom
ON stores USING GIST (geom);

-- Insert stores
INSERT INTO stores (name, geom, open_hours)
VALUES
    ('Store A', ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326), '{"mon": "9-5"}'::jsonb),
    ('Store B', ST_SetSRID(ST_MakePoint(-122.4080, 37.7850), 4326), '{"mon": "8-6"}'::jsonb);

-- Query: Find nearest stores within 5km
SELECT
    name,
    address,
    ST_Distance(
        geom,
        ST_SetSRID(ST_MakePoint($1, $2), 4326)
    ) / 1000 AS distance_km
FROM stores
WHERE ST_DWithin(
    geom,
    ST_SetSRID(ST_MakePoint($1, $2), 4326),
    5000  -- 5km
)
ORDER BY geom <-> ST_SetSRID(ST_MakePoint($1, $2), 4326)
LIMIT 10;
```

**Real EXPLAIN output**:
```
Index Scan using idx_stores_geom on stores  (cost=0.00..50.23 rows=10 width=112)
  Index Cond: (geom && ST_Expand(ST_SetSRID(ST_MakePoint('-122.4194'::float8, '37.7749'::float8, 4326), 5000))
  Order By: (geom <-> ST_SetSRID(ST_MakePoint('-122.4194'::float8, '37.7749'::float8, 4326))
  Filter: (ST_DWithin(geom, ST_SetSRID(ST_MakePoint('-122.4194'::float8, '37.7749'::float8, 4326), 5000))
```

**Without index**: Full table scan, checking all distances.

### Scenario 2: pg_trgm Fuzzy Search

**Problem**: User searches "iphone" but product is named "iPhone 15 Pro".

```sql
-- Enable pg_trgm
CREATE EXTENSION pg_trgm;

-- Create trigram index
CREATE INDEX idx_products_name_trgm
ON products USING gin (name gin_trgm_ops);

-- Fuzzy search
SELECT name FROM products
WHERE name % 'iphone';  -- Case-insensitive fuzzy match!
```

**Results**:
```
iPhone 15 Pro
iPhone 15
iPhone SE
```

**Without pg_trgm**: Only exact matches with `LIKE '%iphone%'`.

### Scenario 3: pg_cron Scheduled Jobs

```sql
-- Enable pg_cron
CREATE EXTENSION pg_cron;

-- Schedule daily cleanup
SELECT cron.schedule(
    'cleanup-old-sessions',
    '0 2 * * *',  -- 2 AM daily
    $$DELETE FROM sessions WHERE expires_at < NOW()$$
);

-- Schedule hourly metrics
SELECT cron.schedule(
    'update-metrics',
    '0 * * * *',  -- Every hour
    $$INSERT INTO metrics_summary SELECT COUNT(*), NOW() FROM events$$
);

-- View scheduled jobs
SELECT * FROM cron.job_schedule;
```

### Scenario 4: Custom Functions

```sql
-- Function to calculate distance between two zip codes
CREATE OR REPLACE FUNCTION zip_distance(zip1 TEXT, zip2 TEXT)
RETURNS FLOAT AS $$
DECLARE
    p1 GEOMETRY;
    p2 GEOMETRY;
BEGIN
    SELECT geom INTO p1 FROM zip_codes WHERE zip_code = zip1;
    SELECT geom INTO p2 FROM zip_codes WHERE zip_code = zip2;

    RETURN ST_Distance(p1, p2) / 1000;  -- Convert to km
END;
$$ LANGUAGE plpgsql;

-- Usage
SELECT zip_distance('90210', '10001');
```

---

## Extension Management

### List Available Extensions

```sql
SELECT * FROM pg_available_extensions
WHERE name LIKE '%postgis%'
   OR name LIKE '%stat%'
   OR name LIKE '%cron%'
ORDER BY name;
```

### List Installed Extensions

```sql
SELECT * FROM pg_extension
ORDER BY extname;
```

### Remove Extension

```sql
DROP EXTENSION IF EXISTS pg_cron;
```

**Note**: Dropping extension removes all its objects but doesn't drop dependent objects.

---

## Extension Recommendations

| Extension | Use Case | Production Ready |
|-----------|----------|------------------|
| `pg_stat_statements` | Query monitoring | ✅ Essential |
| `PostGIS` | Geospatial data | ✅ Yes |
| `pg_trgm` | Fuzzy search | ✅ Yes |
| `pg_cron` | Scheduled jobs | ⚠️ Test thoroughly |
| `uuid-ossp` | UUID generation | ✅ Yes |
| `btree_gin` | GIN on scalar types | ✅ Yes |
| `pg_buffercache` | Buffer cache stats | ⚠️ Monitoring only |
| `pg_prewarm` | Auto warm cache | ⚠️ Experimental |
