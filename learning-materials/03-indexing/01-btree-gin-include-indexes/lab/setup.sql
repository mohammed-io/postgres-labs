-- Setup for Indexing lab

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku TEXT,
    name TEXT,
    price DECIMAL(10,2),
    category TEXT,
    in_stock BOOLEAN,
    attributes JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER,
    order_date DATE,
    total_amount DECIMAL(10,2),
    status TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    user_id BIGINT,
    event_type TEXT,
    properties JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS posts (
    id SERIAL PRIMARY KEY,
    title TEXT,
    tags TEXT[],
    content TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert sample data
INSERT INTO products (sku, name, price, category, in_stock, attributes)
SELECT
    'SKU-' || i,
    'Product ' || i,
    (random() * 1000)::decimal(10,2),
    (ARRAY ['Electronics', 'Clothing', 'Home', 'Toys'])[floor(random() * 4 + 1)],
    random() > 0.3,
    jsonb_build_object(
        'brand', (ARRAY ['BrandA', 'BrandB', 'BrandC'])[floor(random() * 3 + 1)],
        'color', (ARRAY ['Red', 'Blue', 'Green'])[floor(random() * 3 + 1)],
        'weight', (random() * 10)::numeric
    )
FROM generate_series(1, 50000) AS s(i)
ON CONFLICT DO NOTHING;

INSERT INTO orders (customer_id, order_date, total_amount, status)
SELECT
    (random() * 5000)::int,
    CURRENT_DATE - (random() * 365)::int,
    (random() * 500)::decimal(10,2),
    (ARRAY ['pending', 'shipped', 'delivered'])[floor(random() * 3 + 1)]
FROM generate_series(1, 50000) AS s(i)
ON CONFLICT DO NOTHING;

INSERT INTO events (user_id, event_type, properties)
SELECT
    (random() * 10000)::bigint,
    (ARRAY ['page_view', 'click', 'signup', 'purchase'])[floor(random() * 4 + 1)],
    jsonb_build_object(
        'page', format('/page/%s', floor(random() * 1000)),
        'referrer', (ARRAY ['google', 'twitter', 'direct'])[floor(random() * 3 + 1)],
        'session_id', md5(random()::text)
    )
FROM generate_series(1, 50000) AS s(i)
ON CONFLICT DO NOTHING;

INSERT INTO posts (title, tags, content)
SELECT
    'Post ' || i,
    ARRAY [
        (ARRAY ['postgres', 'database', 'sql', 'performance'])[floor(random() * 4 + 1)],
        (ARRAY ['tutorial', 'guide', 'tips'])[floor(random() * 3 + 1)]
    ],
    repeat('Content word ', 100)
FROM generate_series(1, 10000) AS s(i)
ON CONFLICT DO NOTHING;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
