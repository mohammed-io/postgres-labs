-- ============================================================
-- Setup: HOT Updates & Fillfactor Lab
-- Creates a realistic user_sessions table with multiple indexes
-- and 100K rows of representative session data.
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS pageinspect;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Drop if exists for idempotent setup
DROP TABLE IF EXISTS user_sessions CASCADE;

-- Core table: simulates a SaaS session tracking table
-- last_active is updated on every HTTP request (high-churn column)
-- We intentionally do NOT index last_active so HOT is possible
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    last_active TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes: 3 indexes on non-updated columns
-- last_active is deliberately NOT indexed to allow HOT updates
CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(session_token);
CREATE INDEX idx_sessions_status ON user_sessions(status);

-- Seed 100K rows with realistic data
INSERT INTO user_sessions (user_id, session_token, status, last_active, ip_address, user_agent, created_at)
SELECT
    (random() * 50000 + 1)::int AS user_id,
    encode(gen_random_bytes(16), 'hex') AS session_token,
    (ARRAY['active', 'active', 'active', 'idle', 'idle'])[
        (floor(random() * 5) + 1)::int
    ] AS status,
    NOW() - (random() * INTERVAL '30 minutes') AS last_active,
    (
        (10 + (random() * 240))::int || '.' ||
        (random() * 255)::int || '.' ||
        (random() * 255)::int || '.' ||
        (random() * 255)::int
    )::inet AS ip_address,
    (ARRAY[
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Mozilla/5.0 (X11; Linux x86_64)',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)',
        'Mozilla/5.0 (iPad; CPU OS 17_0)'
    ])[(floor(random() * 5) + 1)::int] AS user_agent,
    NOW() - (random() * INTERVAL '7 days') AS created_at
FROM generate_series(1, 100000);

-- Analyze to update planner statistics
ANALYZE user_sessions;

-- Verify setup
SELECT
    'Setup complete' AS status,
    count(*) AS row_count,
    pg_size_pretty(pg_relation_size('user_sessions')) AS table_size,
    (SELECT count(*)
     FROM pg_indexes
     WHERE tablename = 'user_sessions') AS index_count
FROM user_sessions;
