-- =====================================================================
-- CORE LAYER: clean facts and dimensions.
-- =====================================================================

-- ---------- DIMENSIONS ----------

-- Grain: 1 row per team. Includes a special 'unassigned' team.
CREATE TABLE IF NOT EXISTS core.dim_team (
    team_id      VARCHAR PRIMARY KEY,
    team_name    VARCHAR NOT NULL,
    department   VARCHAR
);

-- Grain: 1 row per user known to HR/LDAP.
CREATE TABLE IF NOT EXISTS core.dim_user (
    user_name           VARCHAR PRIMARY KEY,
    email               VARCHAR,
    is_service_account  BOOLEAN NOT NULL
);

-- Grain: 1 row per user x team x validity period (SCD Type 2).
-- valid_to NULL = current membership.
CREATE TABLE IF NOT EXISTS core.bridge_user_team (
    user_name   VARCHAR NOT NULL,
    team_id     VARCHAR NOT NULL,
    valid_from  DATE    NOT NULL,
    valid_to    DATE,
    PRIMARY KEY (user_name, valid_from)
);

-- Grain: 1 row per Iceberg table.
CREATE TABLE IF NOT EXISTS core.dim_table (
    table_id       VARCHAR PRIMARY KEY,   -- catalog.schema.table
    catalog        VARCHAR NOT NULL,
    schema_name    VARCHAR NOT NULL,
    table_name     VARCHAR NOT NULL,
    owner_team_id  VARCHAR,
    description    VARCHAR,
    created_date   DATE
);

-- ---------- FACTS ----------

-- Grain: 1 row per query (deduplicated by query_id).
-- team_id = user's team ON query_date (resolved at load time).
-- Production (Trino/Iceberg): WITH (partitioning = ARRAY['query_date'])
CREATE TABLE IF NOT EXISTS core.fact_query (
    query_id                  VARCHAR PRIMARY KEY,
    query_date                DATE      NOT NULL,   -- date of end_time (UTC)
    user_name                 VARCHAR   NOT NULL,
    team_id                   VARCHAR   NOT NULL,
    source                    VARCHAR,
    query_state               VARCHAR   NOT NULL,   -- FINISHED / FAILED
    error_code                VARCHAR,              -- NULL if finished
    start_time                TIMESTAMP NOT NULL,
    end_time                  TIMESTAMP NOT NULL,
    cpu_time_ms               BIGINT    NOT NULL,
    wall_time_ms              BIGINT    NOT NULL,
    queued_time_ms            BIGINT    NOT NULL,
    peak_memory_bytes         BIGINT    NOT NULL,
    cumulative_memory_gb_sec  DOUBLE    NOT NULL,
    physical_input_bytes      BIGINT    NOT NULL,
    tables_read_count         INTEGER   NOT NULL
);

-- Grain: 1 row per query x table read. System tables excluded.
-- CPU is split by bytes_share, so SUM(cpu_time_allocated_ms) per query = query CPU.
-- Production (Trino/Iceberg): WITH (partitioning = ARRAY['query_date'])
CREATE TABLE IF NOT EXISTS core.fact_query_table_access (
    query_id               VARCHAR NOT NULL,
    table_id               VARCHAR NOT NULL,
    query_date             DATE    NOT NULL,
    user_name              VARCHAR NOT NULL,
    team_id                VARCHAR NOT NULL,
    bytes_read             BIGINT  NOT NULL,
    columns_read_count     INTEGER NOT NULL,
    bytes_share            DOUBLE  NOT NULL,   -- 0..1
    cpu_time_allocated_ms  DOUBLE  NOT NULL,
    PRIMARY KEY (query_id, table_id)
);