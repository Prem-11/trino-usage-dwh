"""
Create the Meta DWH database and all tables.

Usage:
  python pipeline/init_db.py           # create tables (safe to rerun)
  python pipeline/init_db.py --reset   # delete the database and start fresh
"""
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "meta_dwh.duckdb"
DDL_DIR = ROOT / "sql" / "ddl"


def main():
    if "--reset" in sys.argv and DB_PATH.exists():
        DB_PATH.unlink()
        print("Old database deleted")

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB_PATH))

    for sql_file in sorted(DDL_DIR.glob("*.sql")):   # 01_, 02_, ... run in order
        con.execute(sql_file.read_text(encoding="utf-8"))
        print(f"Executed {sql_file.name}")

    tables = con.execute("""
        SELECT table_schema || '.' || table_name
        FROM information_schema.tables
        WHERE table_schema IN ('raw', 'core', 'mart')
        ORDER BY table_schema, table_name
    """).fetchall()

    print(f"\n{len(tables)} tables ready in {DB_PATH.name}:")
    for (name,) in tables:
        print(f"  {name}")
    con.close()


if __name__ == "__main__":
    main()