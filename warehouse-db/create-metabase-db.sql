-- =============================================================
-- create-metabase-db.sql — Metabase Metadata Database
-- Runs on warehouse-db after warehouse_init.sql
-- =============================================================

CREATE DATABASE metabase_db WITH
    OWNER = warehouse_user
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

-- Grant the warehouse_user (which Metabase uses) full access
GRANT ALL PRIVILEGES ON DATABASE metabase_db TO warehouse_user;

-- Metabase needs a user to own its schema — reuse warehouse_user:
-- (created in the parent postgres container startup with POSTGRES_USER=warehouse_user)
