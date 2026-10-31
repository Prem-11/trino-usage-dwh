-- Daily usage per table, built from core.fact_query_table_access.

DELETE FROM mart.agg_table_usage_daily
WHERE usage_date BETWEEN DATE '{start_date}' AND DATE '{end_date}';

INSERT INTO mart.agg_table_usage_daily
SELECT
    query_date                  AS usage_date,
    table_id,
    COUNT(*)                    AS query_count,      -- 1 row = 1 query on this table
    COUNT(DISTINCT user_name)   AS distinct_users,   -- per day only, do not sum
    COUNT(DISTINCT team_id)     AS distinct_teams,   -- per day only, do not sum
    SUM(bytes_read)             AS bytes_read,
    SUM(cpu_time_allocated_ms)  AS cpu_time_allocated_ms
FROM core.fact_query_table_access
WHERE query_date BETWEEN DATE '{start_date}' AND DATE '{end_date}'
GROUP BY query_date, table_id;