-- =============================================================
-- Operational OLTP Schema — Loan Management System
-- PostgreSQL 15 | Primary Database
-- =============================================================

-- ── EXTENSIONS ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ── ROLES & PERMISSIONS ──────────────────────────────────────

-- Application read/write role
CREATE ROLE app_user WITH LOGIN PASSWORD 'AppUser@Secure2025!' NOREPLICATION;

-- Read-only role (for replicas and reporting)
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'ReadOnly@Secure2025!' NOREPLICATION;

-- ETL extraction role (read-only on primary)
CREATE ROLE etl_reader WITH LOGIN PASSWORD 'EtlReader@Secure2025!' NOREPLICATION;

-- =============================================================
-- SCHEMA
-- =============================================================
CREATE SCHEMA IF NOT EXISTS operational;
SET search_path TO operational, public;

-- ── CUSTOMERS ─────────────────────────────────────────────────
CREATE TABLE customers (
    customer_id   SERIAL PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    national_id   VARCHAR(30) UNIQUE,
    date_of_birth DATE,
    city          VARCHAR(60),
    country       VARCHAR(60) DEFAULT 'Kenya',
    segment       VARCHAR(20) CHECK (segment IN ('retail','sme','corporate')) DEFAULT 'retail',
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_customers_email      ON customers(email);
CREATE INDEX idx_customers_segment    ON customers(segment);
CREATE INDEX idx_customers_created_at ON customers(created_at);

-- ── LOAN PRODUCTS ─────────────────────────────────────────────
CREATE TABLE loan_products (
    product_id    SERIAL PRIMARY KEY,
    product_name  VARCHAR(100) NOT NULL,
    product_type  VARCHAR(30) CHECK (product_type IN ('personal','mortgage','business','auto','education')),
    min_amount    DECIMAL(14,2) NOT NULL,
    max_amount    DECIMAL(14,2) NOT NULL,
    min_tenure_months INT NOT NULL,
    max_tenure_months INT NOT NULL,
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ── LOANS ─────────────────────────────────────────────────────
CREATE TABLE loans (
    loan_id          SERIAL PRIMARY KEY,
    customer_id      INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    product_id       INT REFERENCES loan_products(product_id),
    amount           DECIMAL(14,2) NOT NULL CHECK (amount > 0),
    interest_rate    DECIMAL(7,4) NOT NULL CHECK (interest_rate >= 0),
    tenure_months    INT NOT NULL CHECK (tenure_months > 0),
    status           VARCHAR(20) NOT NULL
                         CHECK (status IN ('pending','active','repaid','defaulted','written_off'))
                         DEFAULT 'pending',
    disbursed_at     TIMESTAMP WITH TIME ZONE,
    maturity_date    DATE,
    outstanding_balance DECIMAL(14,2),
    loan_officer     VARCHAR(100),
    branch_code      VARCHAR(20),
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_loans_customer_id ON loans(customer_id);
CREATE INDEX idx_loans_status      ON loans(status);
CREATE INDEX idx_loans_created_at  ON loans(created_at);
CREATE INDEX idx_loans_product_id  ON loans(product_id);

-- ── PAYMENTS ──────────────────────────────────────────────────
CREATE TABLE payments (
    payment_id     SERIAL PRIMARY KEY,
    loan_id        INT NOT NULL REFERENCES loans(loan_id) ON DELETE RESTRICT,
    amount         DECIMAL(14,2) NOT NULL CHECK (amount > 0),
    principal_portion DECIMAL(14,2),
    interest_portion  DECIMAL(14,2),
    penalty_portion   DECIMAL(14,2) DEFAULT 0,
    payment_method VARCHAR(30) CHECK (payment_method IN ('mpesa','bank_transfer','cash','cheque','online')),
    reference_number VARCHAR(50),
    payment_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    recorded_by    VARCHAR(100),
    notes          TEXT,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_loan_id      ON payments(loan_id);
CREATE INDEX idx_payments_payment_date ON payments(payment_date);
CREATE INDEX idx_payments_method       ON payments(payment_method);

-- ── AUDIT LOG ────────────────────────────────────────────────
CREATE TABLE audit_log (
    log_id       BIGSERIAL PRIMARY KEY,
    table_name   VARCHAR(50),
    operation    VARCHAR(10) CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    record_id    INT,
    changed_by   VARCHAR(100),
    change_time  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    old_values   JSONB,
    new_values   JSONB
);

CREATE INDEX idx_audit_table_op   ON audit_log(table_name, operation);
CREATE INDEX idx_audit_change_time ON audit_log(change_time);

-- =============================================================
-- TRIGGER — auto-update updated_at columns
-- =============================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_loans_updated_at
    BEFORE UPDATE ON loans
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================
-- TRIGGER — audit trail for loans table
-- =============================================================
CREATE OR REPLACE FUNCTION audit_loans()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log(table_name, operation, record_id, new_values)
        VALUES ('loans', 'INSERT', NEW.loan_id, row_to_json(NEW)::jsonb);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log(table_name, operation, record_id, old_values, new_values)
        VALUES ('loans', 'UPDATE', NEW.loan_id, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log(table_name, operation, record_id, old_values)
        VALUES ('loans', 'DELETE', OLD.loan_id, row_to_json(OLD)::jsonb);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_loans_audit
    AFTER INSERT OR UPDATE OR DELETE ON loans
    FOR EACH ROW EXECUTE FUNCTION audit_loans();

-- =============================================================
-- VIEWS — for reporting and replica reads
-- =============================================================
CREATE VIEW vw_active_loans AS
SELECT
    l.loan_id,
    c.full_name        AS customer_name,
    c.email,
    c.segment,
    lp.product_name,
    l.amount,
    l.interest_rate,
    l.tenure_months,
    l.outstanding_balance,
    l.status,
    l.disbursed_at,
    l.maturity_date
FROM loans l
JOIN customers c  ON l.customer_id = c.customer_id
LEFT JOIN loan_products lp ON l.product_id = lp.product_id
WHERE l.status = 'active';

CREATE VIEW vw_customer_payment_summary AS
SELECT
    c.customer_id,
    c.full_name,
    c.segment,
    COUNT(DISTINCT l.loan_id)          AS total_loans,
    SUM(l.amount)                      AS total_loan_amount,
    COUNT(p.payment_id)                AS total_payments,
    COALESCE(SUM(p.amount), 0)         AS total_paid,
    MAX(p.payment_date)                AS last_payment_date
FROM customers c
LEFT JOIN loans l   ON l.customer_id = c.customer_id
LEFT JOIN payments p ON p.loan_id = l.loan_id
GROUP BY c.customer_id, c.full_name, c.segment;

-- =============================================================
-- GRANT PERMISSIONS
-- =============================================================
-- Grant schema usage
GRANT USAGE ON SCHEMA operational TO app_user, readonly_user, etl_reader;

-- app_user: full DML on operational tables
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA operational TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA operational TO app_user;

-- readonly_user: SELECT only (for replica queries)
GRANT SELECT ON ALL TABLES IN SCHEMA operational TO readonly_user;

-- etl_reader: SELECT only (for ETL extraction)
GRANT SELECT ON ALL TABLES IN SCHEMA operational TO etl_reader;
