-- Index Bloat from MVCC Lab Setup
-- Creates a table with 5 B-tree indexes and 500K rows

CREATE EXTENSION IF NOT EXISTS pgstattuple;

CREATE TABLE dashboard_metrics (
    id SERIAL PRIMARY KEY,
    metric_name TEXT NOT NULL,
    metric_value NUMERIC(12, 4) NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    source TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    tags JSONB DEFAULT '{}'
);

CREATE INDEX idx_dashboard_metric_name ON dashboard_metrics (metric_name);
CREATE INDEX idx_dashboard_status ON dashboard_metrics (status);
CREATE INDEX idx_dashboard_source ON dashboard_metrics (source, recorded_at);
CREATE INDEX idx_dashboard_recorded_at ON dashboard_metrics (recorded_at);
CREATE INDEX idx_dashboard_value ON dashboard_metrics (metric_value);

INSERT INTO dashboard_metrics (metric_name, metric_value, status, source, recorded_at, tags)
SELECT
    (ARRAY[
        'cpu_usage', 'memory_usage', 'disk_io', 'network_in', 'network_out',
        'request_count', 'error_rate', 'latency_p50', 'latency_p99', 'throughput'
    ])[floor(random() * 10 + 1)::int],
    round((random() * 100)::numeric, 4),
    (ARRAY['active', 'active', 'active', 'warning', 'critical'])[floor(random() * 5 + 1)::int],
    (ARRAY['prod-api-01', 'prod-api-02', 'prod-api-03', 'prod-worker-01', 'prod-db-01'])[floor(random() * 5 + 1)::int],
    NOW() - (random() * INTERVAL '90 days'),
    jsonb_build_object(
        'region', (ARRAY['us-east-1', 'us-west-2', 'eu-west-1'])[floor(random() * 3 + 1)::int],
        'env', 'production'
    )
FROM generate_series(1, 500000) AS s(i);

ANALYZE dashboard_metrics;
