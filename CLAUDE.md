# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

PostgreSQL Deep Dive Labs is a Streamlit-based interactive learning platform for PostgreSQL internals. Each lab covers a specific PostgreSQL concept (process model, MVCC, indexing, replication, etc.) with hands-on exercises, Docker environments, and verification scripts.

## Commands

```bash
# Install dependencies (uses uv for Python package management)
make install

# Run the Streamlit app
make run

# Clean cache files
make clean
```

The app runs on `http://localhost:8501` by default.

## Architecture

### Application Structure

**`main.py`** - Streamlit application with three core responsibilities:
1. **CoachData** class - Manages persistent state (completed labs, current problem, history) via `.coach-data/` directory
2. **ProblemDetail** class - Represents a single lab with metadata, content, hints, and solution files
3. **UI rendering** - Handles Mermaid diagrams, markdown, lab file downloads, step hints, and solutions

### Learning Materials Structure

```
learning-materials/
├── 01-architecture/       # Process model, MVCC, memory
├── 02-storage/            # Pages, TOAST, WAL
├── 03-indexing/           # B-tree, GIN, INCLUDE indexes
├── 04-query-processing/   # Planner, executor, joins
├── 05-caching/            # shared_buffers, OS cache
├── 06-vacuum/             # Autovacuum, bloat, visibility map
├── 07-replication/        # Streaming, logical, upgrades, failover
├── 08-locking/            # Lock modes, deadlocks, isolation
├── 09-performance/        # pg_stat, tuning
└── 10-extensions/         # pg_stat_statements, PostGIS
```

Each topic contains lab directories with:
- `problem.md` - Lab description with frontmatter metadata (name, difficulty, concepts)
- `step-*.md` - Progressive hints (teaching-focused, not direct answers)
- `solution.md` - Complete reference solution
- `lab/` folder:
  - `setup.sql` - Initial schema and data
  - `verify.sql` - Verification queries
  - `explore.sql` - Discovery queries for learning
  - `benchmark.sql` - Performance measurement
  - `break-it.sql` - Edge cases and failure scenarios
  - `docker-compose.yml` - Isolated Postgres environment

### Lab Tools

**`lab-tools/downtime-monitor.py`** - Monitors database connectivity with millisecond precision. Used in replication/upgrade labs to verify zero-downtime operations. Exits with status codes: 0 (pass), 1 (fail >5s downtime), 2 (warning <5s downtime).

**`lab-tools/traffic-simulator.py`** - Generates synthetic database traffic to simulate load during operations like upgrades or failovers.

## Problem Metadata Format

Each `problem.md` uses YAML frontmatter:

```yaml
---
name: "Human-readable title"
category: "XX-topic-name"      # Maps to directory name
difficulty: "beginner|intermediate|advanced"
time: "XX minutes"
concepts: ["keyword1", "keyword2"]
---
```

The `category` field is critical - it's used for grouping and navigation. Labs are sorted numerically by topic (01, 02, etc.).

## Mermaid Diagrams

Problems and solutions can embed Mermaid diagrams using fenced code blocks. The app extracts these and renders them via CDN-loaded mermaid.esm.min.js. Diagrams are numbered and separated with horizontal rules.

## Persistent State

The `.coach-data/` directory stores:
- `completed.txt` - One line per completed lab ID (relative path from learning-materials/)
- `current_problem.txt` - Currently selected problem ID
- `history.txt` - Last 10 viewed problems (most recent first)

Lab IDs are relative paths like `01-architecture/01-process-model-and-mvcc`.

## Adding New Labs

1. Create directory under appropriate topic: `learning-materials/XX-topic-name/YY-lab-name/`
2. Create `problem.md` with proper frontmatter
3. Create `lab/` directory with SQL files and `docker-compose.yml`
4. Optionally create `step-*.md` hint files and `solution.md`
5. The app auto-discovers all `problem.md` files on startup

## Teaching Philosophy

Labs follow a progression: **problem → explore → practice → verify**. Step files teach concepts incrementally rather than giving answers. The `break-it.sql` files encourage learning through failure (e.g., what happens when you exceed connection limits).
