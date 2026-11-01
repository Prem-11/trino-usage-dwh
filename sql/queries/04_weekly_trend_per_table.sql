-- Historical perspective: weekly distinct users per table, with week-over-week change.
-- Distinct users are recounted per week from the detail table (not summed from days).

WITH weekly AS (
    SELECT
        table_id,
        DATE_TRUNC('week', query_date) AS week_start,
        COUNT(DISTINCT user_name)      AS distinct_users,
        COUNT(*)                       AS queries
    FROM core.fact_query_table_access
    WHERE table_id = 'iceberg.sales.orders'
    GROUP BY table_id, week_start
)
SELECT
    table_id,
    week_start,
    distinct_users,
    queries,
    queries - LAG(queries) OVER (PARTITION BY table_id ORDER BY week_start) AS queries_change_vs_prev_week
FROM weekly
ORDER BY week_start;