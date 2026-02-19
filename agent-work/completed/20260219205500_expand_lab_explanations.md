# Work: expand_lab_explanations

status: completed (2026-02-19T20:56:07Z)

## Context
The new replication lab has runnable steps, but explanations are too thin. The learner asked for clearer guidance about what each action means and why it matters.

## Value Proposition
Better explanations improve learning outcomes and reduce “copy/paste” execution without understanding.

## Alternatives Considered
- Add long theory in `problem.md` only: simpler but learners still miss context while executing each step.
- Add concise “what/why/how to verify” in each step file: best balance for practical labs.

## Todos
- [x] Expand `problem.md` with clearer phase narrative and outcomes
- [x] Expand `step-01..04.md` with explanation before commands and expected observations
- [x] Add short rationale notes in `verify.sql` and `explore.sql` comments
- [x] Re-read files for consistency and learner clarity

## Acceptance Criteria
- Every step explains intent, expected output, and failure meaning.
- Commands remain minimal and focused.
- Lab still follows plain-primary-to-replica progression.

## Notes
This is content quality improvement only; no architecture change.
