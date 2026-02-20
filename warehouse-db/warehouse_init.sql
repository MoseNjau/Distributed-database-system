-- =============================================================
-- warehouse_init.sql — Enterprise Data Warehouse
-- Star Schema: Loan Management Analytics
-- PostgreSQL 15 | warehouse_db
-- =============================================================

-- ── EXTENSIONS ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── SCHEMAS ──────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS staging;     -- Raw landing zone for ETL
CREATE SCHEMA IF NOT EXISTS warehouse;  -- Curated star schema
CREATE SCHEMA IF NOT EXISTS audit;      -- ETL run metadata

-- ── ROLES ────────────────────────────────────────────────────
CREATE ROLE warehouse_reader WITH LOGIN PASSWORD 'WRReader@2025!' NOREPLICATION;
CREATE ROLE etl_writer       WITH LOGIN PASSWORD 'ETLWriter@2025!' NOREPLICATION;

-- =============================================================
-- AUDIT SCHEMA — ETL Run Tracking
-- =============================================================
CREATE TABLE audit.etl_runs (
    run_id          BIGSERIAL PRIMARY KEY,
    run_started_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    run_finished_at TIMESTAMP WITH TIME ZONE,
    rows_inserted   BIGINT DEFAULT 0,
    rows_updated    BIGINT DEFAULT 0,
    status          VARCHAR(20) DEFAULT 'running'
                        CHECK (status IN ('running','success','failed')),
    error_message   TEXT
);

