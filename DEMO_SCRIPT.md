# Presentation Demo Script
## Enterprise Data Platform — Loan Management System
### Run in order. Say the lines in quotes out loud.

---

## SETUP BEFORE PRESENTING

Open **3 terminal windows** side by side and `cd` into the project in each:
```bash
cd /home/moses/Documents/DistributedDB/enterprise-data-system
```

Also open in browser:
- `http://localhost:5050` — pgAdmin
- `http://localhost:3000` — Metabase

---

## PART 1 — Show Everything is Running

**Run in Terminal 1:**
```bash
docker compose --env-file .env ps
```

**What you will see:** 9 services — all `Up` or `healthy`

**Say:**
> "This is the full platform running in Docker. We have a primary PostgreSQL database, two read replicas, a separate data warehouse, an ETL pipeline, Metabase for dashboards, pgAdmin for administration, and PgBouncer for connection pooling — all 9 services coordinated by Docker Compose."

---

## PART 2 — Show the OLTP Database (Operational Data)

**Run:**
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db \
  -c "SELECT customer_id, full_name, segment, city FROM operational.customers LIMIT 5;"
```

**Then run:**
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db \
  -c "SELECT loan_id, customer_id, amount, interest_rate, status, outstanding_balance FROM operational.loans LIMIT 5;"
```

**Then run:**
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db \
  -c "SELECT payment_id, loan_id, amount, payment_method, payment_date FROM operational.payments LIMIT 5;"
```

**Say:**
> "This is our OLTP database — the live operational system for a Loan Management company. It has 15 customers, 15 loans, and 50 payments. This is where all writes happen — new loans, new payments, status changes. The schema is fully normalised with foreign key constraints, audit triggers, and role-based access control."

---

## PART 3 — Show the Audit Trail (Trigger)

**Run:**
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db \
  -c "SELECT table_name, operation, record_id, old_values, new_values, change_time FROM operational.audit_log LIMIT 3;"
```

**Say:**
> "Every change to a loan is automatically captured in the audit log by a PostgreSQL trigger. The trigger records both the old values and new values as JSON. This is a compliance and forensic requirement in financial systems — you can see exactly what changed, when, and trace it back to the original transaction."

---

## PART 4 — Streaming Replication

**Run:**
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db \
  -c "SELECT client_addr, state, sent_lsn, replay_lsn, sent_lsn = replay_lsn AS zero_lag FROM pg_stat_replication;"
```

**What you will see:** 2 rows — `172.20.0.11` and `172.20.0.12`, both with state `streaming`, `zero_lag = true`

**Say:**
> "The primary database is streaming its Write-Ahead Log to two replicas in real time. The LSN — Log Sequence Number — is identical on both sides, meaning zero replication lag. Every INSERT, UPDATE, and DELETE on the primary is immediately replayed on both replicas."

---

**Run:**
```bash
docker exec eds_postgres_replica1 psql -U postgres -d loans_db \
  -c "SELECT pg_is_in_recovery() AS is_replica;"
```

**What you will see:** `t` (true)

**Say:**
> "This confirms Replica 1 is running in standby/recovery mode — it is physically receiving and replaying WAL from the primary."

---

**Run:**
```bash
docker exec eds_postgres_replica1 psql -U postgres -d loans_db \
  -c "SELECT customer_id, full_name FROM operational.customers LIMIT 3;"
```

**Say:**
> "Reads work fine on the replica — this is the main purpose, offloading read traffic from the primary."

---

**Now prove it is read-only:**
```bash
docker exec eds_postgres_replica1 psql -U postgres -d loans_db \
  -c "INSERT INTO operational.customers (full_name, email, segment) VALUES ('Hacker', 'h@h.com', 'retail');"
```

**What you will see:**
```
ERROR:  cannot execute INSERT in a read-only transaction
```

**Say:**
> "PostgreSQL enforces read-only at the engine level on standbys. No application misconfiguration can corrupt a replica with accidental writes."

---

## PART 5 — Data Warehouse (Star Schema / Constellation Schema)

**Run:**
```bash
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db \
  -c "SELECT 'dim_customer' AS table_name, COUNT(*) FROM warehouse.dim_customer
      UNION ALL SELECT 'dim_loan',          COUNT(*) FROM warehouse.dim_loan
      UNION ALL SELECT 'dim_date',          COUNT(*) FROM warehouse.dim_date
      UNION ALL SELECT 'dim_payment_method',COUNT(*) FROM warehouse.dim_payment_method
      UNION ALL SELECT 'fact_payments',     COUNT(*) FROM warehouse.fact_payments
      UNION ALL SELECT 'fact_loans',        COUNT(*) FROM warehouse.fact_loans;"
