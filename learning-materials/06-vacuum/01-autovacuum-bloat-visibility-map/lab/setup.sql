-- Setup for Vacuum lab

CREATE EXTENSION IF NOT EXISTS pgstattuple;

CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    session_token TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    event_type TEXT,
    properties JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE job_queue (
    id SERIAL PRIMARY KEY,
    job_type TEXT,
    payload JSONB,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

-- Insert data
INSERT INTO user_sessions (user_id, session_token, expires_at)
SELECT
    (random() * 10000)::int,
    md5(random()::text),
    NOW() + INTERVAL '1 hour'
FROM generate_series(1, 100000) AS s(i);

INSERT INTO events (event_type, properties)
SELECT
    (ARRAY ['page_view', 'click', 'signup'])[floor(random() * 3 + 1)],
    jsonb_build_object('user_id', (random() * 10000)::int)
FROM generate_series(1, 50000) AS s(i);

INSERT INTO job_queue (job_type, payload, status)
SELECT
    'process_' || (random() * 100)::int,
    jsonb_build_object('data', repeat('x', 1000)),
    'pending'
FROM generate_series(1, 10000) AS s(i);

-- Create some dead tuples by updating
UPDATE job_queue SET status = 'done' WHERE id % 10 = 0;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
