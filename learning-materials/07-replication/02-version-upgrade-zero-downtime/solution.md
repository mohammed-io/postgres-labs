# Solution: Zero-Downtime Upgrade

## Complete Upgrade Process

### Prerequisites

```bash
cd lab
docker-compose up -d

# Terminal 1: Monitor downtime
python3 ../../../lab-tools/downtime-monitor.py "postgres://postgres:postgres@localhost:5433/appdb" &

# Terminal 2: Simulate traffic
python3 ../../../lab-tools/traffic-simulator.py 10 100 300 &
```

### Step-by-Step

#### 1. Enable Logical WAL on pg-17

```sql
ALTER SYSTEM SET wal_level = 'logical';
-- Restart required
docker-compose restart pg-17
```

#### 2. Create Publication

```sql
-- On pg-17
CREATE PUBLICATION upgrade_pub FOR ALL TABLES;
```

#### 3. Initialize pg-18

```bash
# Copy schema
docker exec pg-upgrade-17 pg_dump -U postgres --schema-only appdb | \
docker exec -i pg-upgrade-18 psql -U postgres appdb
```

#### 4. Create Subscription

```sql
-- On pg-18
CREATE SUBSCRIPTION upgrade_sub
CONNECTION 'host=pg-upgrade-17 port=5432 user=postgres dbname=appdb'
PUBLICATION upgrade_pub
WITH (copy_data = true);
```

#### 5. Wait for Catch-up

```sql
-- On pg-18, monitor lag
SELECT EXTRACT(EPOCH FROM (now() - replay_lag))::int AS lag_seconds
FROM pg_stat_subscription;

-- Wait until lag = 0 or 1
```

#### 6. Cutover (Zero Downtime!)

```bash
# ONLY change app's DATABASE_URL
# OLD: postgres://...@pg-17:5432/appdb
# NEW: postgres://...@pg-18:5432/appdb

# No databases stopped!
# Downtime = time for app to reconnect (~0.1 seconds)
```

#### 7. Verify

```sql
-- On pg-18
SELECT count(*) FROM products;  -- Should match pg-17

-- Insert test on pg-18
INSERT INTO products (name, price) VALUES ('Post-Upgrade', 1.00);
-- Works! pg-18 is now the primary
```

#### 8. Decommission pg-17

```sql
-- On pg-18
DROP SUBSCRIPTION upgrade_sub;
```

```bash
docker-compose stop pg-17
```

## Expected Downtime

```
✅ PASS: Zero downtime
```

The downtime monitor should report 0 seconds because:
- pg-17 never stopped
- pg-18 was already running and caught up
- Only change was app's connection string

## Rollback Plan

If something goes wrong:

```bash
# Point app back to pg-17
# Any writes on pg-18 need to be manually synced
```

This is why testing the process is critical!
