"""
Run the Meta DWH pipeline: raw -> core -> mart.

Usage:
  python pipeline/run.py --date 2026-10-15                      # daily run (reprocesses last 3 days)
  python pipeline/run.py --start 2026-10-01 --end 2026-10-10    # backfill a date range
  python pipeline/run.py --all                                  # process every raw folder

Every step deletes its date range before inserting, so any run can be repeated safely.
"""
import argparse
from datetime import date, timedelta
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "meta_dwh.duckdb"
RAW_DIR = ROOT / "data" / "raw"
REF_DIR = ROOT / "data" / "reference"
SQL_DIR = ROOT / "sql" / "transform"

LOOKBACK_DAYS = 3   # late events can arrive up to 3 days after the query

CORE_AND_MART_STEPS = [
    "03_fact_query.sql",
    "04_fact_query_table_access.sql",
    "05_agg_table_usage_daily.sql",
    "06_agg_team_usage_daily.sql",
]


def run_sql(con, file_name, **params):
    """Read a SQL file, fill in {placeholders}, and execute it."""
    sql = (SQL_DIR / file_name).read_text(encoding="utf-8")
    for key, value in params.items():
        sql = sql.replace("{" + key + "}", str(value))
    con.execute(sql)


def load_raw(con, first_day, last_day):
    """Load every S3 folder (date=YYYY-MM-DD) between first_day and last_day."""
    loaded = 0
    day = first_day
    while day <= last_day:
        file_path = RAW_DIR / f"date={day}" / "events.jsonl"
        if file_path.exists():
            run_sql(con, "02_load_raw.sql", ingest_date=day, file_path=file_path.as_posix())
            loaded += 1
        day += timedelta(days=1)
    return loaded


def run_pipeline(start, end):
    raw_end = end + timedelta(days=LOOKBACK_DAYS)   # late events for 'end' arrive later
    print(f"Processing query dates {start} -> {end}")

    con = duckdb.connect(str(DB_PATH))
    try:
        con.begin()   # all or nothing: a failure leaves the database unchanged
        run_sql(con, "01_load_dimensions.sql", ref_dir=REF_DIR.as_posix())
        folders = load_raw(con, start, raw_end)
        print(f"  raw folders loaded: {folders}")

        for step in CORE_AND_MART_STEPS:
            run_sql(con, step, start_date=start, end_date=end, raw_end_date=raw_end)
            print(f"  done: {step}")
        con.commit()
    except Exception:
        con.rollback()
        print("FAILED - all changes rolled back")
        raise

    print("\nRow counts:")
    for table in ["raw.query_events", "core.fact_query", "core.fact_query_table_access",
                  "mart.agg_table_usage_daily", "mart.agg_team_usage_daily"]:
        count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table:<32} {count:>6}")
    con.close()


def main():
    parser = argparse.ArgumentParser(description="Meta DWH pipeline")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--date", type=date.fromisoformat, help="daily run for this date")
    mode.add_argument("--start", type=date.fromisoformat, help="backfill start date")
    mode.add_argument("--all", action="store_true", help="process all raw folders")
    parser.add_argument("--end", type=date.fromisoformat, help="backfill end date")
    args = parser.parse_args()

    if args.date:
        start, end = args.date - timedelta(days=LOOKBACK_DAYS), args.date
    elif args.start:
        if not args.end:
            parser.error("--start needs --end")
        start, end = args.start, args.end
    else:
        days = sorted(date.fromisoformat(p.name.split("=")[1]) for p in RAW_DIR.glob("date=*"))
        if not days:
            parser.error("no raw folders found - run generator/generate_events.py first")
        start, end = days[0], days[-1]

    run_pipeline(start, end)


if __name__ == "__main__":
    main()