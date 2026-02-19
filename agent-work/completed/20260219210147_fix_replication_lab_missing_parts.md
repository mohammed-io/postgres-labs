# fix_replication_lab_missing_parts

## Status: completed (20260219211344)

## Context
The lab `07-replication/04-plain-postgres-to-replica-zero-downtime` is missing several critical components:
1. `break-it.sql` has only comments, no executable failure scenarios
2. No replication slots - replicas can break if WAL recycled
3. No failback procedure after promotion
4. No zero-downtime verification script
5. `verify.sql` incomplete - missing replication slots, wal_receiver checks
6. No data consistency verification after cutover
7. No synchronous replication option
8. `benchmark.sql` doesn't test replication lag under load
9. No split-brain prevention guidance
10. No cleanup/reset instructions

## Value Proposition
A complete, production-realistic lab that teaches:
- Proper replication setup with slots
- Failure scenarios and recovery
- True zero-downtime cutover with verification
- Failback procedures
- Data integrity validation

## Alternatives considered (with trade-offs)
1. **Use Patroni/HAProxy** - Too complex for learning fundamentals, adds external dependencies
2. **Use pg_auto_failover** - Good but hides the manual steps we want to teach
3. **Manual approach (chosen)** - More educational, shows all the pieces explicitly

## Todos
- [x] Fix `break-it.sql` - Add executable failure scenarios
  - [x] WAL recycling scenario (low wal_keep_size)
  - [x] Network partition simulation
  - [x] Slot overflow scenario
  - [x] pg_hba.conf misconfiguration
  - [x] Split-brain scenario
  - [x] Query conflicts on replica
  - [x] Disk full simulation
- [x] Add replication slots to solution and steps
- [x] Enhance `verify.sql` with comprehensive checks
  - [x] Check pg_replication_slots
  - [x] Check pg_stat_wal_receiver on replicas
  - [x] Check sync_state
  - [x] Check lag metrics
- [x] Add failback procedure to solution
- [x] Add data consistency check script
- [x] Enhance `benchmark.sql` with replication lag testing
- [x] Add synchronous replication option to step-02
- [x] Enhance step-03 with better content
- [x] Update CLAUDE.md with comprehensive lab requirements
- [x] Enhance step-04 with split-brain prevention and cleanup
- [x] Update problem.md with real-world example

## Acceptance Criteria
- All SQL files are executable (no placeholder comments only)
- Solution includes replication slots
- verify.sql checks all key replication metrics
- Lab can be re-run from scratch with cleanup instructions
- Zero-downtime cutover has measurable verification
- Data integrity verified after promotion

## Notes
Lab directory: learning-materials/07-replication/04-plain-postgres-to-replica-zero-downtime/

