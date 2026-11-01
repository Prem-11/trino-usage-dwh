-- Which teams use the most cluster resources this month, and what share of the total?

SELECT
    team_id,
    SUM(query_count)                                                 AS queries,
    ROUND(SUM(cpu_time_ms) / 3600000.0, 2)                           AS cpu_hours,
    ROUND(100.0 * SUM(cpu_time_ms) / SUM(SUM(cpu_time_ms)) OVER (), 1) AS cpu_share_pct,
    ROUND(100.0 * SUM(failed_query_count) / SUM(query_count), 1)     AS failure_rate_pct
FROM mart.agg_team_usage_daily
WHERE usage_date BETWEEN DATE '2026-10-01' AND DATE '2026-10-31'
GROUP BY team_id
ORDER BY cpu_hours DESC;