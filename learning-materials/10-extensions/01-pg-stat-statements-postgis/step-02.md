# Step 2: PostGIS for Geospatial Queries

## What is PostGIS?

PostGIS adds geospatial data types and functions to PostgreSQL.

**Real-world use cases**:
- "Find all stores within 5 miles"
- "Calculate delivery areas"
- "Check if point is in polygon"
- "Generate isochrone maps"

---

## Investigation

### 1. Enable PostGIS

```sql
docker exec -it postgres-ext psql -U postgres

-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Verify
SELECT PostGIS_Version();
```

### 2. Create Geospatial Table

```sql
CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    name TEXT,
    geom GEOMETRY(Point, 4326),  -- WGS84 (GPS coordinates)
    address TEXT
);

-- Insert locations (longitude, latitude)
INSERT INTO locations (name, geom, address)
VALUES
    ('San Francisco', ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326), 'Market St'),
    ('New York', ST_SetSRID(ST_MakePoint(-74.0060, 40.7128), 4326), '5th Ave'),
    ('Chicago', ST_SetSRID(ST_MakePoint(-87.6298, 41.8781), 4326), 'Loop St');
```

### 3. Geospatial Queries

**Find within radius**:
```sql
-- All locations within 500km of San Francisco
SELECT
    name,
    ST_Distance(
        geom,
        ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)
    ) / 1000 AS distance_km
FROM locations
WHERE ST_DWithin(
    geom,
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326),
    500000  -- 500km in meters
);
```

**Result**:
```
     name      | distance_km
---------------+--------------
 San Francisco |           0
 New York     |     4123.45
```

### 4. Point in Polygon

```sql
-- Create a polygon (delivery zone)
CREATE TABLE delivery_zones (
    id SERIAL PRIMARY KEY,
    zone_name TEXT,
    geom GEOMETRY(Polygon, 4326)
);

INSERT INTO delivery_zones (zone_name, geom)
VALUES (
    'Downtown',
    ST_SetSRID(
        ST_MakePolygon(
            ST_GeomFromText(
                'POLYGON((-122.42 37.78, -122.40 37.78, -122.40 37.80, -122.42 37.80, -122.42 37.78))'
            )
        ),
        4326
    )
);

-- Check if location is in zone
SELECT
    l.name,
    dz.zone_name
FROM locations l
CROSS JOIN delivery_zones dz
WHERE ST_Contains(dz.geom, l.geom);
```

### 5. Real-World Example: Store Finder

```sql
-- User's location (GPS coordinates)
SELECT * FROM locations
WHERE ST_DWithin(
    geom,
    ST_SetSRID(ST_MakePoint($1, $2), 4326),  -- User's lon/lat
    5000  -- 5km radius
)
ORDER BY geom <-> ST_SetSRID(ST_MakePoint($1, $2), 4326)
LIMIT 10;
```

**Explanation**:
- `ST_DWithin` - Within distance check (fast, uses index)
- `<->` - Distance operator (KNN with index)
- Result: 10 nearest stores within 5km

### 6. Create Spatial Index

```sql
-- GIST index for geospatial queries
CREATE INDEX idx_locations_geom
ON locations
USING GIST (geom);

-- Now distance queries are fast!
EXPLAIN ANALYZE
SELECT * FROM locations
WHERE ST_DWithin(
    geom,
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326),
    500000
);
-- Should show Bitmap Index Scan or Index Scan
```

---

## Common PostGIS Operations

| Operation | Function | Use Case |
|-----------|----------|----------|
| Distance | `ST_Distance(geom1, geom2)` | Calculate distance between points |
| Within radius | `ST_DWithin(geom1, geom2, radius)` | Fast "nearby" check |
| Buffer | `ST_Buffer(geom, radius)` | Create area around point |
| Intersection | `ST_Intersects(geom1, geom2)` | Overlap check |
| Contains | `ST_Contains(geom1, geom2)` | Point in polygon |
| Transform | `ST_Transform(geom, new_srid)` | Convert coordinate systems |

See solution.md for more PostGIS examples.
