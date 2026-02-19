CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    region TEXT NOT NULL
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    amount NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO customers (region)
SELECT (ARRAY['us-east','us-west','eu'])[1 + (random()*2)::int]
FROM generate_series(1, 20000);

INSERT INTO orders (customer_id, amount, created_at)
SELECT
    1 + (random()*19999)::int,
    (random()*500)::numeric(10,2),
    NOW() - ((random()*365)::int || ' days')::interval
FROM generate_series(1, 300000);

ANALYZE;
