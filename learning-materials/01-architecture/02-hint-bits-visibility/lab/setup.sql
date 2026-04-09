-- Setup for Hint Bits & Page-Level Visibility lab

CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pg_visibility;

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    inventory INTEGER DEFAULT 100
);

CREATE TABLE audit_log (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    action TEXT NOT NULL,
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Batch 1: Insert orders in explicit transactions
-- Each transaction commits separately, so hint bits are set per-batch
BEGIN;
INSERT INTO orders (customer_id, total, status)
SELECT
    (random() * 5000)::int,
    (random() * 500)::numeric(10,2),
    (ARRAY['pending', 'shipped', 'delivered', 'returned'])[floor(random() * 4 + 1)]
FROM generate_series(1, 10000);
COMMIT;

-- Batch 2: More orders
BEGIN;
INSERT INTO orders (customer_id, total, status)
SELECT
    (random() * 5000)::int,
    (random() * 500)::numeric(10,2),
    (ARRAY['pending', 'shipped', 'delivered', 'returned'])[floor(random() * 4 + 1)]
FROM generate_series(1, 10000);
COMMIT;

-- Batch 3: Products
BEGIN;
INSERT INTO products (name, price, inventory)
SELECT
    'Product-' || i,
    (random() * 100)::numeric(10,2),
    (random() * 1000)::int
FROM generate_series(1, 5000) AS i(i);
COMMIT;

-- Batch 4: Audit entries
BEGIN;
INSERT INTO audit_log (table_name, action, payload)
SELECT
    'orders',
    (ARRAY['INSERT', 'UPDATE', 'DELETE'])[floor(random() * 3 + 1)],
    jsonb_build_object('record_id', (random() * 20000)::int)
FROM generate_series(1, 20000);
COMMIT;

-- Create a table specifically for hint bit observation
-- We'll use this to see hint bits being set on first read
CREATE TABLE hint_bit_demo (
    id SERIAL PRIMARY KEY,
    data TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert in many small transactions so we can observe individual hint bits
-- Each INSERT is its own transaction → each has its own xmin
DO $$
BEGIN
    FOR i IN 1..200 LOOP
        INSERT INTO hint_bit_demo (data)
        VALUES ('row-' || i || '-' || repeat('x', 50));
    END LOOP;
END $$;

-- Create a table for bulk-insert scenario (no hint bits until first read)
CREATE TABLE bulk_insert (
    id SERIAL PRIMARY KEY,
    payload TEXT NOT NULL,
    batch_id INTEGER NOT NULL
);

-- Create a helper view for tuple header inspection
CREATE OR REPLACE VIEW v_tuple_headers AS
SELECT
    t_xmin,
    t_xmax,
    t_infomask,
    t_infomask2,
    CASE WHEN t_infomask & 256 = 256 THEN true ELSE false END AS xmin_committed,
    CASE WHEN t_infomask & 512 = 512 THEN true ELSE false END AS xmin_invalid,
    CASE WHEN t_infomask & 1024 = 1024 THEN true ELSE false END AS xmax_committed,
    CASE WHEN t_infomask & 2048 = 2048 THEN true ELSE false END AS xmax_invalid
FROM generate_series(0, 0) AS g(x);

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