```

**Say:**
> "This is our data warehouse running on a completely separate PostgreSQL instance. It uses a constellation schema — two fact tables sharing conformed dimension tables. fact_payments has one row per payment transaction. fact_loans has one row per loan for portfolio-level analysis. The dim_date table is pre-populated with over 12,000 dates from 2018 to 2050 for fast time-based joins."

---

**Run an analytical query:**
```bash
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db \
  -c "SELECT year, month_name, total_revenue, payment_count FROM warehouse.vw_monthly_revenue ORDER BY year, month;"
```

**Say:**
> "This view aggregates payment data by month. On the operational database this query would require a full table scan and slow down live transactions. In the warehouse it is pre-modelled for this exact type of analysis — this is why we separate OLTP and OLAP."

---

**Run:**
```bash
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db \
  -c "SELECT full_name, segment, total_paid, payment_count FROM warehouse.vw_top_customers ORDER BY total_paid DESC LIMIT 5;"
```

**Say:**
> "Top customers by total payments — another OLAP query that would be expensive on the operational system but is fast in the warehouse."

---

## PART 6 — ETL Pipeline

**Run:**
```bash
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db \
  -c "SELECT run_id, run_started_at, run_finished_at, rows_inserted, rows_updated, status FROM audit.etl_runs ORDER BY run_id DESC LIMIT 5;"
```

**Say:**
> "The ETL pipeline runs automatically every 15 minutes via cron inside its Docker container. Each run is logged in the audit schema — we can see when it ran, how long it took, how many rows were inserted or updated, and whether it succeeded. The ETL uses the dblink PostgreSQL extension to query the primary database across the Docker network, then stages the data, transforms it into the dimensional model, and loads it into the warehouse — all inside a single transaction."

---

**Show ETL is running live:**
```bash
docker logs eds_etl_pipeline 2>&1 | tail -20
```

**Say:**
> "The ETL container is actively running — you can see the cron daemon and the log output from the most recent run."

---

## PART 7 — Concurrency Control (Open 2 terminals)

> **Show this in Terminal 1 and Terminal 2 side by side.**

### Demo A: Non-Repeatable Read (READ COMMITTED)

**Terminal 1:**
```bash
docker exec -it eds_postgres_primary psql -U postgres -d loans_db
```
```sql
BEGIN;
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- You see: 95000.00  (or current value)
-- DO NOT TYPE COMMIT YET
```

**Terminal 2 (while Terminal 1 is still open):**
```bash
docker exec -it eds_postgres_primary psql -U postgres -d loans_db
```
```sql
BEGIN;
UPDATE operational.loans SET outstanding_balance = outstanding_balance - 5000 WHERE loan_id = 1;
COMMIT;
```

**Terminal 1 (run again):**
```sql
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- You now see: 90000.00  ← DIFFERENT from first read!
COMMIT;
```

**Say:**
> "Same transaction, same query, two different results. This is a non-repeatable read — the default READ COMMITTED isolation level allows a transaction to see other committed changes mid-flight. In a payment system this could cause calculation errors."

---

### Demo B: REPEATABLE READ (snapshot protection)

**Terminal 1:**
```sql
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 3;
-- Note the value — e.g. 380000.00
-- DO NOT COMMIT
```

**Terminal 2:**
```sql
BEGIN;
UPDATE operational.loans SET outstanding_balance = outstanding_balance - 5000 WHERE loan_id = 3;
COMMIT;
```

**Terminal 1:**
```sql
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 3;
-- STILL shows 380000.00 — B's change is invisible
COMMIT;
```

**Say:**
> "With REPEATABLE READ, PostgreSQL gives this transaction a frozen snapshot of the database at the moment BEGIN was executed. Even though Terminal 2 committed a real change, Terminal 1 is completely protected from seeing it. This is powered by PostgreSQL's MVCC — Multi-Version Concurrency Control — where multiple versions of the same row exist simultaneously."

---

### Demo C: Row Locking (blocking)

**Terminal 1:**
```sql
BEGIN;
SELECT * FROM operational.loans WHERE loan_id = 1 FOR UPDATE;
-- Terminal 1 now HOLDS the row lock. Do not commit.
```

**Terminal 2:**
```sql
BEGIN;
SELECT * FROM operational.loans WHERE loan_id = 1 FOR UPDATE;
-- THIS HANGS — Terminal 2 is blocked waiting for Terminal 1
```

**Show the lecturer that Terminal 2 is frozen/waiting.**

**Terminal 1:**
```sql
COMMIT;
-- The moment you hit enter here, Terminal 2 will unblock
```

**Say:**
> "FOR UPDATE acquires an exclusive row-level lock. Terminal 2 is completely blocked — it cannot proceed until Terminal 1 releases the lock. This is how a banking system ensures that when two payment requests arrive for the same loan simultaneously, they are processed one at a time — never overlapping and never corrupting the balance."

---

## PART 8 — Backup

**Run:**
```bash
bash backups/backup.sh health
```

**Say:**
> "The backup script can run health checks, take logical backups with pg_dump, check WAL archive status, and verify replication lag. For disaster recovery we have two layers: logical backups via pg_dump which export the full schema and data as SQL, and continuous WAL archiving which enables Point-In-Time Recovery — restoring the database to any exact second in history."

---

## PART 9 — pgAdmin (switch to browser)

Open: `http://localhost:5050`

