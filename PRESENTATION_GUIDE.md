# Enterprise Data Platform — Complete Technical Guide
## Understanding, Explaining & Presenting Your Project

> **Audience:** You — a student who needs to understand every layer of this system so you can explain it confidently.
> **Tone:** Plain English first, then technical terms, then how to say it out loud.

---

## TABLE OF CONTENTS

1. [The Big Picture — What Did You Actually Build?](#1-the-big-picture)
2. [Architecture Diagram — How Everything Connects](#2-architecture-diagram)
3. [Technology Stack — What Each Tool Is and Why](#3-technology-stack)
4. [Phase-by-Phase Breakdown](#4-phase-by-phase-breakdown)
   - 4.1 [Docker & Docker Compose](#41-docker--docker-compose)
   - 4.2 [Operational Database (OLTP)](#42-operational-database-oltp)
   - 4.3 [Streaming Replication](#43-streaming-replication)
   - 4.4 [Data Warehouse & Star Schema](#44-data-warehouse--star-schema)
   - 4.5 [ETL Pipeline](#45-etl-pipeline)
   - 4.6 [OLAP & Metabase Dashboards](#46-olap--metabase-dashboards)
   - 4.7 [Concurrency Control](#47-concurrency-control)
   - 4.8 [Backup & Recovery](#48-backup--recovery)
   - 4.9 [Connection Pooling (PgBouncer)](#49-connection-pooling-pgbouncer)
   - 4.10 [Monitoring (pgAdmin)](#410-monitoring-pgadmin)
5. [Key Database Concepts Explained Simply](#5-key-database-concepts-explained-simply)
6. [Live Demo Script — Step-by-Step Commands](#6-live-demo-script)
7. [Anticipated Questions & Model Answers](#7-anticipated-questions--answers)
8. [ER Diagram — OLTP Schema](#8-er-diagram--oltp-schema)
9. [Star Schema Diagram — Data Warehouse](#9-star-schema-diagram)
10. [What Makes This "Enterprise Grade"](#10-what-makes-this-enterprise-grade)
11. [Port & Service Reference Card](#11-port--service-reference-card)

---

## 1. The Big Picture

### What did you build?

Imagine a bank that gives loans to customers. Every day:
- Customers take loans and make payments **(OLTP — the operational system)**
- The bank needs to read data across multiple servers without slowing down writes **(Replication)**
- At the end of each day, analysts want to ask questions like "which branch collected the most money this month?" **(Data Warehouse + OLAP)**
- The bank needs to be sure that if two people press "pay" at the same time, the money doesn't get counted twice **(Concurrency Control)**
- If the database crashes, they need to restore it **(Backup & Recovery)**

You built **all of that**, running inside **Docker containers** on a single Linux machine.

### The system in one sentence:
> *A fully containerised, distributed data platform for a Loan Management System featuring streaming replication, a star-schema data warehouse, an automated ETL pipeline, OLAP dashboards, concurrency control demonstrations, and backup/recovery mechanisms.*

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        LINUX HOST MACHINE                       │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Docker Network: eds_backend             │   │
│  │                                                          │   │
│  │   ┌──────────────────────┐                              │   │
│  │   │  eds_postgres_primary │  ← ALL WRITES happen here   │   │
│  │   │  PostgreSQL 15        │                              │   │
│  │   │  Port: 5440 (host)   │                              │   │
│  │   │  loans_db schema     │                              │   │
│  │   │  WAL Archiving ON    │                              │   │
│  │   └──────────┬───────────┘                              │   │
│  │              │                                          │   │
│  │    WAL (Write-Ahead Log) Streaming                      │   │
│  │         ┌────┴────┐                                     │   │
│  │         ▼          ▼                                     │   │
│  │  ┌──────────┐  ┌──────────┐                             │   │
│  │  │ Replica 1│  │ Replica 2│  ← READ-ONLY               │   │
│  │  │Port:5441 │  │Port:5442 │                             │   │
│  │  └──────────┘  └──────────┘                             │   │
│  │                                                          │   │
│  │   ┌──────────────────────┐                              │   │
│  │   │  eds_etl_pipeline    │  ← Extracts every 15 min    │   │
│  │   │  (cron + psql)       │                              │   │
│  │   └──────────┬───────────┘                              │   │
│  └──────────────┼───────────────────────────────────────────┘  │
│                 │ ETL Load                                       │
│  ┌──────────────┼───────────────────────────────────────────┐   │
│  │              ▼          Docker Network: eds_analytics     │   │
│  │   ┌──────────────────────┐                              │   │
│  │   │   eds_warehouse_db   │  Star Schema                 │   │
│  │   │   PostgreSQL 15       │  (fact + dimension tables)   │   │
│  │   │   Port: 5435 (host)  │                              │   │
│  │   └──────────┬───────────┘                              │   │
│  │              │                                          │   │
│  │              ▼                                          │   │
│  │   ┌──────────────────────┐                              │   │
│  │   │   eds_metabase       │  OLAP Dashboards             │   │
│  │   │   Port: 3000 (host)  │  → http://localhost:3000     │   │
│  │   └──────────────────────┘                              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Docker Network: eds_monitoring               │   │
│  │   ┌──────────────┐          ┌──────────────────────┐    │   │
│  │   │ eds_pgbouncer│          │    eds_pgadmin        │    │   │
│  │   │ Port: 6433   │          │    Port: 5050         │    │   │
│  │   │ Connection   │          │    Web Admin UI       │    │   │
│  │   │ Pooler       │          │ http://localhost:5050 │    │   │
│  │   └──────────────┘          └──────────────────────┘    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Summary:
```
Users/Apps
    │
    ▼
PgBouncer (Connection Pooler — manages connection limits)
    │
    ▼
PostgreSQL Primary (Writes: INSERT/UPDATE/DELETE)
    │
    ├──► Replica 1  (Reads only — e.g. reports, analytics)
    ├──► Replica 2  (Reads only — backup read capacity)
    │
    ▼ (every 15 minutes via cron)
ETL Pipeline (Extract → Transform → Load)
    │
    ▼
Data Warehouse (Star Schema — analytical model)
    │
    ▼
Metabase (OLAP Dashboards — graphs, charts, reports)
```

---

## 3. Technology Stack

### Understanding each tool:

| Tool | What it is | Why we used it |
|------|-----------|----------------|
| **Docker** | Creates isolated "containers" — like lightweight virtual machines | Keeps services isolated, reproducible, portable |
| **Docker Compose** | Defines and runs multiple Docker containers together | Orchestrates all 9 services with one command |
| **PostgreSQL 15** | The database engine | Industry standard, supports replication, ACID, MVCC |
| **Streaming Replication** | Built-in PostgreSQL feature | Copies data from primary → replicas in real time |
| **pg_basebackup** | PostgreSQL tool to clone a primary DB | Used to bootstrap replicas from scratch |
| **WAL (Write-Ahead Log)** | PostgreSQL's internal change log | Powers both replication and point-in-time recovery |
| **Star Schema** | A data modelling technique | Optimised for analytical queries (OLAP) |
| **dblink** | PostgreSQL extension | Allows one PostgreSQL instance to query another |
| **ETL** | Extract, Transform, Load | Moves data from the OLTP DB to the warehouse |
| **cron** | Linux job scheduler | Runs the ETL SQL automatically every 15 minutes |
| **Metabase** | Open-source BI tool | Point-and-click dashboard creation, no SQL needed |
| **PgBouncer** | Connection pooler | Prevents the database from being overwhelmed with connections |
| **pgAdmin** | Web GUI for PostgreSQL admin | Browse tables, run queries, monitor replication |
| **envsubst** | Linux text substitution tool | Safely injects environment variables into SQL scripts |

---

## 4. Phase-by-Phase Breakdown

---

### 4.1 Docker & Docker Compose

#### What is Docker?
Think of Docker like a shipping container for software.
- Before Docker: "It works on my machine but not yours" — because environments differ.
- With Docker: You define the exact environment (OS, software, config) in a file called a **Dockerfile**, and it runs identically everywhere.

#### What is Docker Compose?
A YAML file (`docker-compose.yml`) that declares **all your services at once**.
Instead of running 9 separate `docker run` commands with 20 flags each, you write them all in one file and run:
```bash
docker compose up -d
```

#### Key concepts in our Compose file:

**Volumes** — Persistent storage that survives container restarts:
```yaml
volumes:
  primary_data:      # Primary DB data files
  replica1_data:     # Replica 1 data
  warehouse_data:    # Warehouse data
  wal_archive:       # WAL archive files (for recovery)
```

**Networks** — Isolated virtual networks for security:
```yaml
networks:
  eds_backend:    # Primary, replicas, ETL (internal only)
  eds_analytics:  # Warehouse + Metabase
  eds_monitoring: # pgAdmin, PgBouncer
```
This means Metabase **cannot** directly reach the primary OLTP database — it can only see the warehouse. This is proper network segmentation.

**Health checks** — Docker waits for a service to be ready before starting dependents:
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 10s
  retries: 10
```

---

### 4.2 Operational Database (OLTP)

#### What is OLTP?
**Online Transaction Processing** — the "live" database that handles day-to-day operations.
- Customers taking loans → `INSERT INTO loans`
- Customer making a payment → `INSERT INTO payments`
- Loan status changing → `UPDATE loans SET status = 'repaid'`

Characteristics:
- Many **small, fast transactions**
- Optimised for **writes and point lookups**
- Must be **ACID compliant** (more on ACID later)

#### Our Schema — The Loan Management System

The operational database (`loans_db`) has this schema in the `operational` schema:

```
customers
├── customer_id (PK)
├── full_name
├── email (UNIQUE)
├── phone
├── national_id
├── city, country
├── segment ('retail' | 'sme' | 'corporate')
└── created_at, updated_at

loan_products
├── product_id (PK)
├── product_name, product_type
└── min/max amount, term limits

loans
├── loan_id (PK)
├── customer_id (FK → customers)
├── product_id  (FK → loan_products)
├── amount, interest_rate, tenure_months
├── status ('pending'|'active'|'repaid'|'defaulted')
├── outstanding_balance
└── branch_code, loan_officer

payments
├── payment_id (PK)
├── loan_id (FK → loans)
├── amount
├── principal_portion, interest_portion, penalty_portion
├── payment_method ('mpesa'|'bank_transfer'|'cash'|...)
└── payment_date

audit_log
└── Every INSERT/UPDATE/DELETE on loans is captured here
```

#### Production Features included:
- **Triggers** — `set_updated_at()` automatically updates `updated_at` on every row change
- **Audit trail** — `audit_loans()` trigger records old and new values as JSON on every loan change
- **Roles** — `app_user`, `readonly_user`, `etl_reader` with least-privilege permissions
- **Views** — `vw_active_loans`, `vw_customer_payment_summary` for common queries

#### How to show above:
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db -c "\dn"          # list schemas
docker exec eds_postgres_primary psql -U postgres -d loans_db -c "\dt operational.*"  # list tables
docker exec eds_postgres_primary psql -U postgres -d loans_db -c "SELECT * FROM operational.vw_customer_payment_summary LIMIT 5;"
```

---

### 4.3 Streaming Replication

#### What is replication? (Simple explanation)
Imagine you write a diary every day. Replication is like having someone **immediately photocopy every page** you write and keep an identical copy in another room. If your original diary is lost, the copy is already up to date.

In PostgreSQL:
- Every change (INSERT/UPDATE/DELETE) is first written to the **WAL (Write-Ahead Log)**
- The WAL is **streamed in real time** to standby servers (replicas)
- Replicas **replay** the WAL to stay in sync
- Replicas are **read-only** — they reject writes

#### How We Set It Up

**Step 1 — Primary configuration (`postgresql.conf`):**
```ini
wal_level = replica         # WAL must include enough info for replication
max_wal_senders = 10        # Allow up to 10 replicas to connect
max_replication_slots = 10  # Reserve a slot for each replica
wal_keep_size = 2048        # Keep 2GB of WAL so slow replicas don't fall behind
archive_mode = on           # Also archive WAL to disk (for disaster recovery)
```

**Step 2 — Replication user and slots (created at startup):**
```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '...';
SELECT pg_create_physical_replication_slot('replica1_slot');
SELECT pg_create_physical_replication_slot('replica2_slot');
```
The **slot** ensures the primary keeps WAL until the replica has consumed it — the replica won't fall behind and lose data.

**Step 3 — pg_hba.conf (access control):**
```
host  replication  replicator  172.20.0.0/16  md5
```
Only the `replicator` user, from within the Docker backend network, can connect for replication.

**Step 4 — Bootstrap each replica (runs on first start):**
```bash
pg_basebackup \
  --host=postgres-primary \
  --username=replicator \
  --pgdata=/var/lib/postgresql/data \
  --wal-method=stream \        # Stream WAL during backup (no gap)
  --slot=replica1_slot \       # Use the pre-created slot
  --checkpoint=fast \
  -R                           # Write standby.signal + primary_conninfo automatically
```
`pg_basebackup` clones the **entire primary** (data files + WAL) to create a starting point for the replica.

**Step 5 — Standby starts, plays WAL from primary:**
```
LOG: entering standby mode
LOG: redo starts at 0/80000D8
LOG: consistent recovery state reached at 0/80001B0
LOG: database system is ready to accept read-only connections
LOG: started streaming WAL from primary at 0/A000000 on timeline 1
```

#### Verify replication is working:
```bash
# On primary — shows connected replicas
docker exec eds_postgres_primary psql -U postgres -d loans_db -c \
  "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"

# On replica — confirm it's a standby
docker exec eds_postgres_replica1 psql -U postgres -d loans_db -c \
  "SELECT pg_is_in_recovery();"
# Returns: t (true = it IS a standby/replica)

# Try writing on replica — will fail
docker exec eds_postgres_replica1 psql -U postgres -d loans_db -c \
  "INSERT INTO operational.customers (full_name, email) VALUES ('x','x@x.com');"
# ERROR: cannot execute INSERT in a read-only transaction
```

---

### 4.4 Data Warehouse & Star Schema

#### Why a separate database for analysis?
The OLTP database is optimised for **many small fast transactions**.
Analytical queries are the opposite — they scan **millions of rows** and do **complex aggregations**:
```sql
-- "What was our total revenue per month for the last 3 years, broken down by branch?"
SELECT branch, year, month, SUM(amount) FROM ...
```
Running this on the live OLTP database would:
1. **Slow down** customer transactions
2. Return inconsistent results if data changes mid-query

The **Data Warehouse** is a separate database designed **just for analytics**.

#### What is a Star Schema?
A star schema organises data into:
- **One central Fact Table** — contains numbers (amounts, counts)
- **Multiple Dimension Tables** around it — contain descriptive context (who, what, when, where)

When you draw it, it looks like a star (fact in the middle, dimensions radiating out).

```
                    dim_date
                       │
                       │
dim_customer ──── fact_payments ──── dim_loan
                       │
                       │
              dim_payment_method
```

#### Our Star Schema:

**Fact Table — `fact_payments`** (one row per payment made):
```
payment_id       — the transaction
customer_sk      — FK to dim_customer (who paid)
loan_sk          — FK to dim_loan (which loan)
date_sk          — FK to dim_date (when)
method_sk        — FK to dim_payment_method (how)
payment_amount   — MEASURE: how much
principal_portion — MEASURE: principal component
interest_portion  — MEASURE: interest component
customer_segment — quick filter (retail/sme/corporate)
loan_status      — quick filter
branch_code      — quick filter
```

**Fact Table — `fact_loans`** (one row per loan, for portfolio analysis):
```
loan_id, customer_sk, loan_sk
principal_amount, outstanding_balance, total_paid
is_active, is_defaulted, is_repaid
```

**Dimension Table — `dim_customer`:**
```
customer_sk (surrogate/warehouse key)
customer_id (natural/source key)
full_name, email, city, segment
effective_date, is_current  ← SCD Type 2 readiness
```

**Dimension Table — `dim_loan`:**
```
loan_sk, loan_id
amount, interest_rate, tenure_months, status, branch_code
```

**Dimension Table — `dim_date`** (pre-populated 2018–2050):
```
date_sk = 20260220 (YYYYMMDD integer — very fast joins)
full_date, day, month, month_name, quarter, year
week_of_year, day_name, is_weekend, is_month_end
```

**Dimension Table — `dim_payment_method`:**
```
mpesa, bank_transfer, cash, cheque, online
```

#### Why surrogate keys?
In the warehouse, we use a **surrogate key** (`customer_sk`) instead of the natural key (`customer_id`). Why?
- Lets us handle slowly changing data (SCD Type 2) — e.g. a customer changes their city, we create a new record, the old payments still point to their old city
- Integer joins are faster than string joins
- Decouples warehouse from source system changes

#### Show analytical views:
```bash
# Monthly revenue trend
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT year, month, month_name, total_revenue, payment_count FROM warehouse.vw_monthly_revenue ORDER BY year, month;"

# Top paying customers
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT full_name, segment, total_paid, payment_count FROM warehouse.vw_top_customers LIMIT 5;"

# Loan status distribution
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT loan_status, COUNT(*), SUM(loan_amount) FROM warehouse.fact_payments GROUP BY loan_status;"
```

---

### 4.5 ETL Pipeline

#### What is ETL?
**Extract, Transform, Load** — the bridge between your operational DB and your warehouse.

```
EXTRACT     → Read data from the source (OLTP primary)
TRANSFORM   → Reshape it into the dimensional model (star schema)
LOAD        → Write it into the warehouse tables
```

#### Our ETL Architecture

**Technology used:**
- `PostgreSQL dblink` extension — allows one PostgreSQL instance to query another over the network
- `envsubst` — substitutes shell environment variables into the SQL script before executing
- `cron` inside the ETL container — schedules the job every 15 minutes
- `psql` — PostgreSQL command-line client that runs the SQL

**ETL Flow (what the SQL actually does):**

```
1. SETUP
   └─ CREATE EXTENSION dblink (enables cross-database queries)
   └─ INSERT INTO audit.etl_runs (status='running') → get run_id

2. PHASE 1: EXTRACT (into staging)
   ├─ TRUNCATE staging.stg_customers
   ├─ INSERT INTO staging.stg_customers
   │   SELECT ... FROM dblink('host=postgres-primary...', 'SELECT * FROM operational.customers')
   ├─ INSERT INTO staging.stg_loans (same pattern)
   └─ INSERT INTO staging.stg_payments (same pattern)

3. PHASE 2: LOAD DIMENSIONS
   ├─ INSERT INTO warehouse.dim_customer ... ON CONFLICT (customer_id) DO UPDATE
   └─ INSERT INTO warehouse.dim_loan ...     ON CONFLICT (loan_id) DO UPDATE

4. PHASE 3: LOAD FACT_PAYMENTS
   └─ INSERT INTO warehouse.fact_payments
       JOIN staging tables to resolve dimension surrogate keys
       WHERE payment_id NOT already in fact_payments (incremental load)

5. PHASE 4: LOAD FACT_LOANS
   └─ INSERT INTO warehouse.fact_loans
       WITH aggregated totals (SUM payments, COUNT payments)
       ON CONFLICT (loan_id) DO UPDATE (update outstanding balance, etc.)

6. FINALISE
   └─ UPDATE audit.etl_runs SET status='success', rows_inserted=..., run_finished_at=NOW()
```

**What happens on error?**
```sql
EXCEPTION WHEN OTHERS THEN
    UPDATE audit.etl_runs SET status='failed', error_message=SQLERRM
    WHERE run_id = v_run_id;
    RAISE EXCEPTION ...
```
Every ETL run is either fully committed or fully rolled back — the `$$...$$` PL/pgSQL block runs as one transaction.

#### Scheduling:
The ETL container runs a `cron` job:
```
*/15 * * * *  bash /app/etl_runner.sh
```
Translation: every 15 minutes, on every hour.

#### Verify ETL:
```bash
# Check ETL run history
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT run_id, run_started_at, rows_inserted, status FROM audit.etl_runs ORDER BY run_id DESC LIMIT 5;"

# Check ETL container logs
docker logs eds_etl_pipeline 2>&1 | tail -30
```

---

### 4.6 OLAP & Metabase Dashboards

#### What is OLAP?
**Online Analytical Processing** — querying large volumes of data to find patterns, trends, and summaries.

Examples of OLAP questions:
- "What was our total loan disbursement by month for the past 2 years?"
- "Which customer segment has the highest default rate?"
- "Which branch collected the most interest revenue?"

OLAP is the **opposite** of OLTP:
| OLAP | OLTP |
|------|------|
| Few complex queries | Many simple queries |
| Reads millions of rows | Reads/writes single rows |
| Historical data analysis | Current state |
| Seconds/minutes response | Millisecond response |

#### What is Metabase?
An open-source Business Intelligence (BI) tool that lets you:
- Connect to a database
- Create charts, graphs, tables without writing SQL
- Build dashboards for reports
- Schedule automatic email reports

Metabase stores its own metadata in `metabase_db` (also on warehouse-db).

#### Connecting Metabase to the Warehouse:
When you open Metabase for the first time at `http://localhost:3000`:
1. Set up an admin account
2. Add a database connection:
   - Type: **PostgreSQL**
   - Host: `warehouse-db` (the Docker service name — works because they share the analytics network)
   - Port: `5432`
   - Database: `warehouse_db`
   - Username: `warehouse_user`
   - Password: `Warehouse@Secure2025!`
3. Metabase will discover all tables in the `warehouse` schema
4. Create questions (queries) and add them to dashboards

#### Dashboards you can create in Metabase:
- **Total Loans Issued** — `SELECT COUNT(*) FROM warehouse.fact_loans`
- **Total Revenue** — `SELECT SUM(payment_amount) FROM warehouse.fact_payments`
- **Monthly Revenue Chart** — from `warehouse.vw_monthly_revenue`
- **Top Paying Customers** — from `warehouse.vw_top_customers`
- **Loan Status Distribution (Pie Chart)** — from `warehouse.vw_loan_status_distribution`
- **Payment Method Breakdown** — from `warehouse.vw_payment_by_method`

---

### 4.7 Concurrency Control

#### What is concurrency?
When **two people try to change the same data at the same time**, what happens?

Classic problem:
- Person A reads: loan outstanding_balance = KES 50,000
- Person B reads: loan outstanding_balance = KES 50,000
- Person A pays KES 5,000 → writes 45,000
- Person B pays KES 5,000 → writes 45,000 (instead of 40,000)
**Net effect: one payment was lost!**

#### ACID Properties (the guarantees a database must provide):

| Letter | Property | Meaning |
|--------|----------|---------|
| **A** | Atomicity | A transaction either fully completes or fully rolls back. No partial updates. |
| **C** | Consistency | Data is always in a valid state. Constraints (e.g. foreign keys) are never violated. |
| **I** | Isolation | Concurrent transactions behave as if they ran one at a time. |
| **D** | Durability | Once committed, data survives crashes (thanks to WAL). |

#### MVCC — PostgreSQL's Concurrency Magic
PostgreSQL uses **Multi-Version Concurrency Control (MVCC)**.
- Instead of **locking rows** when reading (which blocks writers), PostgreSQL keeps **multiple versions** of each row.
- Each transaction sees a **snapshot** of the data at the moment it started.
- Writers and readers **never block each other**.

#### Isolation Levels (what to demonstrate):

**1. READ COMMITTED (default)**
```sql
-- Session A:
BEGIN;
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- Returns: 95000

-- Session B (simultaneously):
BEGIN;
UPDATE operational.loans SET outstanding_balance = 90000 WHERE loan_id = 1;
COMMIT;

-- Back in Session A:
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- Returns: 90000  ← Session A NOW sees B's committed change (non-repeatable read)
COMMIT;
```
**Problem shown:** A read within the same transaction returned different results.

**2. REPEATABLE READ**
```sql
-- Session A:
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- Returns: 95000

-- Session B makes and commits a change to loan 1...

-- Back in Session A:
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- Still returns: 95000  ← Protected by the snapshot
COMMIT;
```
**Benefit shown:** The read is consistent throughout the transaction.

**3. SERIALIZABLE**
```sql
-- Strongest isolation — transactions behave as if they ran serially.
-- If PostgreSQL detects a conflict it would cause inconsistency,
-- it aborts one transaction with: ERROR: could not serialize access...
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
...
```

**4. Row-Level Locking**
```sql
-- Session A: Lock the row for update
BEGIN;
SELECT * FROM operational.loans WHERE loan_id = 1 FOR UPDATE;
-- Session A now HOLDS the row lock

-- Session B: Try to lock same row
BEGIN;
SELECT * FROM operational.loans WHERE loan_id = 1 FOR UPDATE;
-- Session B BLOCKS here — waiting for Session A to release

-- Session A:
UPDATE operational.loans SET outstanding_balance = 90000 WHERE loan_id = 1;
COMMIT;
-- Now Session B proceeds with the updated value
```

#### How to run the concurrency demo:
```bash
# Open two separate terminal sessions
# Session A:
docker exec -it eds_postgres_primary psql -U postgres -d loans_db

# Session B:
docker exec -it eds_postgres_primary psql -U postgres -d loans_db

# Then run the concurrency_demo.sql blocks in each session
```

---

### 4.8 Backup & Recovery

#### Why backup?
- Hardware fails
- Someone accidentally runs `DELETE FROM loans`
- Ransomware encrypts the data
- A software bug corrupts a table

You need to restore data to a known-good state.

#### Two backup strategies implemented:

**1. Logical Backup (pg_dump)**
- Produces a SQL script of all `CREATE TABLE`, `INSERT` statements
- Human-readable, database-version-portable
- Slower to restore but very flexible

```bash
# Take a backup
cd enterprise-data-system
bash backups/backup.sh backup operational

# This runs inside the container:
pg_dump -U postgres -d loans_db --schema=operational > backup_operational_TIMESTAMP.sql.gz

# Restore (replace all data):
bash backups/backup.sh restore backups/backup_operational_20260220_120000.sql.gz
```

**2. WAL Archiving (continuous, for Point-In-Time Recovery)**
The primary is configured with:
```ini
archive_mode = on
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'
```
Every WAL file (16MB of changes) is copied to `/archive/` as it's completed.

This enables **Point-In-Time Recovery (PITR)**:
- "Restore the database to exactly how it was at 14:32:05 on Tuesday"
- Critical for banks where every second of data matters

**Check archive status:**
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db -c \
  "SELECT archived_count, last_archived_wal, last_archived_time FROM pg_stat_archiver;"
```

---

### 4.9 Connection Pooling (PgBouncer)

#### The problem without pooling:
PostgreSQL creates a **new OS process** for every client connection. Each process uses ~5-10MB RAM.
- 200 users connect → 200 PostgreSQL processes → 2GB RAM just for connections
- If 1000 users connect simultaneously, the database crashes

#### What PgBouncer does:
PgBouncer sits between clients and PostgreSQL:
- Clients connect to **PgBouncer (port 6433)**
- PgBouncer maintains a **small pool** of actual PostgreSQL connections (25 in our config)
- 200 clients share 25 server connections
- When a client finishes a transaction, its server connection is returned to the pool for the next client

```
200 App Connections → PgBouncer → 25 PostgreSQL connections
```

**Our config:**
```
pool_mode = transaction    # Connection returned to pool after each COMMIT
max_client_conn = 200      # Max 200 client connections
default_pool_size = 25     # 25 actual server connections
```

---

### 4.10 Monitoring (pgAdmin)

pgAdmin at `http://localhost:5050` gives you:
- Visual query editor with syntax highlighting
- Browse tables, indexes, views
- `EXPLAIN`/`EXPLAIN ANALYZE` plan visualiser
- Monitor `pg_stat_activity` (who is connected, what they're doing)
- Monitor `pg_stat_replication` (replication lag in bytes and seconds)

**Login:**
- Email: `admin@enterprise.com`
- Password: `PgAdmin@Secure2025!`

**Then register servers:**
- Primary: Host `localhost`, Port `5440`, DB `loans_db`, User `postgres`
- Warehouse: Host `localhost`, Port `5435`, DB `warehouse_db`, User `warehouse_user`

---

## 5. Key Database Concepts Explained Simply

### What is a Primary Key?
A column (or combination) that **uniquely identifies every row**. No two rows can have the same PK.
```sql
customer_id SERIAL PRIMARY KEY  -- auto-increments: 1, 2, 3, 4...
```

### What is a Foreign Key?
A column that **references the primary key of another table**, enforcing that the relationship makes sense:
```sql
loan_id INT REFERENCES loans(loan_id)
-- You cannot insert a payment for a loan_id that doesn't exist
```

### What is an Index?
An index is like the **index in the back of a textbook** — instead of reading every page, you go straight to the page number.
```sql
CREATE INDEX idx_loans_status ON loans(status);
-- Now "SELECT * FROM loans WHERE status='active'" doesn't scan all rows
```

### What is a Transaction?
A group of SQL statements that are treated as **one unit**:
```sql
BEGIN;
    UPDATE loans SET outstanding_balance = outstanding_balance - 5000 WHERE loan_id = 1;
    INSERT INTO payments (loan_id, amount) VALUES (1, 5000);
COMMIT;
-- Either BOTH happen, or NEITHER happens
```

### What is WAL?
The **Write-Ahead Log** — PostgreSQL writes every change to this log BEFORE applying it to the actual data files.
- Ensures **durability** (D in ACID) — even if the machine crashes mid-write, the WAL has the full record
- Powers **replication** — replicas just read and replay the WAL
- Enables **PITR** — you can replay WAL up to any point in time

### What is Streaming Replication vs Logical Replication?
- **Streaming (Physical) Replication** — copies the raw WAL byte-for-byte. The replica is an exact binary copy of the primary. Can only be read-only.
- **Logical Replication** — copies row-level changes in a decoded format. Can replicate to different PostgreSQL versions, or replicate only specific tables. We used **Physical** for maximum consistency.

---

## 6. Live Demo Script

Use this to demonstrate the system step by step.

### Step 1: Show all running services
```bash
cd /home/moses/Documents/DistributedDB/enterprise-data-system
docker compose --env-file .env ps
```
*"All 9 services are running. You can see the primary DB on port 5440, two replicas on 5441 and 5442, the warehouse on 5435, Metabase on 3000, and pgAdmin on 5050."*

---

### Step 2: Show OLTP data on primary
```bash
docker exec eds_postgres_primary psql -U postgres -d loans_db -c \
  "SELECT customer_id, full_name, segment, city FROM operational.customers ORDER BY customer_id LIMIT 5;"

docker exec eds_postgres_primary psql -U postgres -d loans_db -c \
  "SELECT loan_id, customer_id, amount, interest_rate, status FROM operational.loans ORDER BY loan_id LIMIT 5;"
```
*"This is our operational OLTP database — a Loan Management System with customers, loans, and payments. Each payment records the principal portion, interest portion, and how it was paid, for example via M-Pesa or bank transfer."*

---

### Step 3: Demonstrate streaming replication
```bash
# Show both replicas are streaming
docker exec eds_postgres_primary psql -U postgres -d loans_db -c \
  "SELECT client_addr, state, sync_state, sent_lsn = replay_lsn AS zero_lag FROM pg_stat_replication;"

# Show replica is a standby
docker exec eds_postgres_replica1 psql -U postgres -d loans_db -c \
  "SELECT pg_is_in_recovery() AS is_replica;"

# Prove data is replicated — read from replica
docker exec eds_postgres_replica1 psql -U postgres -d loans_db -c \
  "SELECT COUNT(*) AS total_customers FROM operational.customers;"
```
*"The primary currently has two replicas streaming from it in real time. The LSN values — Log Sequence Numbers — are identical, meaning zero replication lag. Replicas have the same data as the primary."*

---

### Step 4: Prove replicas are read-only
```bash
docker exec eds_postgres_replica1 psql -U postgres -d loans_db -c \
  "INSERT INTO operational.customers (full_name, email, segment) VALUES ('Test', 'test@test.com', 'retail');"
```
**Expected output:**
```
ERROR:  cannot execute INSERT in a read-only transaction
```
*"PostgreSQL enforces that replicas are read-only at the engine level. No application mistake can write to a replica."*

---

### Step 5: Show the data warehouse star schema
```bash
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT 'dim_customer' AS tbl, COUNT(*) FROM warehouse.dim_customer
   UNION ALL SELECT 'dim_loan',     COUNT(*) FROM warehouse.dim_loan
   UNION ALL SELECT 'fact_payments',COUNT(*) FROM warehouse.fact_payments
   UNION ALL SELECT 'fact_loans',   COUNT(*) FROM warehouse.fact_loans
   UNION ALL SELECT 'dim_date',     COUNT(*) FROM warehouse.dim_date;"
```
*"The data warehouse uses a star schema. We have 15 customers and 15 loans in the dimension tables, 50 payment facts, and the dim_date table is pre-populated with over 12,000 dates from 2018 to 2050."*

---

### Step 6: Show OLAP analytical queries
```bash
# Monthly revenue analysis
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT year, month_name, total_revenue, payment_count FROM warehouse.vw_monthly_revenue ORDER BY year, month LIMIT 5;"

# Top customers
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT full_name, segment, total_paid FROM warehouse.vw_top_customers LIMIT 5;"
```
*"These pre-built analytical views answer business questions that would be too slow to run on the operational database. For example, vw_monthly_revenue aggregates payment data by month — this is the kind of query that powers a Metabase dashboard."*

---

### Step 7: Show ETL run history
```bash
docker exec eds_warehouse_db psql -U warehouse_user -d warehouse_db -c \
  "SELECT run_id, run_started_at, rows_inserted, rows_updated, status FROM audit.etl_runs ORDER BY run_id DESC LIMIT 5;"
```
**Say:** *"Every ETL run is logged in the audit schema. Run #1 successfully extracted 15 customers, 15 loans and 50 payments, then inserted 65 rows into the warehouse — all within a single transaction."*

---

### Step 8: Show Metabase (open browser)
Open: `http://localhost:3000`

*"Metabase is our OLAP tool. It connects directly to the warehouse database and allows business analysts to create dashboards without writing SQL. It stores its own configuration in the metabase_db database on the same warehouse server."*

---

### Step 9: Demonstrate concurrency (open two terminals)

**Terminal 1:**
```sql
docker exec -it eds_postgres_primary psql -U postgres -d loans_db
BEGIN;
SELECT loan_id, outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- Note the value, keep this transaction open
```

**Terminal 2:**
```sql
docker exec -it eds_postgres_primary psql -U postgres -d loans_db
BEGIN;
UPDATE operational.loans SET outstanding_balance = 80000 WHERE loan_id = 1;
COMMIT;
```

**Terminal 1 (continued):**
```sql
-- With READ COMMITTED (default), Session A now sees 80000
SELECT outstanding_balance FROM operational.loans WHERE loan_id = 1;
COMMIT;
```

**Say:** *"This demonstrates the READ COMMITTED isolation level. Session A's second read sees Session B's committed change — this is called a non-repeatable read. With REPEATABLE READ isolation, Session A would have continued to see the original value."*

---

### Step 10: Demonstrate backup
```bash
bash backups/backup.sh backup operational
ls -lh backups/*.sql.gz
```
*"We can take a logical backup using pg_dump, which produces a compressed SQL file that can restore the entire database schema and data. We also have WAL archiving enabled for Point-In-Time Recovery."*

---

## 7. Anticipated Questions & Answers

### Q: Why PostgreSQL and not MySQL?
**A:** PostgreSQL has native, built-in streaming replication, physical WAL archiving, MVCC concurrency, and supports advanced features like physical replication slots, `pg_basebackup`, and extensions like `dblink` — all critical for this architecture. MySQL requires third-party tools like Percona XtraBackup for equivalent replication setups. PostgreSQL is also the industry standard for analytical and financial workloads.

---

### Q: What is the difference between OLTP and OLAP? Why two separate databases?
**A:** OLTP handles hundreds of small, fast transactions per second — optimised with row-level indexes for inserts and point lookups. OLAP runs complex analytical queries over millions of rows — optimised with a denormalised star schema suited for aggregations. Mixing them causes performance interference: an analyst's full-table scan would block customer transactions. Separating them with an ETL pipeline is the industry standard.

---

### Q: Why use Docker instead of just installing PostgreSQL directly?
**A:** Docker provides:
- **Isolation** — each service runs in its own process namespace, can't interfere with others
- **Reproducibility** — the same configuration runs identically on any machine
- **Dependency management** — `depends_on` ensures services start in the right order
- **Portability** — the entire platform can be moved to a cloud server or another laptop with one command

---

### Q: What happens if the primary database crashes?
**A:** With streaming replication:
1. One of the replicas can be **promoted** to primary using `pg_ctl promote`
2. The other replica re-connects to the new primary
3. Applications reconnect to the new primary

This is **high availability**. With WAL archiving enabled, we can also restore to any point in time before the crash. Automated failover (using Patroni or repmgr) would be the next step in a full production environment.

---

### Q: Why use a replication slot instead of just wal_keep_size?
**A:** A replication slot **guarantees** the primary will retain WAL segments until the replica has consumed them. Without a slot, if the replica falls behind and the WAL is cleaned up, the replica is permanently broken. The slot prevents this at the cost of disk space — the primary holds WAL indefinitely if a replica is unreachable.

---

### Q: What is the difference between READ COMMITTED and SERIALIZABLE?
**A:** 
- **READ COMMITTED**: Each statement sees data committed as of its start. Non-repeatable reads are possible.
- **REPEATABLE READ**: Each transaction sees a snapshot from its start. Repeated reads return the same data.
- **SERIALIZABLE**: Strongest — PostgreSQL detects and aborts transactions that would produce anomalies if run concurrently vs. serially. Used for financial transactions where correctness is paramount.

---

### Q: How does the ETL handle incremental loads? Does it re-insert all data every run?
**A:** No. The ETL uses incremental loading for `fact_payments`:
```sql
WHERE NOT EXISTS (
    SELECT 1 FROM warehouse.fact_payments fp WHERE fp.payment_id = sp.payment_id
)
```
Only payments not already in the warehouse are inserted. Dimensions use `ON CONFLICT ... DO UPDATE` (upsert). `fact_loans` uses the same upsert pattern to update outstanding balances without duplicating records.

---

### Q: What is the surrogate key (customer_sk) vs the natural key (customer_id)?
**A:** The natural key (`customer_id=7`) comes from the source system. The surrogate key (`customer_sk`) is generated by the warehouse itself. This serves two purposes:
1. Enables SCD Type 2 (a customer's segment changes — we create a new dim_customer row with a new `customer_sk`, keeping history intact)
2. Decouples the warehouse from source system ID changes

---

### Q: What security measures are implemented?
**A:**
- **Separate roles**: `app_user` (DML), `readonly_user` (SELECT), `etl_reader` (SELECT on OLTP), `etl_writer` (full access on warehouse), `warehouse_reader` (SELECT on warehouse)
- **Network segmentation**: Backend network (DBs + ETL), Analytics network (Warehouse + Metabase), Monitoring network (pgAdmin + PgBouncer) — cross-network access is explicitly controlled
- **pg_hba.conf**: Host-based authentication restricts replication to specific subnets
- **Credentials via `.env`**: Passwords not hardcoded in docker-compose.yml

---

## 8. ER Diagram — OLTP Schema

```
┌─────────────────────┐        ┌──────────────────────────┐
│     customers       │        │       loan_products       │
├─────────────────────┤        ├──────────────────────────┤
│ PK customer_id      │        │ PK product_id            │
│    full_name        │        │    product_name          │
│    email (UNIQUE)   │        │    product_type          │
│    phone            │        │    min/max_amount        │
│    national_id      │        │    min/max_tenure_months │
│    city, country    │        └──────────┬───────────────┘
│    segment          │                   │
│    created_at       │                   │
└────────┬────────────┘                   │
         │ 1                              │ 1
         │                               │
         │ N                             │ N
┌────────┴────────────────────────────────┴───────────────┐
│                         loans                            │
├──────────────────────────────────────────────────────────┤
│ PK loan_id                                               │
│ FK customer_id         → customers.customer_id           │
│ FK product_id          → loan_products.product_id        │
│    amount, interest_rate, tenure_months                  │
│    status, outstanding_balance                           │
│    disbursed_at, maturity_date                           │
│    loan_officer, branch_code                             │
└─────────────────┬────────────────────────────────────────┘
                  │ 1
                  │
                  │ N
┌─────────────────┴────────────────────┐
│              payments                │
├──────────────────────────────────────┤
│ PK payment_id                        │
│ FK loan_id → loans.loan_id           │
│    amount                            │
│    principal_portion                 │
│    interest_portion                  │
│    penalty_portion                   │
│    payment_method                    │
│    payment_date                      │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│             audit_log                │
├──────────────────────────────────────┤
│ PK log_id                            │
│    table_name, operation             │
│    record_id                         │
│    old_values (JSONB)                │
│    new_values (JSONB)                │
│    change_time                       │
└──────────────────────────────────────┘
   ↑ Populated automatically by triggers on loans table
```

---

## 9. Star Schema Diagram

```
                         ┌─────────────────────┐
                         │      dim_date        │
                         ├─────────────────────┤
                         │ PK date_sk (YYYYMMDD)│
                         │    full_date         │
                         │    day, month, year  │
                         │    quarter, week     │
                         │    month_name        │
                         │    day_name          │
                         │    is_weekend        │
                         │    is_month_end      │
                         └──────────┬──────────┘
                                    │ FK date_sk
┌─────────────────────┐             │           ┌─────────────────────┐
│   dim_customer      │             │           │     dim_loan         │
├─────────────────────┤             │           ├─────────────────────┤
│ PK customer_sk      ├─────────────┼───────────┤ PK loan_sk          │
│ NK customer_id      │   FK        │  FK       │ NK loan_id          │
│    full_name        │ customer_sk │ loan_sk   │    amount           │
│    email, city      │             │           │    interest_rate    │
│    segment          │             │           │    tenure_months    │
│    country          │    ┌────────┴─────────┐ │    status           │
│    is_current       │    │   fact_payments   │ │    branch_code     │
└─────────────────────┘    ├──────────────────┤ └─────────────────────┘
                           │ PK payment_sk    │
                           │ NK payment_id    │ ┌─────────────────────┐
                           │ FK customer_sk   │ │  dim_payment_method  │
                           │ FK loan_sk       │ ├─────────────────────┤
                           │ FK date_sk       ├─┤ PK method_sk        │
                           │ FK method_sk     │ │    method_code      │
                           │                  │ │    method_name      │
                           │ MEASURES:        │ │ (mpesa, bank, cash) │
                           │  payment_amount  │ └─────────────────────┘
                           │  principal       │
                           │  interest        │ ┌─────────────────────┐
                           │  penalty        ─┼─┤    fact_loans        │
                           │                  │ ├─────────────────────┤
                           │ FILTERS:         │ │ PK loan_fact_sk     │
                           │  segment         │ │ FK customer_sk      │
                           │  loan_status     │ │ FK loan_sk          │
                           │  branch_code     │ │    principal_amount │
                           └──────────────────┘ │    outstanding_bal  │
                                                │    total_paid       │
                                                │    payment_count    │
                                                │    is_active        │
                                                │    is_defaulted     │
                                                └─────────────────────┘
```

---

## 10. What Makes This "Enterprise Grade"

| Feature | Basic Implementation | Our Enterprise Implementation |
|---------|---------------------|-------------------------------|
| Database | Single instance | Primary + 2 replicas |
| Connections | Direct psql | PgBouncer connection pooler |
| Analytics | On operational DB | Separate warehouse + ETL |
| Data Model | Flat tables | Star Schema (fact + dimensions) |
| Access control | One user | Multiple roles, least privilege |
| Change tracking | None | Audit log with JSONB old/new values |
| Automation | Manual | Cron-scheduled ETL every 15 min |
| Recovery | Restore from dump | pg_dump + WAL archiving (PITR) |
| Monitoring | None | pgAdmin UI + pg_stat_replication |
| Network | All on one network | Segmented: backend/analytics/monitoring |
| Persistence | Ephemeral | Named Docker volumes |
| Data integrity | None | Triggers, FK constraints, CHECK constraints |
| Observability | None | ETL run audit table, container health checks |

---

## 11. Port & Service Reference Card

Print this and keep it on the desk during your presentation.

```
┌──────────────────────────────────────────────────────────────────┐
│             ENTERPRISE DATA PLATFORM — ACCESS REFERENCE          │
├───────────────────────┬──────────────────┬───────────────────────┤
│ SERVICE               │ HOST PORT        │ CREDENTIALS           │
├───────────────────────┼──────────────────┼───────────────────────┤
│ Primary DB (OLTP)     │ localhost:5440   │ postgres / (in .env)  │
│ Replica 1 (Read-Only) │ localhost:5441   │ postgres / (in .env)  │
│ Replica 2 (Read-Only) │ localhost:5442   │ postgres / (in .env)  │
│ Warehouse DB          │ localhost:5435   │ warehouse_user        │
│ PgBouncer (Pooler)    │ localhost:6433   │ postgres / (in .env)  │
│ Metabase (OLAP UI)    │ localhost:3000   │ Set on first login    │
│ pgAdmin (Admin UI)    │ localhost:5050   │ admin@enterprise.com  │
├───────────────────────┼──────────────────┼───────────────────────┤
│ ETL Schedule          │ Every 15 minutes │ cron inside container │
│ ETL Logs              │ docker logs eds_etl_pipeline             │
│ Backup script         │ bash backups/backup.sh health            │
│ Start all             │ make up                                  │
│ Stop all              │ make down                                │
│ Full health check     │ make health                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Quick Command Cheatsheet

```bash
# Navigate to project
cd /home/moses/Documents/DistributedDB/enterprise-data-system

# Show all container statuses
docker compose --env-file .env ps

# Connect to primary (type SQL directly)
docker exec -it eds_postgres_primary psql -U postgres -d loans_db

# Connect to replica 1 (read-only)
docker exec -it eds_postgres_replica1 psql -U postgres -d loans_db

# Connect to warehouse
docker exec -it eds_warehouse_db psql -U warehouse_user -d warehouse_db

# Check replication
docker exec eds_postgres_primary psql -U postgres -d loans_db \
  -c "SELECT client_addr, state, sent_lsn = replay_lsn AS zero_lag FROM pg_stat_replication;"

# Check ETL logs
docker logs eds_etl_pipeline 2>&1 | tail -30

# Full health check
bash backups/backup.sh health

# Take a backup
bash backups/backup.sh backup all

# Open Metabase
xdg-open http://localhost:3000

# Open pgAdmin
xdg-open http://localhost:5050
```

---

*This document was generated for the Enterprise Data Platform project — a multi-layer data architecture implementation for a Loan Management System using Docker, PostgreSQL 15, Streaming Replication, Star Schema, ETL, Metabase, PgBouncer, and pgAdmin.*
