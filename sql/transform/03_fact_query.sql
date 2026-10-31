-- Build core.fact_query for query dates in [start_date, end_date].
-- 1. read raw events that could belong to this window (late events included)
-- 2. remove duplicates: keep one event per query_id
-- 3. look up the user's team ON the query date (SCD Type 2)

DELETE FROM core.fact_query
WHERE query_date BETWEEN DATE '{start_date}' AND DATE '{end_date}';

INSERT INTO core.fact_query
WITH events AS (
    SELECT
        query_id,
        payload,
        CAST(payload ->> '$.createTime' AS TIMESTAMPTZ) AT TIME ZONE 'UTC' AS start_time,
        CAST(payload ->> '$.endTime'    AS TIMESTAMPTZ) AT TIME ZONE 'UTC' AS end_time
    FROM raw.query_events
    -- events arrive on or after the query date, so this range catches late ones
    WHERE ingest_date BETWEEN DATE '{start_date}' AND DATE '{raw_end_date}'
    -- deduplication: same query_id delivered twice -> keep the first arrival
    QUALIFY ROW_NUMBER() OVER (PARTITION BY query_id ORDER BY ingest_date, loaded_at) = 1
),
parsed AS (
    SELECT
        query_id,
        CAST(end_time AS DATE)                                        AS query_date,
        payload ->> '$.context.user'                                  AS user_name,
        payload ->> '$.context.source'                                AS source,
        payload ->> '$.metadata.queryState'                           AS query_state,
        payload ->> '$.failureInfo.errorCode'                         AS error_code,
        start_time,
        end_time,
        CAST(payload ->> '$.statistics.cpuTimeMs' AS BIGINT)          AS cpu_time_ms,
        CAST(payload ->> '$.statistics.wallTimeMs' AS BIGINT)         AS wall_time_ms,
        CAST(payload ->> '$.statistics.queuedTimeMs' AS BIGINT)       AS queued_time_ms,
        CAST(payload ->> '$.statistics.peakUserMemoryBytes' AS BIGINT) AS peak_memory_bytes,
        CAST(payload ->> '$.statistics.cumulativeMemoryByteSec' AS DOUBLE) / 1e9
                                                                      AS cumulative_memory_gb_sec,
        CAST(payload ->> '$.statistics.physicalInputBytes' AS BIGINT) AS physical_input_bytes,
        CAST(json_array_length(payload, '$.ioMetadata.inputs') AS INTEGER)
                                                                      AS tables_read_count
    FROM events
)
SELECT
    p.query_id,
    p.query_date,
    p.user_name,
    COALESCE(b.team_id, 'unassigned') AS team_id,   -- unknown users are kept, not dropped
    p.source,
    p.query_state,
    p.error_code,
    p.start_time,
    p.end_time,
    p.cpu_time_ms,
    p.wall_time_ms,
    p.queued_time_ms,
    p.peak_memory_bytes,
    p.cumulative_memory_gb_sec,
    p.physical_input_bytes,
    p.tables_read_count
FROM parsed p
LEFT JOIN core.bridge_user_team b
       ON b.user_name = p.user_name
      AND p.query_date >= b.valid_from
      AND (b.valid_to IS NULL OR p.query_date <= b.valid_to)
WHERE p.query_date BETWEEN DATE '{start_date}' AND DATE '{end_date}';