# Work: add_plain_to_replica_zero_downtime_lab

status: completed (2026-02-19T20:46:14Z)

## Context
Current replication labs are mostly preconfigured. User needs a pedagogical lab that starts from a plain/default PostgreSQL setup and incrementally transforms it into replication-ready architecture, then practices zero-downtime transition concepts.

## Value Proposition
Learners understand not only replication operations, but also the foundational configuration journey and why each change is required.

## Alternatives Considered
- Modify existing replication lab in-place: risks breaking current workflow and expectations.
- Add a new standalone lab: preserves existing labs and adds progressive learning path.

## Todos
- [x] Create new lab directory and problem content (problem, steps, solution)
- [x] Create runnable lab environment files (compose, setup, verify, explore, benchmark, break-it)
- [x] Validate discovery and structure consistency for new lab

## Acceptance Criteria
- New lab appears under replication section with complete teaching flow.
- Lab starts from plain primary and guides conversion to replication-ready.
- Lab includes zero-downtime cutover/failover exercises and verification assets.

## Notes
Keep this lab additive; do not remove or rewrite existing replication labs.
