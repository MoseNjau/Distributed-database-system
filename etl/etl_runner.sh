#!/bin/bash
# =============================================================
# etl_runner.sh — ETL execution wrapper
# Uses envsubst to inject env vars into SQL template, then runs
# the substituted SQL against the warehouse database.
# =============================================================
set -e

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="/var/log/etl"
LOG_FILE="${LOG_DIR}/etl_$(date '+%Y%m%d').log"

mkdir -p "${LOG_DIR}"
TMP_SQL="/tmp/etl_run_$(date '+%Y%m%d_%H%M%S').sql"

echo "============================================" | tee -a "$LOG_FILE"
echo "[${TIMESTAMP}] ETL Run Starting"             | tee -a "$LOG_FILE"
echo "Source : ${SRC_HOST}:${SRC_PORT}/${SRC_DB}" | tee -a "$LOG_FILE"
echo "Target : ${DST_HOST}:${DST_PORT}/${DST_DB}" | tee -a "$LOG_FILE"
echo "============================================" | tee -a "$LOG_FILE"

# Substitute only the ETL-specific env vars into the SQL template
export SRC_HOST SRC_PORT SRC_DB SRC_USER SRC_PASSWORD
envsubst '${SRC_HOST} ${SRC_PORT} ${SRC_DB} ${SRC_USER} ${SRC_PASSWORD}' \
    < /app/etl_script.sql > "${TMP_SQL}"

export PGPASSWORD="${DST_PASSWORD}"

psql \
    --host="${DST_HOST}" \
    --port="${DST_PORT}" \
    --dbname="${DST_DB}" \
    --username="${DST_USER}" \
    --set=ON_ERROR_STOP=1 \
    --file="${TMP_SQL}" \
    2>&1 | tee -a "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[0]}
rm -f "${TMP_SQL}"

if [ $EXIT_CODE -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ETL Run SUCCEEDED" | tee -a "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ETL Run FAILED (exit $EXIT_CODE)" | tee -a "$LOG_FILE"
fi

echo "============================================" | tee -a "$LOG_FILE"
exit $EXIT_CODE
