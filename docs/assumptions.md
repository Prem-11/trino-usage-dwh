# Assumptions

1. Source: Trino Event Listener writes QueryCompletedEvent as JSON to S3,
   partitioned by date (s3://.../query_events/date=YYYY-MM-DD/).
2. Time zone is UTC. A query belongs to the date of its end time.
3. User → team mapping comes from an HR/LDAP export (extra metadata).
   A user belongs to one team at a time; team changes are kept as history
   with valid_from / valid_to dates.
4. A query is attributed to the team the user belonged to AT QUERY TIME,
   not their current team.
5. Service accounts (airflow, dbt, ...) are mapped to their owning team
   and flagged with is_service_account.
6. Unknown users go to team 'unassigned'. They are never dropped.
7. Multi-table queries:
   - usage counts: the query counts once for EACH table it read
   - resources: split across tables by share of bytes read
     (equal split if bytes are unknown)
   - team totals: always taken from the per-query table, so a query's CPU
     is never counted twice
8. Failed queries are kept (they consumed resources) and flagged.
9. Queries on system / information_schema tables are excluded from table usage.
10. Events can arrive late, so each daily run reprocesses the last 3 days.