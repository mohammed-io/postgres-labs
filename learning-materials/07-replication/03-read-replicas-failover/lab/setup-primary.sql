-- Setup for Primary database

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    price DECIMAL(10,2)
);

CREATE TABLE traffic_metrics (
    sensor_id INTEGER PRIMARY KEY,
    value DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO products (name, price)
SELECT 'Product ' || i, (random() * 100)::decimal(10,2)
FROM generate_series(1, 100);

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO postgres;
