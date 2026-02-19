CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    owner TEXT NOT NULL,
    balance NUMERIC(12,2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO accounts (owner, balance)
SELECT 'user_' || i, (random()*10000)::numeric(12,2)
FROM generate_series(1, 1000) AS i;

ANALYZE;
