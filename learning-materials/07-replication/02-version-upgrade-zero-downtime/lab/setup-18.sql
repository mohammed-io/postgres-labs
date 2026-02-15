-- Setup for Postgres 18 (target database)
-- Tables will be created via schema copy from pg-17
-- This is just for initial database setup

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

GRANT USAGE ON SCHEMA public TO postgres;
