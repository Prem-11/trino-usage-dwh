-- Data quality checks. Each check returns the number of bad rows.
-- FAIL = data is wrong, stop and investigate.  WARN = worth a look, data still usable.

-- 1. Grain: one row per query
SELECT 'fact_query has no duplicate query_id' AS check_name, 'FAIL' AS severity,
       COUNT(*) - COUNT(DISTINCT query_id) AS bad_rows
FROM core.fact_query

UNION ALL
-- 2. Completeness: every query that arrived in raw is in fact_query
SELECT 'every raw query is loaded into fact_query', 'FAIL', COUNT(DISTINCT r.query_id)
FROM raw.query_events r
WHERE NOT EXISTS (SELECT 1 FROM core.fact_query f WHERE f.query_id = r.query_id)

UNION ALL
-- 3. No double counting: CPU split across tables adds up to the query CPU
SELECT 'table CPU split adds up to query CPU', 'FAIL', COUNT(*)
FROM (
    SELECT f.query_id
    FROM core.fact_query f
    JOIN core.fact_query_table_access a ON a.query_id = f.query_id
    GROUP BY f.query_id, f.cpu_time_ms
    HAVING ABS(f.cpu_time_ms - SUM(a.cpu_time_allocated_ms)) > 0.01
)

UNION ALL
-- 4. Mart matches core: daily team CPU equals the sum of query CPU
SELECT 'team mart CPU matches fact_query CPU', 'FAIL', COUNT(*)
FROM (
    SELECT query_date, team_id, SUM(cpu_time_ms) AS cpu FROM core.fact_query GROUP BY ALL
) f
FULL JOIN mart.agg_team_usage_daily m
  ON m.usage_date = f.query_date AND m.team_id = f.team_id
WHERE m.cpu_time_ms IS DISTINCT FROM f.cpu

UNION ALL
-- 5. Mart matches core: daily table query counts
SELECT 'table mart query counts match access rows', 'FAIL', COUNT(*)
FROM (
    SELECT query_date, table_id, COUNT(*) AS cnt FROM core.fact_query_table_access GROUP BY ALL
) a
FULL JOIN mart.agg_table_usage_daily m
  ON m.usage_date = a.query_date AND m.table_id = a.table_id
WHERE m.query_count IS DISTINCT FROM a.cnt

UNION ALL
-- 6. SCD2 sanity: a user cannot be in two teams at the same time
SELECT 'no overlapping team periods per user', 'FAIL', COUNT(*)
FROM core.bridge_user_team b1
JOIN core.bridge_user_team b2
  ON b1.user_name = b2.user_name
 AND b1.valid_from < b2.valid_from
 AND (b1.valid_to IS NULL OR b1.valid_to >= b2.valid_from)

UNION ALL
-- 7. Valid metrics
SELECT 'no negative metrics or end before start', 'FAIL', COUNT(*)
FROM core.fact_query
WHERE cpu_time_ms < 0 OR wall_time_ms < 0 OR physical_input_bytes < 0 OR end_time < start_time

UNION ALL
-- 8. Users missing from HR data (kept as 'unassigned')
SELECT 'users missing from HR data (unassigned)', 'WARN', COUNT(DISTINCT user_name)
FROM core.fact_query
WHERE team_id = 'unassigned'

UNION ALL
-- 9. Tables queried but missing from the table catalog
SELECT 'queried tables missing from dim_table', 'WARN', COUNT(DISTINCT a.table_id)
FROM core.fact_query_table_access a
WHERE NOT EXISTS (SELECT 1 FROM core.dim_table t WHERE t.table_id = a.table_id);