-- Setup for Caching lab

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    sku TEXT,
    name TEXT,
    price DECIMAL(10,2),
    category TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER,
    total DECIMAL(10,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert enough data to see caching effects
INSERT INTO products (sku, name, price, category)
SELECT
    'SKU-' || i,
    'Product ' || i,
    (random() * 100)::decimal(10,2),
    (ARRAY ['A', 'B', 'C'])[floor(random() * 3 + 1)]
FROM generate_series(1, 10000) AS s(i);

INSERT INTO orders (product_id, quantity, total)
SELECT
    (random() * 9999 + 1)::int,
    (random() * 10 + 1)::int,
    (random() * 500)::decimal(10,2)
FROM generate_series(1, 50000) AS s(i);

-- Enable pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
