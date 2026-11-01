-- Extra: cold tables = tables in the catalog with no queries in the last 30 days.
-- Candidates for archiving to save storage cost.
-- (Reference date is fixed to match the sample data; in production use CURRENT_DATE.)

WITH usage AS (
    SELECT
        table_id,
        MAX(query_date) AS last_queried_date,
        COUNT(*) FILTER (WHERE query_date > DATE '2026-10-31' - INTERVAL 30 DAY) AS queries_last_30_days
    FROM core.fact_query_table_access
    GROUP BY table_id
)
SELECT
    t.table_id,
    t.owner_team_id,
    t.description,
    u.last_queried_date,                              -- NULL = never queried
    COALESCE(u.queries_last_30_days, 0) AS queries_last_30_days
FROM core.dim_table t
LEFT JOIN usage u ON u.table_id = t.table_id
WHERE COALESCE(u.queries_last_30_days, 0) = 0
ORDER BY t.table_id;