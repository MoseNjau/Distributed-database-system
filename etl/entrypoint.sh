#!/bin/bash
# =============================================================
# entrypoint.sh — ETL Container Entrypoint
# Sets up environment for cron, writes crontab, starts cron
# =============================================================
set -e

ETL_SCHEDULE="${ETL_SCHEDULE:-*/15 * * * *}"
LOG_FILE="/var/log/etl/cron.log"

echo "============================================"
echo " ETL Container Starting"
echo " Schedule: ${ETL_SCHEDULE}"
echo " Source  : ${SRC_HOST}:${SRC_PORT}/${SRC_DB}"
echo " Dest    : ${DST_HOST}:${DST_PORT}/${DST_DB}"
echo "============================================"

# ── Write environment to a file cron can source ──────────────
# Cron does not inherit shell env, so we persist it explicitly
cat > /etc/etl_env.sh <<EOF
export SRC_HOST="${SRC_HOST}"
export SRC_PORT="${SRC_PORT}"
export SRC_DB="${SRC_DB}"
export SRC_USER="${SRC_USER}"
export SRC_PASSWORD="${SRC_PASSWORD}"
export DST_HOST="${DST_HOST}"
export DST_PORT="${DST_PORT}"
export DST_DB="${DST_DB}"
export DST_USER="${DST_USER}"
export DST_PASSWORD="${DST_PASSWORD}"
export PGPASSWORD="${DST_PASSWORD}"
EOF
chmod 600 /etc/etl_env.sh

# ── Write crontab ─────────────────────────────────────────────
CRON_CMD="source /etc/etl_env.sh && /app/etl_runner.sh >> /var/log/etl/cron.log 2>&1"
echo "${ETL_SCHEDULE} root bash -c '${CRON_CMD}'" > /etc/cron.d/etl_cron
chmod 0644 /etc/cron.d/etl_cron
crontab /etc/cron.d/etl_cron

# ── Run an immediate ETL on container startup ─────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running initial ETL on startup..." | tee -a "$LOG_FILE"
source /etc/etl_env.sh

# Wait for both databases to be ready before the first run
wait_for_db() {
    local host=$1 port=$2 user=$3 db=$4
    echo "Waiting for ${host}:${port}..."
    until pg_isready -h "$host" -p "$port" -U "$user" -d "$db" -q; do
        sleep 3
    done
    echo "${host} is ready."
}

export PGPASSWORD="${SRC_PASSWORD}"
wait_for_db "${SRC_HOST}" "${SRC_PORT}" "${SRC_USER}" "${SRC_DB}"

export PGPASSWORD="${DST_PASSWORD}"
wait_for_db "${DST_HOST}" "${DST_PORT}" "${DST_USER}" "${DST_DB}"

# Give the warehouse DB a few extra seconds for its init scripts to complete
sleep 10

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initial ETL starting..." | tee -a "$LOG_FILE"
/app/etl_runner.sh || echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initial ETL failed — will retry on next cron cycle." | tee -a "$LOG_FILE"

# ── Start cron daemon ─────────────────────────────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting cron daemon..."
service cron start

# ── Tail log to keep container alive and visible ─────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ETL scheduler running. Tailing logs..."
tail -f "$LOG_FILE"
