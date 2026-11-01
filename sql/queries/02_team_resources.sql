-- Q2: How many resources did team Y consume during a given period?
-- Additive metrics (CPU, bytes, memory, query counts) can be summed from the daily mart: fast.
-- Distinct users is not additive, so it comes from core.fact_query.

WITH params AS (
    SELECT 'analytics'       AS team_id,
           DATE '2026-10-01' AS start_date,
           DATE '2026-10-15' AS end_date
)
SELECT
    m.team_id,
    SUM(m.query_count)                                       AS queries,
    SUM(m.failed_query_count)                                AS failed_queries,
    ROUND(SUM(m.cpu_time_ms) / 3600000.0, 2)                 AS cpu_hours,
    ROUND(SUM(m.bytes_read) / POWER(1024, 3), 1)             AS gb_read,
    ROUND(SUM(m.cumulative_memory_gb_sec) / 3600.0, 2)       AS memory_gb_hours,
    (SELECT COUNT(DISTINCT f.user_name)
     FROM core.fact_query f, params p
     WHERE f.team_id = p.team_id
       AND f.query_date BETWEEN p.start_date AND p.end_date) AS distinct_users
FROM mart.agg_team_usage_daily m
JOIN params p
  ON m.team_id = p.team_id
 AND m.usage_date BETWEEN p.start_date AND p.end_date
GROUP BY m.team_id;