---
name: "pg_stat_statements & PostGIS"
category: "10-extensions"
difficulty: "beginner"
time: "45 minutes"
concepts: ["extensions", "pg_stat_statements", "PostGIS", "custom functions"]
---

# pg_stat_statements & PostGIS

## Learning Objectives

Understand PostgreSQL extensions and how to use them effectively.

## Why This Matters

| Extension | Purpose | Production Use |
|-----------|---------|----------------|
| `pg_stat_statements` | Query performance tracking | Essential for monitoring |
| `PostGIS` | Geospatial data | Location-based apps |
| `pg_cron` | Scheduled jobs | Maintenance tasks |
| `pg_trgm` | Fuzzy text search | Search-as-you-type |
| `uuid-ossp` | UUID generation | Unique identifiers |

## Real World Use

### When This Matters

1. **Query Performance Monitoring**
   - Production database slow
   - Need to identify problematic queries
   - Solution: `pg_stat_statements`

2. **Location-Based Features**
   - "Find stores near me"
   - "Users within delivery radius"
   - Solution: PostGIS with geospatial queries

3. **Automated Maintenance**
   - Clean up old sessions daily
   - Generate reports hourly
   - Solution: `pg_cron`

4. **Autocomplete/Search**
   - Search-as-you-type
   - Fuzzy name matching
   - Solution: `pg_trgm` trigram matching

## Your Tasks

1. Enable and use pg_stat_statements
2. Try PostGIS for geospatial queries
3. Create custom functions
4. Use pg_trgm for fuzzy search

## Quick Start

```bash
cd lab && docker-compose up -d
```
