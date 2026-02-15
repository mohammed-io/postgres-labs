-- Setup for Postgres 17 (source database)

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    category TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    total DECIMAL(10,2),
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert sample data
INSERT INTO products (sku, name, price, category)
SELECT
    'SKU-' || i,
    'Product ' || i,
    (random() * 100)::decimal(10,2),
    (ARRAY ['Electronics', 'Clothing', 'Home'])[floor(random() * 3 + 1)]
FROM generate_series(1, 1000) AS s(i)
ON CONFLICT (sku) DO NOTHING;

INSERT INTO users (email, name)
SELECT
    'user' || i || '@example.com',
    'User ' || i
FROM generate_series(1, 100) AS s(i)
ON CONFLICT (email) DO NOTHING;

INSERT INTO orders (user_id, product_id, quantity, total, status)
SELECT
    (random() * 99 + 1)::int,
    (random() * 999 + 1)::int,
    (random() * 5 + 1)::int,
    (random() * 500)::decimal(10,2),
    (ARRAY ['pending', 'shipped', 'delivered'])[floor(random() * 3 + 1)]
FROM generate_series(1, 5000) AS s(i);

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO postgres;
