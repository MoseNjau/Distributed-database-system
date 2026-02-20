# =============================================================
# Makefile — Enterprise Data Platform Operations
# =============================================================

.PHONY: help up down restart build logs ps \
        backup restore health verify etl \
        psql-primary psql-replica1 psql-replica2 psql-warehouse \
        concurrency replication clean nuke

PROJECT=enterprise-data-system
COMPOSE=docker compose --env-file .env

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ─────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────
up: ## Start all services (detached)
	$(COMPOSE) up -d --build
	@echo ""
	@echo "Services starting. Run 'make logs' to monitor."
	@echo "Replica bootstrap takes ~60s. Run 'make health' after."

down: ## Stop all services
	$(COMPOSE) down

restart: ## Restart all services
	$(COMPOSE) restart

build: ## Rebuild all images
	$(COMPOSE) build --no-cache

logs: ## Tail logs for all services
	$(COMPOSE) logs -f

ps: ## Show container status
	$(COMPOSE) ps

# ─────────────────────────────────────────────────────────────
# psql Shortcuts
# ─────────────────────────────────────────────────────────────
psql-primary: ## Connect to primary DB (psql)
	docker exec -it eds_postgres_primary \
		bash -c "PGPASSWORD=$$POSTGRES_PASSWORD psql -U $$POSTGRES_USER -d $$POSTGRES_DB"

psql-replica1: ## Connect to replica 1 (read-only)
	docker exec -it eds_postgres_replica1 \
		bash -c "PGPASSWORD=$$POSTGRES_PASSWORD psql -U $$POSTGRES_USER -d $$POSTGRES_DB"

psql-replica2: ## Connect to replica 2 (read-only)
	docker exec -it eds_postgres_replica2 \
		bash -c "PGPASSWORD=$$POSTGRES_PASSWORD psql -U $$POSTGRES_USER -d $$POSTGRES_DB"

psql-warehouse: ## Connect to warehouse DB (psql)
	docker exec -it eds_warehouse_db \
		bash -c "PGPASSWORD=$$WAREHOUSE_PASSWORD psql -U $$WAREHOUSE_USER -d $$WAREHOUSE_DB"

# Host-port shortcuts (useful when accessing from host scripts)
# Primary   : localhost:5440
# Replica 1 : localhost:5441
# Replica 2 : localhost:5442
# Warehouse : localhost:5435
# PgBouncer : localhost:6433
# Metabase  : http://localhost:3000
# pgAdmin   : http://localhost:5050

# ─────────────────────────────────────────────────────────────
# Operations
# ─────────────────────────────────────────────────────────────
health: ## Full system health check
	@bash backups/backup.sh health

backup: ## Backup all databases
	@bash backups/backup.sh backup all

restore: ## Restore operational DB (pass FILE=<path>)
	@bash backups/backup.sh restore $(FILE)

verify: ## Run full verification test suite
	@bash scripts/verify.sh

replication: ## Check replication status
	@bash backups/backup.sh replication

etl: ## Check ETL run history
	@bash backups/backup.sh etl

concurrency: ## Run concurrency demo on primary
	docker exec -it eds_postgres_primary \
		bash -c "PGPASSWORD=$$POSTGRES_PASSWORD psql -U $$POSTGRES_USER -d $$POSTGRES_DB \
		-f /dev/stdin" < concurrency/concurrency_demo.sql

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
clean: ## Stop and remove containers (keep volumes)
	$(COMPOSE) down --remove-orphans

nuke: ## ⚠️ Destroy everything including volumes
	@echo "WARNING: This permanently deletes all data!"
	@read -p "Type 'destroy' to confirm: " c; [ "$$c" = "destroy" ] || exit 1
	$(COMPOSE) down -v --remove-orphans
	docker volume ls | grep 'eds_' | awk '{print $$2}' | xargs -r docker volume rm
	@echo "All containers and volumes removed."
