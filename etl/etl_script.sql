-- =============================================================
-- etl_script.sql — Enterprise ETL Pipeline
-- Extract → Stage → Transform → Load into Star Schema
-- Source: operational.loans_db (Primary PostgreSQL)
-- Target: warehouse.warehouse_db
-- =============================================================
-- This script runs inside the warehouse-db context.
-- It uses dblink to query the source (operational) DB.
-- Execution: called by etl_runner.sh via psql
-- =============================================================

-- ── Setup dblink extension ───────────────────────────────────
CREATE EXTENSION IF NOT EXISTS dblink;

-- ── ETL Run Registry ─────────────────────────────────────────
DO $$
DECLARE
    v_run_id          BIGINT;
    v_src_connstr     TEXT;
    v_rows_customers  INT := 0;
    v_rows_loans      INT := 0;
    v_rows_payments   INT := 0;
    v_rows_fact_pay   INT := 0;
    v_rows_fact_loans INT := 0;
BEGIN

    -- Build source connection string (env vars substituted by envsubst before psql runs)
    v_src_connstr := 'host=${SRC_HOST}'
                  || ' port=${SRC_PORT}'
                  || ' dbname=${SRC_DB}'
                  || ' user=${SRC_USER}'
                  || ' password=${SRC_PASSWORD}';

    -- Register ETL run
    INSERT INTO audit.etl_runs (status)
    VALUES ('running')
    RETURNING run_id INTO v_run_id;

    RAISE NOTICE '[ETL] Run #% started at %', v_run_id, NOW();

    -- ==========================================================
    -- PHASE 1: EXTRACT — Truncate staging and reload from source
    -- ==========================================================
    RAISE NOTICE '[ETL] Phase 1: Extracting from source...';

    TRUNCATE staging.stg_customers;
    TRUNCATE staging.stg_loans;
    TRUNCATE staging.stg_payments;

    -- ── Extract customers ─────────────────────────────────────
    INSERT INTO staging.stg_customers
        (customer_id, full_name, email, phone, city, country, segment, created_at)
    SELECT
        customer_id, full_name, email, phone, city, country, segment, created_at
    FROM dblink(
        v_src_connstr,
        'SELECT customer_id, full_name, email, phone, city, country, segment, created_at
         FROM operational.customers
         WHERE is_active = true'
    ) AS t (
        customer_id INT,
        full_name   VARCHAR(100),
        email       VARCHAR(100),
        phone       VARCHAR(20),
        city        VARCHAR(60),
        country     VARCHAR(60),
        segment     VARCHAR(20),
        created_at  TIMESTAMP WITH TIME ZONE
    );

    GET DIAGNOSTICS v_rows_customers = ROW_COUNT;
    RAISE NOTICE '[ETL] Extracted % customers.', v_rows_customers;

    -- ── Extract loans ─────────────────────────────────────────
    INSERT INTO staging.stg_loans
        (loan_id, customer_id, product_id, amount, interest_rate,
         tenure_months, status, disbursed_at, maturity_date, branch_code, created_at)
    SELECT
        loan_id, customer_id, product_id, amount, interest_rate,
        tenure_months, status, disbursed_at, maturity_date, branch_code, created_at
    FROM dblink(
        v_src_connstr,
        'SELECT loan_id, customer_id, product_id, amount, interest_rate,
                tenure_months, status, disbursed_at, maturity_date, branch_code, created_at
         FROM operational.loans'
    ) AS t (
        loan_id       INT,
        customer_id   INT,
        product_id    INT,
        amount        DECIMAL(14,2),
        interest_rate DECIMAL(7,4),
        tenure_months INT,
        status        VARCHAR(20),
        disbursed_at  TIMESTAMP WITH TIME ZONE,
        maturity_date DATE,
        branch_code   VARCHAR(20),
        created_at    TIMESTAMP WITH TIME ZONE
    );

    GET DIAGNOSTICS v_rows_loans = ROW_COUNT;
    RAISE NOTICE '[ETL] Extracted % loans.', v_rows_loans;

    -- ── Extract payments ──────────────────────────────────────
    INSERT INTO staging.stg_payments
        (payment_id, loan_id, amount, principal_portion, interest_portion,
         penalty_portion, payment_method, payment_date, created_at)
    SELECT
        payment_id, loan_id, amount, principal_portion, interest_portion,
        penalty_portion, payment_method, payment_date, created_at
    FROM dblink(
        v_src_connstr,
        'SELECT payment_id, loan_id, amount, principal_portion, interest_portion,
                COALESCE(penalty_portion, 0),
                payment_method, payment_date, created_at
         FROM operational.payments'
    ) AS t (
        payment_id        INT,
        loan_id           INT,
        amount            DECIMAL(14,2),
        principal_portion DECIMAL(14,2),
        interest_portion  DECIMAL(14,2),
        penalty_portion   DECIMAL(14,2),
        payment_method    VARCHAR(30),
        payment_date      DATE,
        created_at        TIMESTAMP WITH TIME ZONE
    );

    GET DIAGNOSTICS v_rows_payments = ROW_COUNT;
    RAISE NOTICE '[ETL] Extracted % payments.', v_rows_payments;

    -- ==========================================================
    -- PHASE 2: LOAD DIMENSIONS
    -- ==========================================================
    RAISE NOTICE '[ETL] Phase 2: Loading dimensions...';

    -- ── dim_customer — UPSERT ─────────────────────────────────
    INSERT INTO warehouse.dim_customer
        (customer_id, full_name, email, phone, city, country, segment)
    SELECT
        customer_id, full_name, email, phone, city, country, segment
    FROM staging.stg_customers
    ON CONFLICT (customer_id) DO UPDATE SET
        full_name  = EXCLUDED.full_name,
        email      = EXCLUDED.email,
        phone      = EXCLUDED.phone,
        city       = EXCLUDED.city,
        country    = EXCLUDED.country,
        segment    = EXCLUDED.segment,
        is_current = TRUE;

    RAISE NOTICE '[ETL] dim_customer loaded.';

    -- ── dim_loan — UPSERT ─────────────────────────────────────
    INSERT INTO warehouse.dim_loan
        (loan_id, customer_id, product_id, amount, interest_rate,
         tenure_months, status, branch_code, disbursed_at, maturity_date)
    SELECT
        loan_id, customer_id, product_id, amount, interest_rate,
        tenure_months, status, branch_code, disbursed_at, maturity_date
    FROM staging.stg_loans
    ON CONFLICT (loan_id) DO UPDATE SET
        status        = EXCLUDED.status,
        branch_code   = EXCLUDED.branch_code,
        maturity_date = EXCLUDED.maturity_date;

    RAISE NOTICE '[ETL] dim_loan loaded.';

    -- ==========================================================
    -- PHASE 3: LOAD FACT_PAYMENTS
    -- ==========================================================
    RAISE NOTICE '[ETL] Phase 3: Loading fact_payments...';

    -- Only insert payments not yet in the fact table
    INSERT INTO warehouse.fact_payments (
        payment_id,
        customer_sk,
        loan_sk,
        date_sk,
        method_sk,
        payment_amount,
        principal_portion,
        interest_portion,
        penalty_portion,
        loan_amount,
        interest_rate,
        customer_segment,
        loan_status,
        branch_code
    )
    SELECT
        sp.payment_id,
        dc.customer_sk,
        dl.loan_sk,
        dd.date_sk,
        dpm.method_sk,
        sp.amount,
        sp.principal_portion,
        sp.interest_portion,
        sp.penalty_portion,
        sl.amount          AS loan_amount,
        sl.interest_rate,
        sc.segment         AS customer_segment,
        sl.status          AS loan_status,
        sl.branch_code
    FROM staging.stg_payments sp
    JOIN staging.stg_loans     sl  ON sl.loan_id     = sp.loan_id
    JOIN staging.stg_customers sc  ON sc.customer_id = sl.customer_id
    JOIN warehouse.dim_customer dc ON dc.customer_id  = sc.customer_id AND dc.is_current = TRUE
    JOIN warehouse.dim_loan     dl ON dl.loan_id      = sl.loan_id
    JOIN warehouse.dim_date     dd ON dd.full_date     = sp.payment_date
    LEFT JOIN warehouse.dim_payment_method dpm ON dpm.method_code = sp.payment_method
    WHERE NOT EXISTS (
        SELECT 1 FROM warehouse.fact_payments fp WHERE fp.payment_id = sp.payment_id
    );

    GET DIAGNOSTICS v_rows_fact_pay = ROW_COUNT;
    RAISE NOTICE '[ETL] Inserted % rows into fact_payments.', v_rows_fact_pay;

    -- ==========================================================
    -- PHASE 4: LOAD FACT_LOANS
    -- ==========================================================
    RAISE NOTICE '[ETL] Phase 4: Loading fact_loans...';

    INSERT INTO warehouse.fact_loans (
        loan_id,
        customer_sk,
        loan_sk,
        disbursement_date_sk,
        maturity_date_sk,
        principal_amount,
        interest_rate,
        tenure_months,
        outstanding_balance,
        total_paid,
        payment_count,
        is_active,
        is_defaulted,
        is_repaid,
        customer_segment,
        branch_code
    )
    SELECT
        sl.loan_id,
        dc.customer_sk,
        dl.loan_sk,
        ddi.date_sk                                AS disbursement_date_sk,
        ddm.date_sk                                AS maturity_date_sk,
        sl.amount                                  AS principal_amount,
        sl.interest_rate,
        sl.tenure_months,
        sl.amount - COALESCE(pay_agg.total_paid, 0) AS outstanding_balance,
        COALESCE(pay_agg.total_paid, 0)            AS total_paid,
        COALESCE(pay_agg.pay_count, 0)             AS payment_count,
        (sl.status = 'active')                     AS is_active,
        (sl.status = 'defaulted')                  AS is_defaulted,
        (sl.status = 'repaid')                     AS is_repaid,
        sc.segment                                 AS customer_segment,
        sl.branch_code
    FROM staging.stg_loans sl
    JOIN staging.stg_customers sc  ON sc.customer_id  = sl.customer_id
    JOIN warehouse.dim_customer dc ON dc.customer_id   = sc.customer_id AND dc.is_current = TRUE
    JOIN warehouse.dim_loan     dl ON dl.loan_id       = sl.loan_id
    LEFT JOIN warehouse.dim_date ddi ON ddi.full_date  = sl.disbursed_at::DATE
    LEFT JOIN warehouse.dim_date ddm ON ddm.full_date  = sl.maturity_date
    LEFT JOIN LATERAL (
        SELECT SUM(amount) AS total_paid, COUNT(*) AS pay_count
        FROM staging.stg_payments
        WHERE loan_id = sl.loan_id
    ) pay_agg ON TRUE
    ON CONFLICT (loan_id) DO UPDATE SET
        outstanding_balance = EXCLUDED.outstanding_balance,
        total_paid          = EXCLUDED.total_paid,
        payment_count       = EXCLUDED.payment_count,
        is_active           = EXCLUDED.is_active,
        is_defaulted        = EXCLUDED.is_defaulted,
        is_repaid           = EXCLUDED.is_repaid,
        etl_loaded_at       = NOW();

    GET DIAGNOSTICS v_rows_fact_loans = ROW_COUNT;
    RAISE NOTICE '[ETL] Inserted/updated % rows in fact_loans.', v_rows_fact_loans;

    -- ==========================================================
    -- Finalize ETL Run
    -- ==========================================================
    UPDATE audit.etl_runs SET
        run_finished_at = NOW(),
        rows_inserted   = v_rows_fact_pay + v_rows_fact_loans,
        rows_updated    = v_rows_customers + v_rows_loans,
        status          = 'success'
    WHERE run_id = v_run_id;

    RAISE NOTICE '[ETL] Run #% completed successfully at %.', v_run_id, NOW();

EXCEPTION WHEN OTHERS THEN
    -- On any error, mark run as failed
    UPDATE audit.etl_runs SET
        run_finished_at = NOW(),
        status          = 'failed',
        error_message   = SQLERRM
    WHERE run_id = v_run_id;

    RAISE EXCEPTION '[ETL] Run #% FAILED: %', v_run_id, SQLERRM;
END;
$$;
