# standardize_all_problem_md_files

## Status: completed (2026-02-20)

## Context
The lab problem.md files had significant inconsistencies in structure and content. Only 1 of 13 files (7.7%) was fully compliant with CLAUDE.md requirements.

## Value Proposition
A unified, compliant structure across all labs ensures:
- Consistent learning experience for users
- Clear navigation and progression
- Easy maintenance and scaling
- Professional documentation standards

## Work Completed

All 13 problem.md files have been standardized with:

### Required Sections Added to All Files:
1. **Scenario** - Who, what, why context
2. **Why This Lab Exists** - Lab motivation
3. **Real-World Example** - Production incident/use case with sources
4. **What You Will Build** - Clear phases/outcomes
5. **Quick Start** - How to get environment running
6. **Lab Flow** - Ordered steps with step-*.md references

### Files Fixed:
1. ✅ 01-architecture/01-process-model-and-mvcc/problem.md
2. ✅ 02-storage/01-pages-toast-wal/problem.md
3. ✅ 03-indexing/01-btree-gin-include-indexes/problem.md
4. ✅ 04-query-processing/01-explain-planner-joins/problem.md
5. ✅ 05-caching/01-shared-buffers-os-cache/problem.md
6. ✅ 06-vacuum/01-autovacuum-bloat-visibility-map/problem.md
7. ✅ 07-replication/01-streaming-logical-failover/problem.md
8. ✅ 07-replication/02-version-upgrade-zero-downtime/problem.md
9. ✅ 07-replication/03-read-replicas-failover/problem.md
10. ✅ 07-replication/04-plain-postgres-to-replica-zero-downtime/problem.md (was already compliant)
11. ✅ 08-locking/01-lock-modes-deadlocks-isolation/problem.md
12. ✅ 09-performance/01-pg-stat-configuration-tuning/problem.md
13. ✅ 10-extensions/01-pg-stat-statements-postgis/problem.md

## Verification Results

All 13 files now have all 6 required sections:
- Scenario: 13/13 ✅
- Why This Lab Exists: 13/13 ✅
- Real-World Example: 13/13 ✅
- What You Will Build: 13/13 ✅
- Quick Start: 13/13 ✅
- Lab Flow: 13/13 ✅

## Acceptance Criteria
- [x] All 13 problem.md files have consistent structure
- [x] All required sections present: Scenario, Why This Lab Exists, Real-World Example, What You Will Build, Quick Start, Lab Flow
- [x] Section order is consistent: Scenario → Why This Lab Exists → Real-World Example → What You Will Build → Quick Start → Lab Flow
- [x] No placeholder content - all sections have actual content
- [x] All existing content preserved, only structure added/adjusted
- [x] "Why This Matters" tables kept as supplementary (not main section)

## Notes
- Fixed python3 and ../../../lab-tools/ references in replication labs
- Fixed broken link for Garvit Gupta blog post
- Added proper real-world examples with sources to labs that were missing them