-- =============================================================
-- STAGING SCHEMA — Raw ETL Landing Zone
-- =============================================================
CREATE TABLE staging.stg_customers (
    customer_id  INT,
    full_name    VARCHAR(100),
    email        VARCHAR(100),
    phone        VARCHAR(20),
    city         VARCHAR(60),
    country      VARCHAR(60),
    segment      VARCHAR(20),
    created_at   TIMESTAMP WITH TIME ZONE,
    etl_loaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging.stg_loans (
    loan_id         INT,
    customer_id     INT,
    product_id      INT,
    amount          DECIMAL(14,2),
    interest_rate   DECIMAL(7,4),
    tenure_months   INT,
    status          VARCHAR(20),
    disbursed_at    TIMESTAMP WITH TIME ZONE,
    maturity_date   DATE,
    branch_code     VARCHAR(20),
    created_at      TIMESTAMP WITH TIME ZONE,
    etl_loaded_at   TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE staging.stg_payments (
    payment_id        INT,
    loan_id           INT,
    amount            DECIMAL(14,2),
    principal_portion DECIMAL(14,2),
    interest_portion  DECIMAL(14,2),
    penalty_portion   DECIMAL(14,2),
    payment_method    VARCHAR(30),
    payment_date      DATE,
    created_at        TIMESTAMP WITH TIME ZONE,
    etl_loaded_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================
-- WAREHOUSE SCHEMA — Star Schema
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- DIMENSION: dim_customer
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.dim_customer (
    customer_sk   SERIAL PRIMARY KEY,              -- Surrogate key
    customer_id   INT NOT NULL UNIQUE,             -- Natural key
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(100),
    phone         VARCHAR(20),
    city          VARCHAR(60),
    country       VARCHAR(60),
    segment       VARCHAR(20),
    effective_date DATE DEFAULT CURRENT_DATE,      -- SCD Type 2 readiness
    expiry_date   DATE,
    is_current    BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_cust_id      ON warehouse.dim_customer(customer_id);
CREATE INDEX idx_dim_cust_segment ON warehouse.dim_customer(segment);

-- ─────────────────────────────────────────────────────────────
-- DIMENSION: dim_loan
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.dim_loan (
    loan_sk       SERIAL PRIMARY KEY,
    loan_id       INT NOT NULL UNIQUE,
    customer_id   INT NOT NULL,
    product_id    INT,
    amount        DECIMAL(14,2),
    interest_rate DECIMAL(7,4),
    tenure_months INT,
    status        VARCHAR(20),
    branch_code   VARCHAR(20),
    disbursed_at  TIMESTAMP WITH TIME ZONE,
    maturity_date DATE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_loan_id     ON warehouse.dim_loan(loan_id);
CREATE INDEX idx_dim_loan_status ON warehouse.dim_loan(status);

-- ─────────────────────────────────────────────────────────────
-- DIMENSION: dim_date  (pre-populated)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.dim_date (
    date_sk       INT PRIMARY KEY,                 -- YYYYMMDD integer key
    full_date     DATE NOT NULL UNIQUE,
    day           SMALLINT NOT NULL,
    month         SMALLINT NOT NULL,
    month_name    VARCHAR(15) NOT NULL,
    quarter       SMALLINT NOT NULL,
    year          SMALLINT NOT NULL,
    week_of_year  SMALLINT,
    day_of_week   SMALLINT,                        -- 0=Sunday..6=Saturday
    day_name      VARCHAR(15),
    is_weekend    BOOLEAN DEFAULT FALSE,
    is_month_end  BOOLEAN DEFAULT FALSE
);

-- ─────────────────────────────────────────────────────────────
-- DIMENSION: dim_product
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.dim_product (
    product_sk   SERIAL PRIMARY KEY,
    product_id   INT NOT NULL UNIQUE,
    product_name VARCHAR(100),
    product_type VARCHAR(30)
);

-- ─────────────────────────────────────────────────────────────
-- DIMENSION: dim_payment_method
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.dim_payment_method (
    method_sk   SERIAL PRIMARY KEY,
    method_code VARCHAR(30) NOT NULL UNIQUE,
    method_name VARCHAR(50)
);

INSERT INTO warehouse.dim_payment_method (method_code, method_name) VALUES
  ('mpesa',         'M-Pesa Mobile Money'),
  ('bank_transfer', 'Bank Transfer'),
  ('cash',          'Cash'),
  ('cheque',        'Cheque'),
  ('online',        'Online Payment');

-- ─────────────────────────────────────────────────────────────
-- FACT TABLE: fact_payments
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.fact_payments (
    payment_sk        BIGSERIAL PRIMARY KEY,
    payment_id        INT NOT NULL,
    -- Foreign keys to dimensions
    customer_sk       INT NOT NULL REFERENCES warehouse.dim_customer(customer_sk),
    loan_sk           INT NOT NULL REFERENCES warehouse.dim_loan(loan_sk),
    date_sk           INT NOT NULL REFERENCES warehouse.dim_date(date_sk),
    method_sk         INT REFERENCES warehouse.dim_payment_method(method_sk),
    -- Measures
    payment_amount        DECIMAL(14,2) NOT NULL,
    principal_portion     DECIMAL(14,2),
    interest_portion      DECIMAL(14,2),
    penalty_portion       DECIMAL(14,2) DEFAULT 0,
    -- Denormalized convenience columns
    loan_amount           DECIMAL(14,2),
    interest_rate         DECIMAL(7,4),
    customer_segment      VARCHAR(20),
    loan_status           VARCHAR(20),
    branch_code           VARCHAR(20),
    -- Metadata
    etl_loaded_at         TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fact_pay_customer    ON warehouse.fact_payments(customer_sk);
CREATE INDEX idx_fact_pay_loan        ON warehouse.fact_payments(loan_sk);
CREATE INDEX idx_fact_pay_date        ON warehouse.fact_payments(date_sk);
CREATE INDEX idx_fact_pay_date_method ON warehouse.fact_payments(date_sk, method_sk);
CREATE INDEX idx_fact_pay_segment     ON warehouse.fact_payments(customer_segment);
CREATE INDEX idx_fact_pay_status      ON warehouse.fact_payments(loan_status);

-- ─────────────────────────────────────────────────────────────
-- FACT TABLE: fact_loans (loan-level grain for portfolio analysis)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE warehouse.fact_loans (
    loan_fact_sk             BIGSERIAL PRIMARY KEY,
    loan_id                  INT NOT NULL UNIQUE,
    customer_sk              INT NOT NULL REFERENCES warehouse.dim_customer(customer_sk),
    loan_sk                  INT NOT NULL REFERENCES warehouse.dim_loan(loan_sk),
    disbursement_date_sk     INT REFERENCES warehouse.dim_date(date_sk),
    maturity_date_sk         INT REFERENCES warehouse.dim_date(date_sk),
    -- Measures
    principal_amount         DECIMAL(14,2),
    interest_rate            DECIMAL(7,4),
    tenure_months            INT,
    outstanding_balance      DECIMAL(14,2),
    total_paid               DECIMAL(14,2) DEFAULT 0,
    payment_count            INT DEFAULT 0,
    -- Status flags
    is_active                BOOLEAN DEFAULT FALSE,
    is_defaulted             BOOLEAN DEFAULT FALSE,
    is_repaid                BOOLEAN DEFAULT FALSE,
    customer_segment         VARCHAR(20),
    branch_code              VARCHAR(20),
    -- Metadata
    etl_loaded_at            TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================
-- PRE-POPULATE dim_date (2018-01-01 to 2050-12-31)
-- =============================================================
INSERT INTO warehouse.dim_date (date_sk, full_date, day, month, month_name, quarter, year, week_of_year, day_of_week, day_name, is_weekend, is_month_end)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT                                AS date_sk,
    d::DATE                                                     AS full_date,
    EXTRACT(DAY   FROM d)::SMALLINT                            AS day,
    EXTRACT(MONTH FROM d)::SMALLINT                            AS month,
    TO_CHAR(d, 'Month')                                        AS month_name,
    EXTRACT(QUARTER FROM d)::SMALLINT                          AS quarter,
    EXTRACT(YEAR  FROM d)::SMALLINT                            AS year,
    EXTRACT(WEEK  FROM d)::SMALLINT                            AS week_of_year,
    EXTRACT(DOW   FROM d)::SMALLINT                            AS day_of_week,
    TO_CHAR(d, 'Day')                                          AS day_name,
    EXTRACT(DOW FROM d) IN (0,6)                               AS is_weekend,
    (d = DATE_TRUNC('month', d) + INTERVAL '1 month' - INTERVAL '1 day')
                                                               AS is_month_end
FROM generate_series('2018-01-01'::DATE, '2050-12-31'::DATE, '1 day'::INTERVAL) AS d;

-- =============================================================
-- ANALYTICAL VIEWS — pre-built for OLAP / Metabase
-- =============================================================

-- Monthly payment revenue
CREATE VIEW warehouse.vw_monthly_revenue AS
SELECT
    dd.year,
    dd.month,
    dd.month_name,
    SUM(fp.payment_amount)    AS total_revenue,
    SUM(fp.principal_portion) AS total_principal,
    SUM(fp.interest_portion)  AS total_interest,
    COUNT(fp.payment_sk)      AS payment_count
FROM warehouse.fact_payments fp
JOIN warehouse.dim_date dd ON fp.date_sk = dd.date_sk
GROUP BY dd.year, dd.month, dd.month_name
ORDER BY dd.year, dd.month;

-- Top paying customers
CREATE VIEW warehouse.vw_top_customers AS
SELECT
    dc.customer_id,
    dc.full_name,
    dc.segment,
    dc.city,
    COUNT(DISTINCT fp.loan_sk)  AS total_loans,
    SUM(fp.payment_amount)      AS total_paid,
    COUNT(fp.payment_sk)        AS payment_count,
    MAX(dd.full_date)           AS last_payment_date
FROM warehouse.fact_payments fp
JOIN warehouse.dim_customer dc ON fp.customer_sk = dc.customer_sk
JOIN warehouse.dim_date     dd ON fp.date_sk     = dd.date_sk
GROUP BY dc.customer_id, dc.full_name, dc.segment, dc.city
ORDER BY total_paid DESC;

-- Loan status distribution
CREATE VIEW warehouse.vw_loan_status_distribution AS
SELECT
    loan_status,
    customer_segment,
    COUNT(*)                      AS loan_count,
    SUM(loan_amount)              AS total_loan_amount,
    AVG(interest_rate)            AS avg_interest_rate
FROM warehouse.fact_payments
GROUP BY loan_status, customer_segment
ORDER BY loan_count DESC;

-- Payment method breakdown
CREATE VIEW warehouse.vw_payment_by_method AS
SELECT
    dpm.method_name,
    COUNT(fp.payment_sk)        AS payment_count,
    SUM(fp.payment_amount)      AS total_amount,
    ROUND(100.0 * SUM(fp.payment_amount) /
          NULLIF(SUM(SUM(fp.payment_amount)) OVER(), 0), 2) AS pct_of_total
FROM warehouse.fact_payments fp
JOIN warehouse.dim_payment_method dpm ON fp.method_sk = dpm.method_sk
GROUP BY dpm.method_name
ORDER BY total_amount DESC;

-- Branch performance
CREATE VIEW warehouse.vw_branch_performance AS
SELECT
    branch_code,
    COUNT(DISTINCT loan_sk)    AS loan_count,
    SUM(payment_amount)        AS total_collected,
    SUM(interest_portion)      AS total_interest_earned,
    AVG(interest_rate)         AS avg_rate
FROM warehouse.fact_payments
GROUP BY branch_code
ORDER BY total_collected DESC;

-- =============================================================
-- GRANTS
-- =============================================================
GRANT USAGE ON SCHEMA staging, warehouse, audit TO etl_writer;
GRANT ALL ON ALL TABLES IN SCHEMA staging   TO etl_writer;
GRANT ALL ON ALL TABLES IN SCHEMA warehouse TO etl_writer;
GRANT ALL ON ALL TABLES IN SCHEMA audit     TO etl_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA warehouse TO etl_writer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA audit     TO etl_writer;

GRANT USAGE ON SCHEMA warehouse TO warehouse_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA warehouse TO warehouse_reader;
