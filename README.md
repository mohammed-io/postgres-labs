# 🐘 PostgreSQL Deep Dive Labs

Hands-on, production-oriented PostgreSQL learning labs.

## Structure

```
postgres-deep-dive/
├── main.py                    # Streamlit app
├── learning-materials/
│   ├── 01-architecture/       # Process model, memory, MVCC
│   ├── 02-storage/            # Pages, TOAST, WAL
│   ├── 03-indexing/           # B-tree, GIN, INCLUDE
│   ├── 04-query-processing/   # Planner, executor
│   ├── 05-caching/            # shared_buffers
│   ├── 06-vacuum/             # Autovacuum, bloat
│   ├── 07-replication/        # Streaming, logical, upgrades
│   ├── 08-locking/            # Lock modes, isolation
│   ├── 09-performance/        # Tuning, pg_stat
│   └── 10-extensions/         # pg_stat_statements
└── lab-tools/                 # Shared monitoring tools
```

## Usage

```bash
make install
make run
```

## Each Lab Includes

- `problem.md` - The challenge
- `step-*.md` - Guided hints (teaching, not answers)
- `solution.md` - Complete reference
- `lab/` folder:
  - `setup.sql` - Initial schema/data
  - `verify.sql` - Check your work
  - `explore.sql` - Discover concepts
  - `benchmark.sql` - Measure performance
  - `break-it.sql` - Learn from failures
  - `docker-compose.yml` - Postgres environment
