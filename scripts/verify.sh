#!/bin/bash
# =============================================================
# verify.sh — Enterprise Data Platform Full Verification Script
# Runs all system checks: replication, ETL, warehouse, OLAP
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

set -a
source "${PROJECT_DIR}/.env" 2>/dev/null || true
set +a

# ── Colours ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0

info()  { echo -e "${CYAN}[INFO ]${NC} $*"; }
ok()    { echo -e "${GREEN}[PASS ]${NC} $*"; ((PASS++)); }
fail()  { echo -e "${RED}[FAIL ]${NC} $*"; ((FAIL++)); }
header(){ echo -e "\n${BOLD}${YELLOW}━━━ $* ━━━${NC}"; }

run_sql_primary() {
    docker exec eds_postgres_primary \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tAc \"$1\""
}

run_sql_replica1() {
    docker exec eds_postgres_replica1 \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tAc \"$1\""
}

run_sql_warehouse() {
    docker exec eds_warehouse_db \
        bash -c "PGPASSWORD='${WAREHOUSE_PASSWORD}' psql -U ${WAREHOUSE_USER} -d ${WAREHOUSE_DB} -tAc \"$1\""
}

# =============================================================
header "TEST 1: Container Health"
# =============================================================
for container in eds_postgres_primary eds_postgres_replica1 eds_postgres_replica2 \
                  eds_warehouse_db eds_etl_pipeline eds_metabase eds_pgadmin eds_pgbouncer; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
    if [ "$STATUS" == "running" ]; then
        ok "$container is running"
    else
        fail "$container is $STATUS"
    fi
done

# =============================================================
header "TEST 2: Primary DB — OLTP Schema"
# =============================================================
CUST_COUNT=$(run_sql_primary "SELECT COUNT(*) FROM operational.customers;" 2>/dev/null || echo "0")
LOAN_COUNT=$(run_sql_primary "SELECT COUNT(*) FROM operational.loans;" 2>/dev/null || echo "0")
PAY_COUNT=$(run_sql_primary "SELECT COUNT(*) FROM operational.payments;" 2>/dev/null || echo "0")

info "Customers: $CUST_COUNT | Loans: $LOAN_COUNT | Payments: $PAY_COUNT"
[ "$CUST_COUNT" -gt 0 ] && ok "Customers table populated" || fail "Customers table empty"
[ "$LOAN_COUNT" -gt 0 ] && ok "Loans table populated"     || fail "Loans table empty"
[ "$PAY_COUNT"  -gt 0 ] && ok "Payments table populated"  || fail "Payments table empty"

# =============================================================
header "TEST 3: Replication — Primary Write, Replica Read"
# =============================================================

