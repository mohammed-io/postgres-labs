-- ============================================================
-- Setup: MultiXact ID Wraparound Lab
-- ============================================================
-- Creates tables and seed data that naturally produce multixact
-- scenarios when accessed with SELECT FOR SHARE patterns.
-- Uses dblink to simulate concurrent sessions for actual
-- multixact creation (single-transaction FOR SHARE doesn't
-- create multixacts — you need 2+ transactions on the same row).
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS dblink;

-- ============================================================
-- Table 1: inventory — simulates an inventory management table
-- where multiple readers lock rows for consistency checks
-- ============================================================
DROP TABLE IF EXISTS inventory CASCADE;
CREATE TABLE inventory (
    product_id   SERIAL PRIMARY KEY,
    product_name TEXT NOT NULL,
    quantity     INTEGER NOT NULL DEFAULT 0,
    reserved     INTEGER NOT NULL DEFAULT 0,
    unit_price   DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO inventory (product_name, quantity, reserved, unit_price) VALUES
    ('Widget A', 1000, 0, 9.99),
    ('Widget B', 500, 0, 19.99),
    ('Widget C', 250, 0, 29.99),
    ('Gadget X', 750, 0, 49.99),
    ('Gadget Y', 300, 0, 59.99),
    ('Gadget Z', 150, 0, 79.99),
    ('Tool Alpha', 2000, 0, 5.99),
    ('Tool Beta', 1000, 0, 14.99),
    ('Tool Gamma', 800, 0, 24.99),
    ('Component D', 5000, 0, 1.49),
    ('Component E', 3000, 0, 2.99),
    ('Component F', 1500, 0, 3.99),
    ('Assembly G', 400, 0, 99.99),
    ('Assembly H', 200, 0, 149.99),
    ('Assembly I', 100, 0, 199.99),
    ('Part J', 10000, 0, 0.49),
    ('Part K', 8000, 0, 0.99),
    ('Part L', 6000, 0, 1.29),
    ('Material M', 20000, 0, 0.10),
    ('Material N', 15000, 0, 0.25);

-- ============================================================
-- Table 2: order_locks — simulates an order processing table
-- where orders are locked for validation by multiple services
-- ============================================================
DROP TABLE IF EXISTS order_locks CASCADE;
CREATE TABLE order_locks (
    order_id     SERIAL PRIMARY KEY,
    customer_id  INTEGER NOT NULL,
    status       TEXT NOT NULL DEFAULT 'pending',
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    locked_by    TEXT[]
);

INSERT INTO order_locks (customer_id, status, total_amount)
SELECT
    (random() * 10000)::int,
    (ARRAY['pending', 'processing', 'validated', 'shipped'])[floor(random() * 4 + 1)::int],
    (random() * 500 + 10)::decimal(12, 2)
FROM generate_series(1, 100);

-- ============================================================
-- Table 3: shared_resources — simulates a resource reservation
-- system where multiple users lock resources to check availability
-- ============================================================
DROP TABLE IF EXISTS shared_resources CASCADE;
CREATE TABLE shared_resources (
    resource_id  SERIAL PRIMARY KEY,
    resource_name TEXT NOT NULL,
    capacity     INTEGER NOT NULL DEFAULT 1,
    booked       INTEGER NOT NULL DEFAULT 0,
    category     TEXT NOT NULL DEFAULT 'general'
);

INSERT INTO shared_resources (resource_name, capacity, booked, category)
SELECT
    'Resource-' || i,
    (random() * 20 + 1)::int,
    (random() * 5)::int,
    (ARRAY['room', 'vehicle', 'equipment', 'slot'])[floor(random() * 4 + 1)::int]
FROM generate_series(1, 50) AS i;

-- ============================================================
-- Table 4: mxid_stress — table specifically designed to
-- accumulate multixacts rapidly during break-it scenarios
-- ============================================================
DROP TABLE IF EXISTS mxid_stress CASCADE;
CREATE TABLE mxid_stress (
    id    SERIAL PRIMARY KEY,
    data  TEXT NOT NULL DEFAULT md5(random()::text),
    counter INTEGER NOT NULL DEFAULT 0
);

INSERT INTO mxid_stress (data, counter)
SELECT md5(random()::text), 0
FROM generate_series(1, 200);

-- ============================================================
-- Table 5: long_lock_demo — for demonstrating how long-running
-- transactions block multixact freeze
-- ============================================================
DROP TABLE IF EXISTS long_lock_demo CASCADE;
CREATE TABLE long_lock_demo (
    id      SERIAL PRIMARY KEY,
    payload TEXT NOT NULL DEFAULT repeat('x', 100),
    version INTEGER NOT NULL DEFAULT 1
);

INSERT INTO long_lock_demo (payload, version)
SELECT repeat('x', 100), 1
FROM generate_series(1, 50);

-- ============================================================
-- Views for monitoring
-- ============================================================

CREATE OR REPLACE VIEW v_mxid_status AS
SELECT
    datname,
    datminmxid,
    mxid_age(datminmxid) AS mxid_age,
    age(datfrozenxid) AS xid_age,
    ROUND(100.0 * mxid_age(datminmxid) / 2147483648, 6) AS pct_mxid_used,
    ROUND(100.0 * age(datfrozenxid) / 2147483648, 6) AS pct_xid_used,
    CASE
        WHEN mxid_age(datminmxid) > 1500000000 THEN 'MXID EMERGENCY'
        WHEN age(datfrozenxid) > 1500000000 THEN 'XID EMERGENCY'
        WHEN mxid_age(datminmxid) > 150000000 THEN 'MXID CRITICAL'
        WHEN age(datfrozenxid) > 1500000000 THEN 'XID CRITICAL'
        WHEN mxid_age(datminmxid) > 100000000 THEN 'MXID WARNING'
        WHEN age(datfrozenxid) > 1000000000 THEN 'XID WARNING'
        ELSE 'OK'
    END AS status
FROM pg_database
ORDER BY greatest(mxid_age(datminmxid), age(datfrozenxid)) DESC;

CREATE OR REPLACE VIEW v_table_mxid_age AS
SELECT
    n.nspname AS schemaname,
    c.relname,
    c.relminmxid,
    mxid_age(c.relminmxid) AS mxid_age,
    c.relfrozenxid,
    age(c.relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(n.nspname || '.' || c.relname)) AS size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
    AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY mxid_age(c.relminmxid) DESC;

CREATE OR REPLACE VIEW v_multixact_settings AS
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name LIKE '%multixact%'
   OR name LIKE '%freeze%'
ORDER BY name;

-- ============================================================
-- Helper procedure: create real multixacts using dblink
-- ============================================================
-- A multixact is only created when TWO DIFFERENT transactions
-- hold locks on the same row simultaneously. Doing FOR SHARE
-- twice in the same transaction does NOT create a multixact
-- (same XID). This procedure opens a dblink connection to
-- simulate a second session, locks the row from both sessions,
-- then commits both — creating a genuine multixact.
-- ============================================================

CREATE OR REPLACE PROCEDURE create_multixact_batch(
    p_table TEXT,
    p_count INTEGER DEFAULT 100
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_conn TEXT;
    v_row_id INTEGER;
    v_created INTEGER := 0;
BEGIN
    FOR i IN 1..p_count LOOP
        v_conn := 'mxid_batch_' || i;
        v_row_id := ((i - 1) % 200) + 1;

        BEGIN
            PERFORM dblink_connect(v_conn, 'dbname=labdb');
            PERFORM dblink_exec(v_conn, 'BEGIN');

            PERFORM * FROM dblink(v_conn,
                format('SELECT 1 FROM %I WHERE id = %s FOR SHARE', p_table, v_row_id)
            ) AS t(dummy int);

            EXECUTE format('SELECT * FROM %I WHERE id = $1 FOR SHARE', p_table)
            USING v_row_id;

            PERFORM dblink_exec(v_conn, 'COMMIT');
            PERFORM dblink_disconnect(v_conn);

            COMMIT;
            v_created := v_created + 1;
        EXCEPTION WHEN OTHERS THEN
            BEGIN
                PERFORM dblink_disconnect(v_conn);
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
            RAISE NOTICE 'Error at iteration % (row %): %', i, v_row_id, SQLERRM;
        END;
    END LOOP;

    RAISE NOTICE 'Created % multixacts on table %', v_created, p_table;
END;
$$;

-- ============================================================
-- Seed multixact activity using the dblink procedure
-- Creates initial multixacts on inventory rows so the
-- pg_multixact directory has some data to inspect.
-- ============================================================
CALL create_multixact_batch('inventory', 20);

-- ============================================================
-- Verify setup completed
-- ============================================================
\echo 'Setup complete. Verifying...'

SELECT 'Tables created' AS check_point,
       count(*) AS table_count
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('inventory', 'order_locks', 'shared_resources', 'mxid_stress', 'long_lock_demo');

SELECT 'Inventory rows' AS check_point, count(*) AS row_count FROM inventory;
SELECT 'Order locks rows' AS check_point, count(*) AS row_count FROM order_locks;
SELECT 'Shared resources rows' AS check_point, count(*) AS row_count FROM shared_resources;
SELECT 'Stress test rows' AS check_point, count(*) AS row_count FROM mxid_stress;

\echo ''
\echo 'MultiXact baseline:'
SELECT * FROM v_mxid_status WHERE datname = 'labdb';

\echo ''
\echo 'Current multixact counter:'
SELECT next_multixact_id::text::bigint AS next_mxid FROM pg_control_checkpoint();

\echo ''
\echo 'Setup complete. Read step-01.md to begin the lab.'
