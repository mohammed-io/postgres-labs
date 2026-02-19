# Work: fix_lab_integrity_and_instructions

status: completed (2026-02-19T18:57:43Z)

## Context
Several labs are broken or inconsistent: missing lab assets referenced by problem docs, invalid PostgreSQL configuration, wrong service/container references, and incorrect SQL examples.

## Value Proposition
Make every lab runnable and pedagogically valid so learners can focus on solving exercises rather than fighting environment/setup defects.

## Alternatives Considered
- Patch only runtime blockers and leave partial labs: fastest but keeps repo inconsistency.
- Full harmonization with README lab file expectations: slightly more work, better long-term maintainability.

## Todos
- [x] Fix broken docker/runtime config issues (invalid GUC, missing mounted file, interactive replication command)
- [x] Fix incorrect commands and SQL snippets in problem statements
- [x] Add missing lab files for empty/partial labs so referenced commands work
- [x] Validate lab structure consistency and summarize remaining caveats

## Acceptance Criteria
- All problem instructions reference existing services/files/commands.
- No obviously invalid PostgreSQL config options remain.
- Empty lab directories gain runnable starter assets.
- Each lab has baseline expected files per README.

## Notes
Created manually because required helper scripts (`agent-work/bin/work-create.sh`, `work-complete.sh`) are not present in this repository.
