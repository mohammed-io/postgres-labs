---
name: "pg_stat_statements & PostGIS"
category: "10-extensions"
difficulty: "beginner"
time: "45 minutes"
concepts: ["extensions", "pg_stat_statements", "PostGIS", "custom functions"]
---

# pg_stat_statements & PostGIS

## Scenario

Your team needs to monitor query performance and build a location-based feature. You need to:
1. Enable `pg_stat_statements` to identify slow queries
2. Add geospatial capabilities for "find stores near me" features

Your job is to understand PostgreSQL extensions and how to use them effectively.

## Why This Lab Exists

PostgreSQL's extensibility is its greatest strength. Extensions add powerful capabilities without modifying core code:
- **pg_stat_statements**: Essential for production monitoring
- **PostGIS**: Industry-standard geospatial capabilities
- **pg_trgm**: Fuzzy search for autocomplete
- **pg_cron**: Scheduled maintenance tasks

Many developers don't realize that core functionality in other databases requires extensions in PostgreSQL. Understanding extensions is key to building production-ready applications.

## Real-World Example

### Query Performance Monitoring

**Problem:** Production database slow, but which queries are the culprit?

**Solution:** Enable `pg_stat_statements`

```sql
CREATE EXTENSION pg_stat_statements;

-- Find slowest queries
SELECT query, calls, mean_time, total_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

**What this teaches:** pg_stat_statements is essential for identifying which queries need optimization. Most production databases enable this immediately.

### Location-Based Features

**Problem:** "Find stores near me" - how to query by geographic distance?

**Solution:** PostGIS

```sql
CREATE EXTENSION postgis;

-- Create spatial table
CREATE TABLE stores (
    id SERIAL PRIMARY KEY,
    name TEXT,
    location GEOGRAPHY(POINT, 4326)
);

-- Find stores within 5km
SELECT name, ST_Distance(
    location,
    ST_MakePoint(-122.4194, 37.7749)::geography
) / 1000 AS km_away
FROM stores
WHERE ST_DWithin(location, ST_MakePoint(-122.4194, 37.7749)::geography, 5000);
```

**What this teaches:** PostGIS is the industry standard for geospatial. It supports complex queries like "stores within X km of point Y".

### Autocomplete / Fuzzy Search

**Problem:** Search-as-you-type with typo tolerance.

**Solution:** pg_trgm extension

```sql
CREATE EXTENSION pg_trgm;

CREATE INDEX idx_users_name_trgm ON users USING gin (name gin_trgm_ops);

-- Find "Jonshon" even though it's spelled "Johnson"
SELECT * FROM users WHERE name % 'Jonshon';
```

**What this teaches:** pg_trgm provides trigram similarity. Great for search-as-you-type features.

## What You Will Build

```
Phase 1: [pg_stat_statements] - Enable and use query performance tracking
Phase 2: [PostGIS Basics] - Add geospatial capabilities
Phase 3: [Custom Functions] - Create reusable SQL functions
Phase 4: [pg_trgm] - Implement fuzzy search
```

## Quick Start

```bash
cd lab && docker-compose up -d
```

## Lab Flow

1. Read `step-01.md`: pg_stat_statements - enable and use query performance tracking
2. Read `step-02.md`: PostGIS Basics - add geospatial capabilities
3. Read `step-03.md`: Custom Functions - create reusable SQL functions
4. Read `step-04.md`: pg_trgm - implement fuzzy search
5. Run `lab/verify.sql` throughout to validate your understanding
6. Try `lab/break-it.sql` - explore extension features

## Learning Objectives

Understand PostgreSQL extensions and how to use them effectively.

## Common Extensions

| Extension | Purpose | Production Use |
|-----------|---------|----------------|
| `pg_stat_statements` | Query performance tracking | Essential for monitoring |
| `PostGIS` | Geospatial data | Location-based apps |
| `pg_cron` | Scheduled jobs | Maintenance tasks |
| `pg_trgm` | Fuzzy text search | Search-as-you-type |
| `uuid-ossp` | UUID generation | Unique identifiers |

## Your Tasks

1. Enable and use pg_stat_statements
2. Try PostGIS for geospatial queries
3. Create custom functions
4. Use pg_trgm for fuzzy search
