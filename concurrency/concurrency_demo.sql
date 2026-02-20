-- =============================================================
-- concurrency_demo.sql — PostgreSQL Concurrency Control
-- Demonstrates: MVCC, Isolation Levels, Row Locking, Deadlocks
-- Run these blocks in separate psql sessions as indicated.
-- =============================================================

-- =============================================================
-- SECTION 1: SETUP — Verify data for demonstration
-- =============================================================
\echo '=== SECTION 1: Setup Verification ==='
SET search_path TO operational, public;

SELECT loan_id, customer_id, amount, outstanding_balance, status
FROM loans
WHERE loan_id IN (1, 3, 4)
ORDER BY loan_id;

SELECT payment_id, loan_id, amount, payment_method, payment_date
FROM payments
WHERE loan_id = 1
ORDER BY payment_id;

-- =============================================================
-- SECTION 2: DEMONSTRATION — READ COMMITTED (Default Isolation)
-- =============================================================
-- Open two separate psql sessions to postgres-primary.
-- Run the blocks in order as indicated by SESSION A / SESSION B.
-- =============================================================

\echo ''
\echo '=== SECTION 2: READ COMMITTED Isolation Level ==='
\echo 'Session A (run first):'
\echo '  BEGIN;'
\echo '  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;'
\echo '  SELECT amount, outstanding_balance FROM loans WHERE loan_id = 1;'
\echo '  -- (keep transaction open, switch to Session B)'
\echo ''
\echo 'Session B (while Session A is open):'
\echo '  BEGIN;'
\echo '  UPDATE loans SET outstanding_balance = outstanding_balance - 5000 WHERE loan_id = 1;'
\echo '  COMMIT;'
\echo ''
\echo 'Session A (now re-read — will see B''s committed value = non-repeatable read):'
\echo '  SELECT amount, outstanding_balance FROM loans WHERE loan_id = 1;'
\echo '  COMMIT;'

-- BEGIN;
-- SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- SELECT loan_id, amount, outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- <switch to Session B, update and commit>
-- SELECT loan_id, amount, outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- COMMIT;

-- =============================================================
-- SECTION 3: DEMONSTRATION — REPEATABLE READ
-- Prevents non-repeatable reads; allows phantom reads
-- =============================================================
\echo ''
\echo '=== SECTION 3: REPEATABLE READ Isolation Level ==='

-- Session A:
-- BEGIN;
-- SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- SELECT loan_id, amount, outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- <Session B commits an update to loan_id=1>
-- SELECT loan_id, amount, outstanding_balance FROM operational.loans WHERE loan_id = 1;
-- -- Result: SAME value as first read (no non-repeatable read)
-- COMMIT;

-- =============================================================
-- SECTION 4: DEMONSTRATION — SERIALIZABLE
-- Strictest isolation — prevents all anomalies
-- =============================================================
\echo ''
\echo '=== SECTION 4: SERIALIZABLE Isolation Level ==='

-- Session A:
-- BEGIN;
-- SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- SELECT SUM(amount) AS total_unpaid FROM operational.payments WHERE loan_id = 1;
-- <Session B inserts a new payment for loan_id=1 and commits>
-- SELECT SUM(amount) AS total_unpaid FROM operational.payments WHERE loan_id = 1;
-- -- PostgreSQL detects serialization conflict and raises an error on COMMIT
-- COMMIT; -- May raise: ERROR: could not serialize access due to concurrent update

-- =============================================================
-- SECTION 5: ROW-LEVEL LOCKING — SELECT FOR UPDATE
-- =============================================================
\echo ''
\echo '=== SECTION 5: Row-Level Locking (SELECT FOR UPDATE) ==='
\echo ''
\echo 'Session A — acquires row lock:'

-- BEGIN;
-- SELECT loan_id, amount, outstanding_balance
-- FROM operational.loans
-- WHERE loan_id = 1
-- FOR UPDATE;
-- -- Session A holds the lock; Session B will BLOCK if it tries to update.

\echo 'Session B — attempts to modify same row (will BLOCK until A commits/rolls back):'

-- BEGIN;
-- UPDATE operational.loans
-- SET outstanding_balance = outstanding_balance - 1000
-- WHERE loan_id = 1;
-- -- ^^ BLOCKS here waiting for Session A

-- Session A releases:
-- UPDATE operational.loans
-- SET outstanding_balance = outstanding_balance - 5000
-- WHERE loan_id = 1;
-- COMMIT; -- Session B unblocks and proceeds

