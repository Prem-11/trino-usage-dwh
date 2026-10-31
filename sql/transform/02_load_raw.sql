-- Load ONE S3 folder (one ingest_date) into the raw layer.
-- Delete first, then insert: rerunning the same folder never creates duplicates.

DELETE FROM raw.query_events WHERE ingest_date = DATE '{ingest_date}';

INSERT INTO raw.query_events (ingest_date, query_id, payload, loaded_at)
SELECT
    DATE '{ingest_date}'                AS ingest_date,
    json ->> '$.metadata.queryId'       AS query_id,
    json                                AS payload,
    current_timestamp                   AS loaded_at
FROM read_ndjson_objects('{file_path}');