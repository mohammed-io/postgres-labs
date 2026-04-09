-- ============================================================
-- Benchmark: MultiXact Accumulation Overhead
-- ============================================================
-- Measures the performance impact of shared locking patterns
-- and compares normal operations vs multixact-heavy operations.
-- Uses dblink to create genuine multixacts (requires two
-- concurrent transactions locking the same row).
-- ============================================================

\timing on

\echo ''
\echo '============================================================'
\echo '  Benchmark 1: Baseline — Normal SELECT (No Locking)'
\echo '============================================================'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_count INTEGER;
BEGIN
    v_start := clock_timestamp();

    FOR i IN 1..1000 LOOP
        SELECT count(*) INTO v_count FROM inventory WHERE quantity > 0;
    END LOOP;

    RAISE NOTICE '1000 plain SELECTs: % ms',
        extract(epoch from (clock_timestamp() - v_start)) * 1000;
END $$;

\echo ''
\echo '============================================================'
\echo '  Benchmark 2: SELECT FOR UPDATE (Exclusive Lock)'
\echo '============================================================'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_rec RECORD;
BEGIN
    v_start := clock_timestamp();

    FOR i IN 1..100 LOOP
        FOR v_rec IN SELECT * FROM inventory WHERE product_id <= 5 FOR UPDATE LOOP
            NULL;
        END LOOP;
    END LOOP;

    RAISE NOTICE '100 iterations of SELECT FOR UPDATE (5 rows each): % ms',
        extract(epoch from (clock_timestamp() - v_start)) * 1000;
END $$;

\echo ''
\echo '============================================================'
\echo '  Benchmark 3: SELECT FOR SHARE (Creates Multixacts)'
\echo '============================================================'
\echo 'Uses dblink to create real multixacts (2 concurrent sessions)'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_rec RECORD;
    v_conn TEXT;
    v_mxid_before BIGINT;
    v_mxid_after BIGINT;
    v_created INTEGER := 0;
BEGIN
    v_mxid_before := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());
    v_start := clock_timestamp();

    FOR i IN 1..50 LOOP
        FOR v_rec IN SELECT product_id FROM inventory WHERE product_id <= 5 LOOP
            v_conn := 'bench_mxid_' || i || '_' || v_rec.product_id;
            BEGIN
                PERFORM dblink_connect(v_conn, 'dbname=labdb');
                PERFORM dblink_exec(v_conn, 'BEGIN');

                PERFORM * FROM dblink(v_conn,
                    format('SELECT 1 FROM inventory WHERE product_id = %s FOR SHARE', v_rec.product_id)
                ) AS t(dummy int);

                SELECT * INTO v_rec FROM inventory WHERE product_id = v_rec.product_id FOR SHARE;

                PERFORM dblink_exec(v_conn, 'COMMIT');
                PERFORM dblink_disconnect(v_conn);
                v_created := v_created + 1;
            EXCEPTION WHEN OTHERS THEN
                BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
            END;
        END LOOP;
    END LOOP;

    v_mxid_after := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());

    RAISE NOTICE '50 iterations x 5 rows SELECT FOR SHARE: % ms',
        extract(epoch from (clock_timestamp() - v_start)) * 1000;
    RAISE NOTICE '  MultiXact IDs created: %', v_mxid_after - v_mxid_before;
    RAISE NOTICE '  Successful lock pairs: %', v_created;
END $$;

\echo ''
\echo '============================================================'
\echo '  Benchmark 4: MultiXact Creation Rate (High Volume)'
\echo '============================================================'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_conn TEXT;
    v_mxid_before BIGINT;
    v_mxid_after BIGINT;
    v_created INTEGER := 0;
BEGIN
    v_mxid_before := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());
    v_start := clock_timestamp();

    FOR i IN 1..200 LOOP
        v_conn := 'bench_rate_' || i;
        BEGIN
            PERFORM dblink_connect(v_conn, 'dbname=labdb');
            PERFORM dblink_exec(v_conn, 'BEGIN');

            PERFORM * FROM dblink(v_conn,
                format('SELECT 1 FROM mxid_stress WHERE id = %s FOR SHARE', (i % 200) + 1)
            ) AS t(dummy int);

            PERFORM * FROM mxid_stress WHERE id = (i % 200) + 1 FOR SHARE;

            PERFORM dblink_exec(v_conn, 'COMMIT');
            PERFORM dblink_disconnect(v_conn);
            v_created := v_created + 1;
        EXCEPTION WHEN OTHERS THEN
            BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
        END;
    END LOOP;

    v_mxid_after := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());

    RAISE NOTICE '200 multixact-creating operations: % ms',
        extract(epoch from (clock_timestamp() - v_start)) * 1000;
    RAISE NOTICE '  MultiXact IDs consumed: %', v_mxid_after - v_mxid_before;
    RAISE NOTICE '  Rate: %.1f mxids/sec',
        (v_mxid_after - v_mxid_before) / NULLIF(extract(epoch from (clock_timestamp() - v_start)), 0);
END $$;

\echo ''
\echo '============================================================'
\echo '  Benchmark 5: VACUUM FREEZE Time After Accumulation'
\echo '============================================================'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_mxid_before BIGINT;
    v_mxid_after BIGINT;
BEGIN
    v_mxid_before := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());

    v_start := clock_timestamp();
    VACUUM FREEZE mxid_stress;
    RAISE NOTICE 'VACUUM FREEZE mxid_stress: % ms',
        extract(epoch from (clock_timestamp() - v_start)) * 1000;

    v_start := clock_timestamp();
    VACUUM FREEZE inventory;
    RAISE NOTICE 'VACUUM FREEZE inventory: % ms',
        extract(epoch from (clock_timestamp() - v_start)) * 1000;

    v_mxid_after := (SELECT next_multixact_id::text::bigint FROM pg_control_checkpoint());
    RAISE NOTICE '  mxid before freeze: %', v_mxid_before;
    RAISE NOTICE '  mxid after freeze: %', v_mxid_after;
END $$;

\timing off

\echo ''
\echo '============================================================'
\echo '  Benchmark Summary'
\echo '============================================================'
\echo ''
\echo '  Key findings:'
\echo '  1. Plain SELECTs are fastest (no lock overhead)'
\echo '  2. SELECT FOR UPDATE adds moderate overhead (XID lock only)'
\echo '  3. SELECT FOR SHARE via dblink adds more overhead (multixact creation + extra connection)'
\echo '  4. MultiXact creation rate determines how fast mxid age grows'
\echo '  5. VACUUM FREEZE cost depends on table size and multixact count'
\echo ''
\echo '  Production implication: An application doing SELECT FOR SHARE'
\echo '  on hot rows will accumulate multixacts faster than a workload'
\echo '  using only SELECT FOR UPDATE. Monitor mxid_age closely!'
\echo ''

-- Final state check
SELECT
    'Post-benchmark mxid state' AS label,
    mxid_age(datminmxid) AS mxid_age,
    age(datfrozenxid) AS xid_age
FROM pg_database
WHERE datname = 'labdb';
