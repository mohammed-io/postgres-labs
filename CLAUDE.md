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

## Lab Requirements (MANDATORY)

### `problem.md` Requirements

Every `problem.md` MUST include:

1. **Scenario Section** - A realistic context for the problem (who, what, why)
2. **Why This Lab Exists** - Motivation and real-world relevance
3. **Real-World Example** - Concrete example from production scenarios:
   - What actually happened
   - What went wrong (if applicable)
   - What the lab teaches to prevent/solve it
4. **What You Will Build/Learn** - Clear outcomes
5. **Quick Start** - How to get the environment running
6. **Lab Flow** - Ordered list of steps to follow

Example structure:
```markdown
## Scenario
You are a DBA at a fintech company...

## Why This Lab Exists
Most tutorials start with preconfigured servers. Real production doesn't...

## Real-World Example
In 2023, Company X lost 2 hours of data because their replica was 
configured without replication slots. When network lag occurred, 
WAL files were recycled and the replica couldn't catch up...

## What You Will Build
Phase 1: [Primary only]
Phase 2: [Primary] => [Replicas]

## Quick Start
\`\`\`bash
cd lab && docker compose up -d
\`\`\`

## Lab Flow
1. Read `step-01.md`: ...
```

### `lab/` Directory Requirements

Every lab MUST contain these files (no placeholders):

| File | Purpose | Requirements |
|------|---------|--------------|
| `setup.sql` | Initial schema/data | Executable, creates realistic test data |
| `verify.sql` | Verification queries | Multiple sections, checks all key metrics |
| `explore.sql` | Discovery queries | Helps users understand the system state |
| `benchmark.sql` | Performance tests | Measures relevant metrics with timing |
| `break-it.sql` | Failure scenarios | **Executable SQL**, not just comments. Minimum 3 scenarios |
| `docker-compose.yml` | Environment | Isolated containers, proper healthchecks |

### `break-it.sql` Requirements

This file is for learning through controlled failure. It MUST:

1. Contain **executable SQL** (not just comments describing what to do)
2. Include at least **3 distinct failure scenarios**
3. Each scenario should have:
   - Clear description of what breaks
   - SQL to trigger the failure
   - SQL to observe the failure
   - SQL to recover (commented)
   - Expected error messages or symptoms

Example structure:
```sql
-- EXPERIMENT 1: [Title]
-- =====================================
-- What breaks: ...
-- Prerequisites: ...

-- Step 1: Trigger
ALTER SYSTEM SET some_param = 'dangerous_value';

-- Step 2: Observe
SELECT ... FROM pg_stat_...;

-- Expected: Error "..." or symptom "..."

-- Recovery (uncomment to fix):
-- ALTER SYSTEM RESET some_param;
```

### `verify.sql` Requirements

This file validates the lab was completed correctly. It MUST:

1. Be organized into **named sections** using `SELECT 'section_name' AS section;`
2. Check **all key metrics** for the lab's topic
3. Include a **health summary** at the end
4. Work on both primary and replica where applicable
5. Include data consistency checks where relevant

### `solution.md` Requirements

The solution is a reference, not the only path. It MUST:

1. Include **baseline checks** before making changes
2. Explain **why** each step is needed (not just commands)
3. Include **verification steps** after each major change
4. Include **cleanup/reset instructions** for re-running the lab
5. Include **failback procedures** for HA/replication labs
6. Include **data consistency verification** after migrations/failovers
7. Include **troubleshooting table** for common issues

### `step-*.md` Requirements

Step files teach incrementally. They MUST:

1. Have a **clear goal** at the top
2. Include **conceptual explanations** with tables/diagrams
3. Provide **commands to run** with expected output
4. Include **troubleshooting tips** at the end
5. NOT give direct answers (teach the concept, let user apply it)

### Docker Compose Requirements

1. Use **named containers** for clarity (e.g., `pg-primary`, `pg-replica-1`)
2. Include **healthchecks** for all services
3. Use **profiles** for optional services (e.g., replicas)
4. Map **distinct ports** to avoid conflicts (5451, 5452, etc.)
5. Use **named volumes** for persistence
6. Include **init scripts** via `/docker-entrypoint-initdb.d/`

## Teaching Philosophy

Labs follow a progression: **problem → explore → practice → verify**. Step files teach concepts incrementally rather than giving answers. The `break-it.sql` files encourage learning through failure (e.g., what happens when you exceed connection limits).
