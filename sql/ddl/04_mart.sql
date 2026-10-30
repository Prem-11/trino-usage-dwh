-- =====================================================================
-- MART LAYER: daily aggregates for dashboards and trends.
-- WARNING: distinct_* columns are per day and must NOT be summed across days.
-- =====================================================================

-- Grain: 1 row per table x day. Built from core.fact_query_table_access.
CREATE TABLE IF NOT EXISTS mart.agg_table_usage_daily (
    usage_date             DATE    NOT NULL,
    table_id               VARCHAR NOT NULL,
    query_count            BIGINT  NOT NULL,
    distinct_users         BIGINT  NOT NULL,
    distinct_teams         BIGINT  NOT NULL,
    bytes_read             BIGINT  NOT NULL,
    cpu_time_allocated_ms  DOUBLE  NOT NULL,
    PRIMARY KEY (usage_date, table_id)
);

-- Grain: 1 row per team x day. Built from core.fact_query (no double counting).
CREATE TABLE IF NOT EXISTS mart.agg_team_usage_daily (
    usage_date                DATE    NOT NULL,
    team_id                   VARCHAR NOT NULL,
    query_count               BIGINT  NOT NULL,
    failed_query_count        BIGINT  NOT NULL,
    distinct_users            BIGINT  NOT NULL,
    cpu_time_ms               BIGINT  NOT NULL,
    bytes_read                BIGINT  NOT NULL,
    cumulative_memory_gb_sec  DOUBLE  NOT NULL,
    PRIMARY KEY (usage_date, team_id)
);