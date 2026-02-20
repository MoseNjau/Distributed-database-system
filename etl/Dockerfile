# =============================================================
# ETL Pipeline Container
# Base: postgres:15 (has psql client + pg utilities built in)
# Adds: cron daemon for scheduling ETL runs
# =============================================================
FROM postgres:15

LABEL maintainer="Enterprise Data Platform"
LABEL description="ETL Pipeline — extracts from OLTP, loads into warehouse"

# Install cron and envsubst (gettext-base)
RUN apt-get update && \
    apt-get install -y --no-install-recommends cron gettext-base && \
    rm -rf /var/lib/apt/lists/*

# Create app directory and log directory
RUN mkdir -p /app /var/log/etl

# Copy ETL scripts (also mounted as volumes — these are fallbacks)
COPY etl_script.sql  /app/etl_script.sql
COPY etl_runner.sh   /app/etl_runner.sh
COPY entrypoint.sh   /entrypoint.sh

# Make scripts executable
RUN chmod +x /app/etl_runner.sh /entrypoint.sh

# Entrypoint writes the crontab and starts cron + keeps container alive
ENTRYPOINT ["/entrypoint.sh"]