-- =============================================================
-- SECTION 6: DEADLOCK DEMONSTRATION
-- =============================================================
\echo ''
\echo '=== SECTION 6: Deadlock Demonstration ==='
\echo ''
\echo 'Session A:'
\echo '  BEGIN;'
\echo '  UPDATE operational.loans SET outstanding_balance = outstanding_balance - 500 WHERE loan_id = 1;'
\echo '  -- (do NOT commit yet)'
\echo ''
\echo 'Session B:'
\echo '  BEGIN;'
\echo '  UPDATE operational.loans SET outstanding_balance = outstanding_balance - 200 WHERE loan_id = 3;'
\echo '  UPDATE operational.loans SET outstanding_balance = outstanding_balance - 200 WHERE loan_id = 1; -- BLOCKS'
\echo ''
\echo 'Session A:'
\echo '  UPDATE operational.loans SET outstanding_balance = outstanding_balance - 300 WHERE loan_id = 3; -- DEADLOCK!'
\echo '  -- PostgreSQL detects deadlock and rolls back one transaction automatically.'

-- =============================================================
-- SECTION 7: LIVE DEMO — Concurrent payment processing
-- (Self-contained; run this entire block in ONE session)
-- =============================================================
\echo ''
\echo '=== SECTION 7: Concurrent Payment Processing Simulation ==='

DO $$
DECLARE
    v_loan_id        INT := 1;
    v_payment_amount DECIMAL := 7200.00;
    v_balance        DECIMAL;
    v_new_balance    DECIMAL;
BEGIN
    -- Simulate atomic payment processing with proper locking
    BEGIN
        -- Lock the loan row for update (prevents race conditions)
        SELECT outstanding_balance INTO v_balance
        FROM operational.loans
        WHERE loan_id = v_loan_id
        FOR UPDATE;

        IF v_balance IS NULL THEN
            RAISE EXCEPTION 'Loan % not found', v_loan_id;
        END IF;

        IF v_balance < v_payment_amount THEN
            RAISE NOTICE 'Payment (%) exceeds outstanding balance (%). Adjusting...', v_payment_amount, v_balance;
            v_payment_amount := v_balance;
        END IF;

        v_new_balance := v_balance - v_payment_amount;

        -- Record payment
        INSERT INTO operational.payments
            (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date)
        VALUES
            (v_loan_id, v_payment_amount,
             ROUND(v_payment_amount * 0.75, 2),
             ROUND(v_payment_amount * 0.25, 2),
             'mpesa', 'DEMO_' || EXTRACT(EPOCH FROM NOW())::TEXT, CURRENT_DATE);

        -- Update outstanding balance
        UPDATE operational.loans
        SET outstanding_balance = v_new_balance,
            status = CASE WHEN v_new_balance <= 0 THEN 'repaid' ELSE status END
        WHERE loan_id = v_loan_id;

        RAISE NOTICE 'Payment processed: Loan %, Amount: %, Old Balance: %, New Balance: %',
                     v_loan_id, v_payment_amount, v_balance, v_new_balance;
    END;
END;
$$;

-- Verify result
SELECT loan_id, amount, outstanding_balance, status,
       (SELECT COUNT(*) FROM operational.payments WHERE loan_id = l.loan_id) AS payment_count
FROM operational.loans l WHERE loan_id = 1;

-- =============================================================
-- SECTION 8: ACID VERIFICATION
-- =============================================================
\echo ''
\echo '=== SECTION 8: ACID Properties Verification ==='

-- Atomicity — rollback test
\echo 'Testing Atomicity (rollback aborts all changes):'
BEGIN;
  INSERT INTO operational.payments
      (loan_id, amount, payment_method, payment_date)
  VALUES (1, 999.99, 'cash', CURRENT_DATE);

  -- Simulate error by violating constraint
  INSERT INTO operational.payments
      (loan_id, amount, payment_method, payment_date)
  VALUES (-999, 999.99, 'cash', CURRENT_DATE); -- invalid loan_id -> should fail

ROLLBACK; -- All changes in this block are discarded (Atomicity)

-- Verify no payment was inserted
SELECT COUNT(*) AS payments_for_loan_1
FROM operational.payments WHERE loan_id = 1 AND amount = 999.99;

-- =============================================================
-- SECTION 9: MVCC — Show active transactions
-- =============================================================
\echo ''
\echo '=== SECTION 9: MVCC — Active Transactions & Locks ==='

SELECT
    pid,
    usename,
    application_name,
    state,
    wait_event_type,
    wait_event,
    LEFT(query, 80) AS query_preview,
    now() - xact_start AS transaction_age
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY transaction_age DESC NULLS LAST;

-- Show current locks
SELECT
    l.pid,
    l.relation::regclass AS table_name,
    l.mode,
    l.granted,
    a.state,
    LEFT(a.query, 60) AS query
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.relation IS NOT NULL
ORDER BY l.granted, l.pid;
