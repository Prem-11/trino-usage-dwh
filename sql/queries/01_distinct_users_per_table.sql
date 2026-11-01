-- Q1: How many distinct users queried table X during a given period?
-- Source: core.fact_query_table_access (detail level), NOT the daily mart,
-- because distinct counts cannot be summed across days.
-- The last column shows the WRONG answer you get by summing daily distinct users.

WITH params AS (
    SELECT 'iceberg.sales.orders' AS table_id,
           DATE '2026-10-01'      AS start_date,
           DATE '2026-10-15'      AS end_date
)
SELECT
    a.table_id,
    COUNT(DISTINCT a.user_name)                                        AS distinct_users,
    COUNT(DISTINCT a.user_name) FILTER (WHERE NOT u.is_service_account) AS distinct_human_users,
    COUNT(DISTINCT a.team_id)                                          AS distinct_teams,
    COUNT(*)                                                           AS queries,
    (SELECT SUM(m.distinct_users)
     FROM mart.agg_table_usage_daily m, params p
     WHERE m.table_id = p.table_id
       AND m.usage_date BETWEEN p.start_date AND p.end_date)           AS wrong_sum_of_daily_distinct
FROM core.fact_query_table_access a
JOIN params p
  ON a.table_id = p.table_id
 AND a.query_date BETWEEN p.start_date AND p.end_date
LEFT JOIN core.dim_user u ON u.user_name = a.user_name
GROUP BY a.table_id;