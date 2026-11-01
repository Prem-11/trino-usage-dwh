"""
Run every example query in sql/queries/ and print the results.

Usage:
  python pipeline/run_queries.py
"""
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "meta_dwh.duckdb"
QUERY_DIR = ROOT / "sql" / "queries"


def main():
    con = duckdb.connect(str(DB_PATH), read_only=True)
    for sql_file in sorted(QUERY_DIR.glob("*.sql")):
        sql = sql_file.read_text(encoding="utf-8")
        title = sql.splitlines()[0].lstrip("- ").strip()   # first comment line = title
        print(f"\n=== {sql_file.name}: {title}")
        con.sql(sql).show(max_width=200)
    con.close()


if __name__ == "__main__":
    main()