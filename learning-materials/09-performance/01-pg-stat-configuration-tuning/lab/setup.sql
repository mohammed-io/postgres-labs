-- Setup for Performance Tuning lab

-- Enable pg_stat_statements (loaded via shared_preload_libraries)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    price DECIMAL(10,2),
    category TEXT,
    in_stock BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER,
    total DECIMAL(10,2),
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE dashboard_data (
    id SERIAL PRIMARY KEY,
    metric_name TEXT,
    metric_value BIGINT,
    user_id INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert realistic data volumes
INSERT INTO products (name, price, category, in_stock)
SELECT
    'Product ' || i,
    (random() * 100)::decimal(10,2),
    (ARRAY ['Electronics', 'Clothing', 'Home', 'Toys'])[floor(random() * 4 + 1)],
    random() > 0.3
FROM generate_series(1, 100000) AS s(i);

INSERT INTO orders (customer_id, product_id, quantity, total, status)
SELECT
    (random() * 10000 + 1)::int,
    (random() * 100000 + 1)::int,
    (random() * 10 + 1)::int,
    (random() * 1000)::decimal(10,2),
    (ARRAY ['pending', 'shipped', 'delivered'])[floor(random() * 3 + 1)]
FROM generate_series(1, 500000) AS s(i);

INSERT INTO dashboard_data (metric_name, metric_value, user_id)
SELECT
    (ARRAY ['page_views', 'clicks', 'signups', 'purchases'])[floor(random() * 4 + 1)],
    (random() * 100000)::bigint,
    (random() * 10000 + 1)::int
FROM generate_series(1, 1000000) AS s(i);

-- Create some indexes (some missing on purpose for lab)
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_created ON orders(created_at);
-- Missing: idx_orders_product_id (intentionally missing for optimization exercise)

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
