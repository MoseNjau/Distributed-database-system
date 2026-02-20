#!/bin/bash
# =============================================================
# setup-replication.sh — Runs inside postgres-primary initdb
# Creates replication user and physical replication slots
# =============================================================

set -e

echo ">>> [REPLICATION] Creating replication role and slots..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL

    -- ── Replication role ──────────────────────────────────────
    DO \$\$
    BEGIN
        IF NOT EXISTS (
            SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator'
        ) THEN
            CREATE ROLE replicator
                WITH REPLICATION
                     LOGIN
                     PASSWORD '${REPLICATION_PASSWORD}';
            RAISE NOTICE 'Replication role created.';
        ELSE
            RAISE NOTICE 'Replication role already exists — skipping.';
        END IF;
    END
    \$\$;

    -- ── Physical replication slots (one per replica) ─────────
    DO \$\$
    BEGIN
        IF NOT EXISTS (
            SELECT FROM pg_replication_slots WHERE slot_name = 'replica1_slot'
        ) THEN
            PERFORM pg_create_physical_replication_slot('replica1_slot');
            RAISE NOTICE 'Replication slot replica1_slot created.';
        END IF;

        IF NOT EXISTS (
            SELECT FROM pg_replication_slots WHERE slot_name = 'replica2_slot'
        ) THEN
            PERFORM pg_create_physical_replication_slot('replica2_slot');
            RAISE NOTICE 'Replication slot replica2_slot created.';
        END IF;
    END
    \$\$;

EOSQL

echo ">>> [REPLICATION] Setup complete."
