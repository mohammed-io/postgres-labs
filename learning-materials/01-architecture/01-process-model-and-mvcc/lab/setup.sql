-- Setup script for Process Model & MVCC lab

-- Create demo tables
CREATE TABLE IF NOT EXISTS mvcc_demo (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    balance DECIMAL(10,2) DEFAULT 0.00
);

CREATE TABLE IF NOT EXISTS traffic_metrics (
    sensor_id INTEGER PRIMARY KEY,
    value DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert sample data
INSERT INTO mvcc_demo (name, balance) VALUES
    ('Alice', 1000.00),
    ('Bob', 500.00),
    ('Charlie', 250.00)
ON CONFLICT DO NOTHING;

-- Create view for process monitoring
CREATE OR REPLACE VIEW v_processes AS
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    state_change,
    query_start,
    backend_type,
    query
FROM pg_stat_activity;

-- Grant necessary permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO postgres;
