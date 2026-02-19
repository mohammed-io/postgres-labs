-- Baseline app schema (plain primary start)
CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    owner TEXT NOT NULL,
    balance NUMERIC(12,2) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE ledger (
    id BIGSERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    amount NUMERIC(12,2) NOT NULL,
    kind TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO accounts (owner, balance)
SELECT 'user_' || i, (random() * 10000)::numeric(12,2)
FROM generate_series(1, 1000) AS s(i);

INSERT INTO ledger (account_id, amount, kind)
SELECT
    (floor(random() * 1000) + 1)::int,
    (random() * 500)::numeric(12,2),
    CASE WHEN random() > 0.5 THEN 'credit' ELSE 'debit' END
FROM generate_series(1, 5000);

ANALYZE;
