-- Daily resource usage per team, built from core.fact_query
-- (1 row per query, so no double counting of multi-table queries).

DELETE FROM mart.agg_team_usage_daily
WHERE usage_date BETWEEN DATE '{start_date}' AND DATE '{end_date}';

INSERT INTO mart.agg_team_usage_daily
SELECT
    query_date                              AS usage_date,
    team_id,
    COUNT(*)                                AS query_count,
    COUNT_IF(query_state = 'FAILED')        AS failed_query_count,
    COUNT(DISTINCT user_name)               AS distinct_users,   -- per day only, do not sum
    SUM(cpu_time_ms)                        AS cpu_time_ms,
    SUM(physical_input_bytes)               AS bytes_read,
    SUM(cumulative_memory_gb_sec)           AS cumulative_memory_gb_sec
FROM core.fact_query
WHERE query_date BETWEEN DATE '{start_date}' AND DATE '{end_date}'
GROUP BY query_date, team_id;