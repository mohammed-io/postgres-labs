-- Setup for Storage lab

CREATE TABLE IF NOT EXISTS page_test (
    id SERIAL PRIMARY KEY,
    name TEXT
);

CREATE TABLE IF NOT EXISTS toast_test (
    id SERIAL PRIMARY KEY,
    name TEXT,
    huge_data TEXT,
    json_data JSONB
);

CREATE TABLE IF NOT EXISTS wal_test (
    id SERIAL,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fragmentation_test (
    id SERIAL PRIMARY KEY,
    data TEXT
) WITH (fillfactor = 50);

-- Insert sample data
INSERT INTO page_test (name) VALUES
    ('Alice'), ('Bob'), ('Charlie')
ON CONFLICT DO NOTHING;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