Login: `admin@enterprise.com` / `PgAdmin@Secure2025!`

**Show:**
1. Click **Primary OLTP** → enter password `StrongPrimary@2025!` → expand to show tables
2. Right-click `loans_db` → **Query Tool** → run:
   ```sql
   SELECT * FROM operational.vw_customer_payment_summary LIMIT 5;
   ```
3. Click **Data Warehouse** → password `Warehouse@Secure2025!` → show warehouse tables

**Say:**
> "pgAdmin gives us a full web-based administration interface. We can browse every table, run queries, see execution plans, and monitor pg_stat_replication to watch replication lag in real time. All 5 servers — primary, two replicas, warehouse, and pgBouncer — are pre-configured and available."

---

## PART 10 — Metabase (switch to browser)

Open: `http://localhost:3000`

**Show:**
1. Click **Databases** (left panel) → confirm warehouse_db is listed
2. Click **New** → **Question** → pick `warehouse_db` → pick `fact_payments`
3. Click **Summarize** → pick `Sum of payment_amount` → Group by `customer_segment`
4. Click **Visualize** → switch to **Bar chart**

**Say:**
> "Metabase is our OLAP dashboard tool. Business analysts can build charts and reports without writing SQL. It connects directly to the warehouse database — not the operational one — so analytical queries never affect live transaction performance. This separation between OLTP and OLAP is the core architectural principle of the entire platform."

---

## CLOSING STATEMENT

**Say:**
> "To summarise — we built a full enterprise data platform with six distinct capabilities:
> One: A normalised OLTP database handling live loan transactions with ACID guarantees.
> Two: Streaming replication delivering real-time copies to two read-only standbys for high availability.
> Three: A constellation schema data warehouse separated from the operational system.
> Four: An automated ETL pipeline that incrementally loads data from the primary to the warehouse every 15 minutes.
> Five: Concurrency control demonstrated across three isolation levels — READ COMMITTED, REPEATABLE READ, and explicit row locking.
> Six: Backup and recovery via pg_dump and continuous WAL archiving for Point-In-Time Recovery.
> All of this runs in Docker containers on a single Linux machine, coordinated by Docker Compose."

---

## QUICK CREDENTIAL REFERENCE

| What | URL / Port | Username | Password |
|------|-----------|----------|----------|
| Primary DB | `localhost:5440` | `postgres` | `StrongPrimary@2025!` |
| Replica 1 | `localhost:5441` | `postgres` | `StrongPrimary@2025!` |
| Replica 2 | `localhost:5442` | `postgres` | `StrongPrimary@2025!` |
| Warehouse DB | `localhost:5435` | `warehouse_user` | `Warehouse@Secure2025!` |
| pgAdmin | `localhost:5050` | `admin@enterprise.com` | `PgAdmin@Secure2025!` |
| Metabase | `localhost:3000` | *(your email)* | *(set on first login)* |
| PgBouncer | `localhost:6433` | `postgres` | `StrongPrimary@2025!` |
