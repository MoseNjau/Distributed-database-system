#!/bin/bash
# =============================================================
# setup-replica.sh — PostgreSQL 15 Streaming Replica Bootstrap
# =============================================================
set -e

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
PRIMARY_HOST="${PRIMARY_HOST:-postgres-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICATION_USER="${REPLICATION_USER:-replicator}"
REPLICATION_SLOT="${REPLICATION_SLOT:-replica_slot}"
REPLICATION_PASSWORD="${REPLICATION_PASSWORD}"

echo "============================================================"
echo " PostgreSQL 15 Streaming Replica"
echo " Primary : ${PRIMARY_HOST}:${PRIMARY_PORT}  Slot: ${REPLICATION_SLOT}"
echo "============================================================"

# Wait for primary
wait_for_primary() {
    export PGPASSWORD="${REPLICATION_PASSWORD}"
    local i=0
    until pg_isready -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U "${REPLICATION_USER}" -q; do
        i=$((i+1)); [ $i -ge 60 ] && { echo "Primary timeout"; exit 1; }
        echo "  Waiting for primary... ($i/60)"; sleep 3
    done
    echo ">>> Primary ready."
}

# Write required overrides to postgresql.auto.conf
write_standby_conf() {
    cat >> "${PGDATA}/postgresql.auto.conf" << EOF

# ── Replica overrides (must be >= primary values) ──────────
max_connections = 200
hot_standby = on
hot_standby_feedback = on
primary_slot_name = '${REPLICATION_SLOT}'
max_standby_streaming_delay = 30s
wal_receiver_timeout = 60s
EOF
    chown postgres:postgres "${PGDATA}/postgresql.auto.conf"
}

if [ -f "${PGDATA}/PG_VERSION" ]; then
    echo ">>> PGDATA exists — ensuring standby config is correct..."
    # Ensure max_connections is set; add if not present
    if ! grep -q "max_connections" "${PGDATA}/postgresql.auto.conf" 2>/dev/null; then
        write_standby_conf
    fi
else
    wait_for_primary

    echo ">>> Clearing PGDATA..."
    mkdir -p "${PGDATA}"
    find "${PGDATA}" -mindepth 1 -delete 2>/dev/null || true
    chown -R postgres:postgres "${PGDATA}"
    chmod 700 "${PGDATA}"

    echo ">>> Running pg_basebackup..."
    export PGPASSWORD="${REPLICATION_PASSWORD}"
    gosu postgres pg_basebackup \
        --host="${PRIMARY_HOST}" \
        --port="${PRIMARY_PORT}" \
        --username="${REPLICATION_USER}" \
        --pgdata="${PGDATA}" \
        --wal-method=stream \
        --slot="${REPLICATION_SLOT}" \
        --checkpoint=fast \
        --progress \
        --verbose \
        -R

    echo ">>> Basebackup done. Writing standby config..."
    write_standby_conf
fi

# Ensure standby.signal exists
gosu postgres touch "${PGDATA}/standby.signal"

echo ">>> Starting standby..."
exec gosu postgres postgres -D "${PGDATA}"
