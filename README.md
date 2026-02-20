# Enterprise Data Platform

A production-grade, fully containerised enterprise data ecosystem built with Docker Compose, PostgreSQL 15, and Metabase.

## Architecture

```
Users / Applications
       │
       ▼
  PgBouncer (Connection Pool — port 6432)
       │
       ▼
PostgreSQL Primary — OLTP Write Master (port 5432)
       │
       ├── Streaming Replication
       │       ├── Replica 1 — Read-Only (port 5433)
       │       └── Replica 2 — Read-Only (port 5434)
       │
       ▼
  ETL Pipeline (scheduled every 15 min)
       │
       ▼
  Data Warehouse — Star Schema (port 5435)
       │
       ▼
  Metabase OLAP — Dashboards & Reports (port 3000)
       │
  pgAdmin — DBA Monitoring (port 5050)
```

## Services

| Service    | Container               | Port | Purpose                      |
| ---------- | ----------------------- | ---- | ---------------------------- |
| Primary DB | `eds_postgres_primary`  | 5432 | OLTP write master            |
| Replica 1  | `eds_postgres_replica1` | 5433 | Read-only replica            |
| Replica 2  | `eds_postgres_replica2` | 5434 | Read-only replica            |
| Warehouse  | `eds_warehouse_db`      | 5435 | Star schema warehouse        |
| ETL        | `eds_etl_pipeline`      | —    | Scheduled ETL (every 15 min) |
| Metabase   | `eds_metabase`          | 3000 | OLAP dashboards              |
| pgAdmin    | `eds_pgadmin`           | 5050 | Database administration      |
| PgBouncer  | `eds_pgbouncer`         | 6432 | Connection pooler            |

## Quick Start

### Prerequisites

```bash
sudo apt update && sudo apt install docker.io docker-compose-v2 -y
sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # logout and back in after this
```

### Launch

```bash
cd enterprise-data-system/
make up
```

Monitor the startup (replicas take ~60 seconds to bootstrap from primary):

```bash
make logs
```

### Verify Everything Works

```bash
make verify
```

### Access Services

| Service   | URL                   | Credentials                                  |
| --------- | --------------------- | -------------------------------------------- |
| Metabase  | http://localhost:3000 | Set up on first visit                        |
| pgAdmin   | http://localhost:5050 | admin@enterprise.local / PgAdmin@Secure2025! |
| PgBouncer | localhost:6432        | Same as primary                              |

---

## Phase-by-Phase Guide

### Phase 3 — OLTP Database

The primary database runs a **Loan Management System** with:

- `operational.customers` — customer master data
- `operational.loans` — loan records with products and officers
- `operational.payments` — payment transactions
- `operational.loan_products` — product catalogue
- `operational.audit_log` — complete change audit trail

Connect directly:

```bash
make psql-primary
```

### Phase 4 — Streaming Replication

Both replicas use `pg_basebackup` to clone the primary on first start, then stream WAL continuously.

Verify replication:

```bash
make replication
```

Or inside psql on primary:

```sql
SELECT application_name, client_addr, state, sent_lsn, replay_lsn, sync_state
FROM pg_stat_replication;
```

Verify replica is read-only:

```bash
make psql-replica1
# Inside psql:
SELECT pg_is_in_recovery();   -- should return: t
INSERT INTO ...               -- should fail: ERROR: cannot execute INSERT on read-only transaction
```

### Phase 5 — Data Warehouse (Star Schema)

The warehouse uses a proper **star schema**:

```
                    ┌──────────────────┐
                    │   dim_date       │
                    └────────┬─────────┘
                             │
┌───────────────┐   ┌────────▼─────────┐   ┌─────────────────┐
│ dim_customer  ├───►   fact_payments   ◄───┤   dim_loan       │
└───────────────┘   └────────┬─────────┘   └─────────────────┘
                             │
                    ┌────────▼─────────┐
                    │ dim_payment_method│
                    └──────────────────┘
```

Plus `fact_loans` for portfolio-level analysis.

Connect to warehouse:

```bash
make psql-warehouse
```

### Phase 6 — ETL Pipeline

The ETL:

1. **Extracts** from `operational.*` using `dblink`
2. **Stages** into `staging.*` schema
3. **Transforms** (applies dimension lookups, surrogate keys)
4. **Loads** into `warehouse.*` (upserts to handle reruns)
5. **Records** each run in `audit.etl_runs`

Runs automatically every 15 minutes via cron. View history:

```bash
make etl
```

### Phase 7 — OLAP (Metabase)

1. Open http://localhost:3000
2. Complete the Metabase setup wizard
3. Add a new database connection:
   - Type: **PostgreSQL**
   - Host: `warehouse-db`
   - Port: `5432`
   - Database: `warehouse_db`
   - Username: `warehouse_user`
   - Password: from `.env`
4. Build dashboards from these views:
   - `warehouse.vw_monthly_revenue` — revenue by month
   - `warehouse.vw_top_customers` — highest paying customers
   - `warehouse.vw_loan_status_distribution` — portfolio health
   - `warehouse.vw_payment_by_method` — channel breakdown
   - `warehouse.vw_branch_performance` — branch KPIs

### Phase 8 — Concurrency Control

Run the full concurrency demonstration:

```bash
make concurrency
```

Or step through `concurrency/concurrency_demo.sql` manually in two separate psql sessions. Scenarios covered:

- READ COMMITTED (non-repeatable reads)
- REPEATABLE READ (snapshot consistency)
- SERIALIZABLE (full conflict detection)
- Row-level locking with `SELECT FOR UPDATE`
- Deadlock detection and automatic resolution
- ACID: Atomicity rollback verification
- MVCC visibility via `pg_stat_activity` and `pg_locks`

### Phase 9 — Backup & Recovery

**Logical backup (all databases):**

```bash
make backup
```

**Custom-format backup (fastest restore):**

```bash
bash backups/backup.sh backup-custom
```

**List backups:**

```bash
bash backups/backup.sh list
```

**Restore operational DB:**

```bash
make restore FILE=backups/backup_operational_YYYYMMDD_HHMMSS.sql.gz
```

**WAL archive status:**

```bash
bash backups/backup.sh wal
```

WAL segments are archived to the `eds_wal_archive` Docker volume, enabling point-in-time recovery (PITR).

---

## Makefile Commands

```
make up              Start all services
make down            Stop all services
make logs            Tail all service logs
make ps              Show container status
make health          Full health check
make verify          Run automated test suite
make backup          Backup all databases
make restore         Restore from backup file
make replication     Check replication status
make etl             View ETL run history
make concurrency     Run concurrency demo
make psql-primary    Connect to primary (psql)
make psql-replica1   Connect to replica 1 (psql)
make psql-replica2   Connect to replica 2 (psql)
make psql-warehouse  Connect to warehouse (psql)
make clean           Remove containers (keep data)
make nuke            ⚠️ Destroy everything including volumes
```

---

## Security Notes

- All passwords are stored only in `.env` (never committed to version control)
- Add `.env` to `.gitignore` in production
- Replication uses a dedicated `replicator` role with minimal privileges
- Separate roles per tier: `app_user`, `readonly_user`, `etl_reader`, `etl_writer`, `warehouse_reader`
- Network segmentation: backend, analytics, and monitoring networks are isolated

---

## Business Scenario

The OLTP system models a **Loan Management System** typical of microfinance institutions and banks:

- Multi-segment customers (retail, SME, corporate)
- Multiple loan products (personal, business, mortgage, auto, education)
- Full payment tracking with principal/interest breakdown
- Branch-level attribution and loan officer assignment
- Complete audit trail via triggers
