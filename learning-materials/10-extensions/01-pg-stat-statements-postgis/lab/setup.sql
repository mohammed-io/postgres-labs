-- Setup for Extensions lab

-- pg_stat_statements is loaded via shared_preload_libraries
-- PostGIS includes it automatically
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    price DECIMAL(10,2),
    category TEXT
);

CREATE TABLE locations (
    id SERIAL PRIMARY KEY,
    name TEXT,
    geom GEOMETRY(Point, 4326),
    address TEXT
);

CREATE TABLE sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    session_token TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    event_type TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert sample data
INSERT INTO products (name, price, category)
SELECT
    'Product ' || i || ' - ' || (ARRAY ['iPhone', 'Samsung', 'Sony'])[floor(random() * 3 + 1)],
    (random() * 1000)::decimal(10,2),
    (ARRAY ['Electronics', 'Clothing'])[floor(random() * 2 + 1)]
FROM generate_series(1, 10000) AS s(i);

-- Insert some locations (major US cities)
INSERT INTO locations (name, geom, address)
VALUES
    ('San Francisco', ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326), 'Market St'),
    ('New York', ST_SetSRID(ST_MakePoint(-74.0060, 40.7128), 4326), '5th Ave'),
    ('Chicago', ST_SetSRID(ST_MakePoint(-87.6298, 41.8781), 4326), 'Loop St'),
    ('Los Angeles', ST_SetSRID(ST_MakePoint(-118.2437, 34.0522), 4326), 'Downtown'),
    ('Seattle', ST_SetSRID(ST_MakePoint(-122.3321, 47.6062), 4326), 'Pike Place'),
    ('Miami', ST_SetSRID(ST_MakePoint(-80.1918, 25.7617), 4326), 'South Beach'),
    ('Boston', ST_SetSRID(ST_MakePoint(-71.0589, 42.3601), 4326), 'Downtown'),
    ('Denver', ST_SetSRID(ST_MakePoint(-104.9903, 39.7392), 4326), '16th St Mall');

INSERT INTO sessions (user_id, session_token, expires_at)
SELECT
    (random() * 1000)::int,
    md5(random()::text),
    NOW() + INTERVAL '1 hour'
FROM generate_series(1, 100) AS s(i);

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
