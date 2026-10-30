-- =====================================================================
-- RAW LAYER: events exactly as received. Never modified, only reloaded.
-- =====================================================================

-- Grain: 1 row per event received (duplicates from the source are kept here).
-- Production (Trino/Iceberg): WITH (partitioning = ARRAY['ingest_date'])
CREATE TABLE IF NOT EXISTS raw.query_events (
    ingest_date  DATE       NOT NULL,   -- S3 folder date = when the event arrived
    query_id     VARCHAR    NOT NULL,   -- metadata.queryId
    payload      JSON       NOT NULL,   -- full QueryCompletedEvent
    loaded_at    TIMESTAMP  NOT NULL    -- when our pipeline loaded it
);