# Primary should accept writes
WRITE_TEST=$(run_sql_primary "
  INSERT INTO operational.customers (full_name, email, phone, segment)
  VALUES ('Verify Test User', 'verify.test@enterprise.local', '+254700999999', 'retail')
  RETURNING customer_id;" 2>/dev/null || echo "FAIL")

if echo "$WRITE_TEST" | grep -qE '^[0-9]+$'; then
    ok "Primary accepts writes (new customer_id: $WRITE_TEST)"
    TEST_CUSTOMER_ID="$WRITE_TEST"

    # Cleanup
    run_sql_primary "DELETE FROM operational.customers WHERE email='verify.test@enterprise.local';" >/dev/null
else
    fail "Primary write failed: $WRITE_TEST"
    TEST_CUSTOMER_ID=""
fi

# Replica 1 should be read-only
REPLICA1_READONLY=$(docker exec eds_postgres_replica1 \
    bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tAc \
    \"SELECT pg_is_in_recovery();\"" 2>/dev/null || echo "error")
[ "$REPLICA1_READONLY" == "t" ] && ok "Replica 1 is in recovery (read-only)" || fail "Replica 1 NOT in recovery mode"

REPLICA2_READONLY=$(docker exec eds_postgres_replica2 \
    bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tAc \
    \"SELECT pg_is_in_recovery();\"" 2>/dev/null || echo "error")
[ "$REPLICA2_READONLY" == "t" ] && ok "Replica 2 is in recovery (read-only)" || fail "Replica 2 NOT in recovery mode"

# Replication lag check
REPLICA1_LAG=$(docker exec eds_postgres_replica1 \
    bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tAc \
    \"SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT;\"" 2>/dev/null || echo "N/A")
info "Replica 1 lag: ${REPLICA1_LAG}s"

# Stats from primary
REPL_STAT=$(run_sql_primary "SELECT COUNT(*) FROM pg_stat_replication;" 2>/dev/null || echo "0")
info "Active replication connections to primary: $REPL_STAT"
[ "$REPL_STAT" -ge 1 ] && ok "At least 1 replica streaming from primary" || fail "No replicas connected"

# =============================================================
header "TEST 4: Replica Write Rejection"
# =============================================================
WRITE_REJECT=$(docker exec eds_postgres_replica1 \
    bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c \
    \"INSERT INTO operational.customers (full_name, email, segment) VALUES ('Bad', 'bad@test.com', 'retail');\"" \
    2>&1 || true)

if echo "$WRITE_REJECT" | grep -qi "read-only\|cannot\|standby"; then
    ok "Replica 1 correctly rejects writes"
else
    fail "Replica 1 did not reject write: $WRITE_REJECT"
fi

# =============================================================
header "TEST 5: Data Warehouse — Star Schema"
# =============================================================
DIM_CUST=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.dim_customer;" 2>/dev/null || echo "0")
DIM_LOAN=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.dim_loan;" 2>/dev/null || echo "0")
FACT_PAY=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.fact_payments;" 2>/dev/null || echo "0")
FACT_LOA=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.fact_loans;" 2>/dev/null || echo "0")
DIM_DATE=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.dim_date;" 2>/dev/null || echo "0")

info "dim_customer: $DIM_CUST | dim_loan: $DIM_LOAN | fact_payments: $FACT_PAY | fact_loans: $FACT_LOA | dim_date: $DIM_DATE"
[ "$DIM_CUST" -gt 0 ] && ok "dim_customer populated by ETL" || fail "dim_customer empty (ETL may not have run yet)"
[ "$DIM_LOAN" -gt 0 ] && ok "dim_loan populated by ETL"     || fail "dim_loan empty"
[ "$FACT_PAY" -gt 0 ] && ok "fact_payments populated"       || fail "fact_payments empty"
[ "$FACT_LOA" -gt 0 ] && ok "fact_loans populated"          || fail "fact_loans empty"
[ "$DIM_DATE" -gt 10000 ] && ok "dim_date pre-populated (${DIM_DATE} rows)" || fail "dim_date not populated"

# =============================================================
header "TEST 6: OLAP Analytical Views"
# =============================================================
REV=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.vw_monthly_revenue;" 2>/dev/null || echo "0")
TOP=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.vw_top_customers;" 2>/dev/null || echo "0")
DIST=$(run_sql_warehouse "SELECT COUNT(*) FROM warehouse.vw_loan_status_distribution;" 2>/dev/null || echo "0")

[ "$REV" -gt 0 ] && ok "vw_monthly_revenue returns $REV rows"       || fail "vw_monthly_revenue is empty"
[ "$TOP" -gt 0 ] && ok "vw_top_customers returns $TOP rows"          || fail "vw_top_customers is empty"
[ "$DIST" -gt 0 ] && ok "vw_loan_status_distribution returns $DIST rows" || fail "vw_loan_status_distribution is empty"

# =============================================================
header "TEST 7: ETL Run History"
# =============================================================
ETL_RUNS=$(run_sql_warehouse "SELECT COUNT(*) FROM audit.etl_runs;" 2>/dev/null || echo "0")
ETL_OK=$(run_sql_warehouse "SELECT COUNT(*) FROM audit.etl_runs WHERE status='success';" 2>/dev/null || echo "0")
[ "$ETL_RUNS" -gt 0 ] && ok "ETL has executed ($ETL_RUNS runs, $ETL_OK successful)" || fail "No ETL runs recorded"

# =============================================================
header "TEST 8: Metabase Health"
# =============================================================
MB_STATUS=$(curl -sf http://localhost:3000/api/health 2>/dev/null || echo "unavailable")
if echo "$MB_STATUS" | grep -qi "ok\|healthy\|true"; then
    ok "Metabase API is healthy"
else
    fail "Metabase not responding: $MB_STATUS"
fi

# =============================================================
header "TEST 9: WAL Archiving"
# =============================================================
ARCH_COUNT=$(run_sql_primary "SELECT archived_count FROM pg_stat_archiver;" 2>/dev/null || echo "0")
info "WAL segments archived: $ARCH_COUNT"
[ "$ARCH_COUNT" -gt 0 ] && ok "WAL archiving active ($ARCH_COUNT segments)" || \
    info "WAL archives: 0 segments yet (normal for fresh start)"

# =============================================================
header "TEST 10: Backup Mechanism"
# =============================================================
if command -v docker &>/dev/null; then
    # Quick pg_dump test (output suppressed, just test it works)
    DUMP_TEST=$(docker exec eds_postgres_primary \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump \
                    -U ${POSTGRES_USER} -d ${POSTGRES_DB} \
                    --schema=operational --table=operational.customers \
                    --schema-only 2>&1" | wc -l || echo "0")
    [ "$DUMP_TEST" -gt 5 ] && ok "pg_dump executed successfully (${DUMP_TEST} lines)" || fail "pg_dump failed"
else
    fail "Docker not available for backup test"
fi

# =============================================================
header "RESULTS SUMMARY"
# =============================================================
TOTAL=$((PASS + FAIL))
echo ""
echo -e "${BOLD}Tests Passed : ${GREEN}${PASS}${NC}"
echo -e "${BOLD}Tests Failed : ${RED}${FAIL}${NC}"
echo -e "${BOLD}Total        : ${TOTAL}${NC}"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅  All tests passed — Enterprise Data Platform is operational!${NC}"
    exit 0
else
    echo -e "${YELLOW}${BOLD}⚠️   $FAIL test(s) failed. Check logs above for details.${NC}"
    exit 1
fi
