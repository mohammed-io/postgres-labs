-- Setup for Locking lab

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    stock INTEGER DEFAULT 0,
    price DECIMAL(10,2)
);

CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    owner TEXT,
    balance DECIMAL(10,2) DEFAULT 0
);

CREATE TABLE job_queue (
    id SERIAL PRIMARY KEY,
    job_type TEXT,
    payload JSONB,
    status TEXT DEFAULT 'pending',
    worker_id INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ
);

-- Insert sample data
INSERT INTO products (name, stock, price)
SELECT
    'Product ' || i,
    (random() * 100)::int,
    (random() * 1000)::decimal(10,2)
FROM generate_series(1, 100) AS s(i);

INSERT INTO accounts (owner, balance)
SELECT
    'User ' || i,
    1000.00
FROM generate_series(1, 10) AS s(i);

INSERT INTO job_queue (job_type, payload)
SELECT
    'job_type_' || (random() * 5)::int,
    jsonb_build_object('data', repeat('x', 100))
FROM generate_series(1, 50) AS s(i);

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
