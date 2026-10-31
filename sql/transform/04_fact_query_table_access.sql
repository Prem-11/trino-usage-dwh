-- Build core.fact_query_table_access for query dates in [start_date, end_date].
-- One row per query x table. System tables are excluded.
-- Query CPU is split across its tables by share of bytes read
-- (equal split if no bytes are known), so the split always adds up to the query CPU.

DELETE FROM core.fact_query_table_access
WHERE query_date BETWEEN DATE '{start_date}' AND DATE '{end_date}';

INSERT INTO core.fact_query_table_access
WITH events AS (
    SELECT query_id, payload
    FROM raw.query_events
    WHERE ingest_date BETWEEN DATE '{start_date}' AND DATE '{raw_end_date}'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY query_id ORDER BY ingest_date, loaded_at) = 1
),
inputs AS (
    -- json_each turns the "inputs" array into one row per table
    SELECT
        f.query_id,
        f.query_date,
        f.user_name,
        f.team_id,
        f.cpu_time_ms,
        (i.value ->> 'catalogName') || '.' || (i.value ->> 'schema') || '.' || (i.value ->> 'table')
                                                         AS table_id,
        CAST(i.value ->> 'physicalInputBytes' AS BIGINT) AS bytes_read,
        CAST(json_array_length(i.value -> 'columns') AS INTEGER) AS columns_read_count
    FROM core.fact_query f
    JOIN events e ON e.query_id = f.query_id,
         json_each(e.payload, '$.ioMetadata.inputs') AS i
    WHERE f.query_date BETWEEN DATE '{start_date}' AND DATE '{end_date}'
      AND (i.value ->> 'catalogName') <> 'system'
      AND (i.value ->> 'schema') <> 'information_schema'
),
per_table AS (
    -- a query can reference the same table twice (self-join): merge into one row
    SELECT
        query_id, query_date, user_name, team_id, cpu_time_ms, table_id,
        SUM(COALESCE(bytes_read, 0))  AS bytes_read,
        MAX(columns_read_count)       AS columns_read_count
    FROM inputs
    GROUP BY ALL
),
shares AS (
    SELECT
        *,
        CASE
            WHEN SUM(bytes_read) OVER (PARTITION BY query_id) = 0
                THEN 1.0 / COUNT(*) OVER (PARTITION BY query_id)
            ELSE bytes_read * 1.0 / SUM(bytes_read) OVER (PARTITION BY query_id)
        END AS bytes_share
    FROM per_table
)
SELECT
    query_id,
    table_id,
    query_date,
    user_name,
    team_id,
    bytes_read,
    columns_read_count,
    bytes_share,
    cpu_time_ms * bytes_share AS cpu_time_allocated_ms
FROM shares;