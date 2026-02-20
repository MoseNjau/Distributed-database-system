#!/bin/bash
# =============================================================
# backup.sh — Enterprise Backup & Recovery Script
# Supports: logical backup (pg_dump), restore (psql), status
# Usage from host machine (calls into Docker containers)
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${SCRIPT_DIR}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Load environment variables
if [ -f "${PROJECT_DIR}/.env" ]; then
    set -a
    source "${PROJECT_DIR}/.env"
    set +a
fi

# Defaults
PRIMARY_CONTAINER="eds_postgres_primary"
WAREHOUSE_CONTAINER="eds_warehouse_db"
DB_NAME="${POSTGRES_DB:-loans_db}"
DB_USER="${POSTGRES_USER:-postgres}"
WAREHOUSE_DB="${WAREHOUSE_DB:-warehouse_db}"
WAREHOUSE_USER="${WAREHOUSE_USER:-warehouse_user}"

# ── Colour output ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO ]${NC} $*"; }
success() { echo -e "${GREEN}[OK   ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN ]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================
# FUNCTION: Logical Backup (pg_dump)
# =============================================================
backup_logical() {
    local target="${1:-operational}"     # operational | warehouse | all
    mkdir -p "${BACKUP_DIR}"

    if [[ "$target" == "operational" || "$target" == "all" ]]; then
        local out="${BACKUP_DIR}/backup_operational_${TIMESTAMP}.sql.gz"
        info "Starting logical backup of ${DB_NAME} → ${out}"

        docker exec "${PRIMARY_CONTAINER}" \
            bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump \
                        --username=${DB_USER} \
                        --dbname=${DB_NAME} \
                        --format=plain \
                        --clean \
                        --if-exists \
                        --schema=operational \
                        --verbose" \
        | gzip > "${out}"

        success "Operational backup complete: ${out} ($(du -sh "${out}" | cut -f1))"
    fi

    if [[ "$target" == "warehouse" || "$target" == "all" ]]; then
        local out="${BACKUP_DIR}/backup_warehouse_${TIMESTAMP}.sql.gz"
        info "Starting logical backup of ${WAREHOUSE_DB} → ${out}"

        docker exec "${WAREHOUSE_CONTAINER}" \
            bash -c "PGPASSWORD='${WAREHOUSE_PASSWORD}' pg_dump \
                        --username=${WAREHOUSE_USER} \
                        --dbname=${WAREHOUSE_DB} \
                        --format=plain \
                        --clean \
                        --if-exists \
                        --verbose" \
        | gzip > "${out}"

        success "Warehouse backup complete: ${out} ($(du -sh "${out}" | cut -f1))"
    fi
}

# =============================================================
# FUNCTION: Custom-format backup (pg_dump -Fc — smallest, fastest restore)
# =============================================================
backup_custom_format() {
    mkdir -p "${BACKUP_DIR}"
    local out="${BACKUP_DIR}/backup_operational_${TIMESTAMP}.dump"
    info "Creating custom-format backup → ${out}"

    docker exec "${PRIMARY_CONTAINER}" \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump \
                    --username=${DB_USER} \
                    --dbname=${DB_NAME} \
                    --format=custom \
                    --compress=9" \
    > "${out}"

    success "Custom backup: ${out} ($(du -sh "${out}" | cut -f1))"
}

# =============================================================
# FUNCTION: Restore from logical backup
# =============================================================
restore_operational() {
    local backup_file="${1:-}"
    if [ -z "$backup_file" ]; then
        error "Usage: $0 restore <backup_file.sql.gz>"
        exit 1
    fi
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        exit 1
    fi

    warn "⚠️  This will overwrite data in ${DB_NAME} on ${PRIMARY_CONTAINER}!"
    read -rp "Type 'yes' to confirm: " confirm
    [[ "$confirm" == "yes" ]] || { info "Restore cancelled."; exit 0; }

    info "Restoring ${backup_file} → ${DB_NAME}..."
    gunzip -c "${backup_file}" | docker exec -i "${PRIMARY_CONTAINER}" \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql \
                    --username=${DB_USER} \
                    --dbname=${DB_NAME} \
                    --set=ON_ERROR_STOP=1"

    success "Restore complete."
}

# =============================================================
# FUNCTION: List existing backups
# =============================================================
list_backups() {
    info "Backups in ${BACKUP_DIR}:"
    if ls "${BACKUP_DIR}"/*.sql.gz "${BACKUP_DIR}"/*.dump 2>/dev/null | head -50; then
        echo ""
        info "Total backup size: $(du -sh "${BACKUP_DIR}" | cut -f1)"
    else
        warn "No backup files found."
    fi
}

# =============================================================
# FUNCTION: Verify replication status
# =============================================================
check_replication() {
    info "Replication status on primary:"
    docker exec "${PRIMARY_CONTAINER}" \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql \
                    --username=${DB_USER} \
                    --dbname=${DB_NAME} \
                    --command=\"SELECT application_name, client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state FROM pg_stat_replication;\""

    info "Replication lag (replica 1):"
    docker exec eds_postgres_replica1 \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql \
                    --username=${DB_USER} \
                    --dbname=${DB_NAME} \
                    --command=\"SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;\"" 2>/dev/null || \
        warn "Replica 1 not available."

    info "Replication lag (replica 2):"
    docker exec eds_postgres_replica2 \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql \
                    --username=${DB_USER} \
                    --dbname=${DB_NAME} \
                    --command=\"SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;\"" 2>/dev/null || \
        warn "Replica 2 not available."
}

# =============================================================
# FUNCTION: WAL archive status
# =============================================================
check_wal_archive() {
    info "WAL archiving status:"
    docker exec "${PRIMARY_CONTAINER}" \
        bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql \
                    --username=${DB_USER} \
                    --dbname=${DB_NAME} \
                    --command=\"SELECT archived_count, last_archived_wal, last_archived_time, failed_count, last_failed_wal FROM pg_stat_archiver;\""
}

# =============================================================
# FUNCTION: ETL run history
# =============================================================
etl_history() {
    info "Recent ETL runs:"
    docker exec "${WAREHOUSE_CONTAINER}" \
        bash -c "PGPASSWORD='${WAREHOUSE_PASSWORD}' psql \
                    --username=${WAREHOUSE_USER} \
                    --dbname=${WAREHOUSE_DB} \
                    --command=\"SELECT run_id, run_started_at, run_finished_at, rows_inserted, rows_updated, status, LEFT(error_message,80) AS error FROM audit.etl_runs ORDER BY run_id DESC LIMIT 10;\""
}

# =============================================================
# FUNCTION: System health check
# =============================================================
health_check() {
    info "=== Enterprise Data Platform — Health Check ==="
    echo ""

    local services=("eds_postgres_primary" "eds_postgres_replica1" "eds_postgres_replica2" "eds_warehouse_db" "eds_etl_pipeline" "eds_metabase" "eds_pgadmin" "eds_pgbouncer")

    for svc in "${services[@]}"; do
        if docker inspect "$svc" &>/dev/null; then
            STATUS=$(docker inspect --format='{{.State.Status}}' "$svc")
            HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$svc")
            if [ "$STATUS" == "running" ]; then
                success "$svc → running (health: $HEALTH)"
            else
                error "$svc → $STATUS"
            fi
        else
            warn "$svc → not found"
        fi
    done

    echo ""
    check_replication
}

# =============================================================
# MAIN — Argument dispatcher
# =============================================================
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  backup [operational|warehouse|all]  — Logical pg_dump backup"
    echo "  backup-custom                        — Custom-format pg_dump"
    echo "  restore <file.sql.gz>               — Restore operational DB"
    echo "  list                                 — List backup files"
    echo "  replication                          — Check replication status"
    echo "  wal                                  — WAL archive status"
    echo "  etl                                  — ETL run history"
    echo "  health                               — Full system health check"
    echo ""
}

case "${1:-help}" in
    backup)         backup_logical "${2:-all}" ;;
    backup-custom)  backup_custom_format ;;
    restore)        restore_operational "${2:-}" ;;
    list)           list_backups ;;
    replication)    check_replication ;;
    wal)            check_wal_archive ;;
    etl)            etl_history ;;
    health)         health_check ;;
    *)              usage ;;
esac
