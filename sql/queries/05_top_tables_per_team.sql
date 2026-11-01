-- Which tables does each team spend its CPU on? Top 3 per team.
-- Uses allocated CPU, so multi-table queries are split fairly, never double counted.

WITH team_table AS (
    SELECT
        team_id,
        table_id,
        ROUND(SUM(cpu_time_allocated_ms) / 3600000.0, 2) AS cpu_hours
    FROM core.fact_query_table_access
    GROUP BY team_id, table_id
)
SELECT team_id, table_id, cpu_hours
FROM team_table
QUALIFY ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY cpu_hours DESC) <= 3
ORDER BY team_id, cpu_hours DESC;