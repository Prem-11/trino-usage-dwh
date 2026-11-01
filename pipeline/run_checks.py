"""
Run data quality checks. Exits with code 1 if any FAIL check finds bad rows,
so an orchestrator (e.g. Airflow) would mark the run as failed.

Usage:
  python pipeline/run_checks.py
"""
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "meta_dwh.duckdb"
CHECKS_FILE = ROOT / "sql" / "checks" / "data_quality.sql"


def main():
    con = duckdb.connect(str(DB_PATH), read_only=True)
    results = con.execute(CHECKS_FILE.read_text(encoding="utf-8")).fetchall()
    con.close()

    failed = 0
    print("Data quality checks:")
    for check_name, severity, bad_rows in results:
        if bad_rows == 0:
            status = "PASS"
        else:
            status = severity   # FAIL or WARN
            failed += severity == "FAIL"
        print(f"  [{status}] {check_name}  (bad rows: {bad_rows})")

    passed = sum(1 for r in results if r[2] == 0)
    print(f"\n{passed}/{len(results)} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()