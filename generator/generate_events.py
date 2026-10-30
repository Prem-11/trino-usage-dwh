"""
Generate fake Trino query events to test the Meta DWH.

Creates:
  data/reference/*.csv              -> HR/LDAP export + table catalog (dimension data)
  data/raw/date=YYYY-MM-DD/*.jsonl  -> query events, one folder per day (simulated S3)

Field names follow Trino's QueryCompletedEvent (simplified: durations are in milliseconds).
"""
import csv
import json
import random
import shutil
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

# ---------------------------------------------------------------- settings
SEED = 42                          # same seed -> same data every run
START_DATE = date(2026, 10, 1)
NUM_DAYS = 30

ROOT = Path(__file__).resolve().parent.parent
REF_DIR = ROOT / "data" / "reference"
RAW_DIR = ROOT / "data" / "raw"

# ---------------------------------------------------------------- planted test cases
TEAM_CHANGER = "prem"                    # moves analytics -> marketing
TEAM_CHANGE_DATE = date(2026, 10, 16)
UNKNOWN_USER = "contractor_x"            # runs queries but is missing from HR data
COLD_TABLE = "iceberg.legacy.campaigns_2019"   # exists but is never queried
LATE_EVENT_RATE = 0.01                   # 1% of events land in the next day's folder
DUPLICATE_RATE = 0.005                   # 0.5% of events are delivered twice
FAILED_RATE = 0.05                       # 5% of queries fail
SYSTEM_QUERY_RATE = 0.02                 # 2% of queries read Trino system tables

# ---------------------------------------------------------------- reference data
TEAMS = [
    ("analytics", "Analytics", "Data"),
    ("marketing", "Marketing", "Business"),
    ("product", "Product", "Product"),
    ("finance", "Finance", "Business"),
    ("data_platform", "Data Platform", "Data"),
]

# (table_id, owner_team, description)
TABLES = [
    ("iceberg.events.ide_sessions", "product", "One row per IDE session with product, version and duration"),
    ("iceberg.events.feature_usage", "product", "One row per feature usage event in an IDE"),
    ("iceberg.events.plugin_installs", "product", "One row per plugin install or uninstall"),
    ("iceberg.events.crash_reports", "product", "One row per IDE crash report"),
    ("iceberg.sales.orders", "finance", "One row per license order"),
    ("iceberg.sales.customers", "finance", "One row per customer account"),
    ("iceberg.sales.licenses", "finance", "One row per active or expired license"),
    ("iceberg.sales.refunds", "finance", "One row per refund"),
    ("iceberg.marketing.campaigns", "marketing", "One row per marketing campaign"),
    ("iceberg.marketing.web_visits", "marketing", "One row per website visit"),
    ("iceberg.marketing.email_events", "marketing", "One row per email send, open or click"),
    ("iceberg.analytics.daily_active_users", "analytics", "Daily active users per product"),
    ("iceberg.analytics.retention_cohorts", "analytics", "User retention by signup cohort"),
    ("iceberg.analytics.product_kpis", "analytics", "Daily KPI values per product"),
    ("iceberg.platform.ingestion_log", "data_platform", "One row per ingestion job run"),
    ("iceberg.platform.table_sizes", "data_platform", "Daily size of every Iceberg table"),
    (COLD_TABLE, "marketing", "Old 2019 campaign data, kept for reference"),
]

SYSTEM_TABLES = [
    "system.runtime.queries",
    "system.information_schema.tables",
]

GENERIC_COLUMNS = ["id", "event_time", "user_id", "product", "country", "version", "amount", "status"]

HUMANS = {
    "analytics": ["prem", "anna", "ravi", "lena", "tom", "mia"],
    "marketing": ["sara", "omar", "julia", "ken", "nina"],
    "product": ["alex", "maria", "ivan", "chen", "lucas", "eva"],
    "finance": ["david", "sofia", "li", "peter"],
    "data_platform": ["max", "olga", "raj", "emma"],
}

SERVICE_ACCOUNTS = {"airflow_bot": "data_platform", "dbt_prod": "analytics"}

HUMAN_SOURCES = ["jupyter", "superset", "datagrip", "trino-cli"]
ROBOT_SOURCES = {"airflow_bot": "airflow", "dbt_prod": "dbt"}
ERROR_CODES = ["EXCEEDED_TIME_LIMIT", "EXCEEDED_MEMORY_LIMIT", "SYNTAX_ERROR", "TABLE_NOT_FOUND"]


# ---------------------------------------------------------------- helpers
def team_of(user, day):
    """Team of a user on a given day (used only to choose realistic tables)."""
    if user == TEAM_CHANGER:
        return "marketing" if day >= TEAM_CHANGE_DATE else "analytics"
    if user in SERVICE_ACCOUNTS:
        return SERVICE_ACCOUNTS[user]
    for team, members in HUMANS.items():
        if user in members:
            return team
    return None  # unknown user


def write_reference_files():
    """Write the dimension data: teams, users, team history, tables."""
    REF_DIR.mkdir(parents=True, exist_ok=True)

    with open(REF_DIR / "teams.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["team_id", "team_name", "department"])
        w.writerows(TEAMS)

    with open(REF_DIR / "users.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["user_name", "email", "is_service_account"])
        for members in HUMANS.values():
            for u in members:
                w.writerow([u, f"{u}@example.com", "false"])
        for u in SERVICE_ACCOUNTS:
            w.writerow([u, f"{u}@example.com", "true"])
        # UNKNOWN_USER is deliberately NOT written here

    with open(REF_DIR / "user_team_history.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["user_name", "team_id", "valid_from", "valid_to"])
        for team, members in HUMANS.items():
            for u in members:
                if u == TEAM_CHANGER:
                    w.writerow([u, "analytics", "2025-01-01", str(TEAM_CHANGE_DATE - timedelta(days=1))])
                    w.writerow([u, "marketing", str(TEAM_CHANGE_DATE), ""])
                else:
                    w.writerow([u, team, "2025-01-01", ""])
        for u, team in SERVICE_ACCOUNTS.items():
            w.writerow([u, team, "2025-01-01", ""])

    with open(REF_DIR / "tables.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["table_id", "catalog", "schema_name", "table_name",
                    "owner_team_id", "description", "created_date"])
        for table_id, owner, desc in TABLES:
            catalog, schema, name = table_id.split(".")
            w.writerow([table_id, catalog, schema, name, owner, desc, "2025-01-01"])


def pick_user(day):
    """Humans run most queries; robots and the unknown user run some."""
    r = random.random()
    if r < 0.12:
        return random.choice(list(SERVICE_ACCOUNTS))
    if r < 0.15 and day.weekday() < 5:
        return UNKNOWN_USER
    team = random.choice(list(HUMANS))
    return random.choice(HUMANS[team])


def pick_tables(user, day):
    """Pick 1-3 tables. Users prefer their own team's tables. Cold table is never picked."""
    if random.random() < SYSTEM_QUERY_RATE:
        return [random.choice(SYSTEM_TABLES)]

    candidates = [t for t, _, _ in TABLES if t != COLD_TABLE]
    team = team_of(user, day)
    weights = [3 if owner == team else 1 for t, owner, _ in TABLES if t != COLD_TABLE]

    k = random.choices([1, 2, 3], weights=[70, 22, 8])[0]
    chosen = []
    while len(chosen) < k:
        t = random.choices(candidates, weights=weights)[0]
        if t not in chosen:
            chosen.append(t)
    return chosen


def make_event(query_no, user, day):
    """Build one QueryCompletedEvent-like dict."""
    is_robot = user in SERVICE_ACCOUNTS
    hour = random.randint(0, 5) if is_robot else random.randint(8, 18)
    create_time = datetime(day.year, day.month, day.day, hour,
                           random.randint(0, 59), random.randint(0, 59), tzinfo=timezone.utc)

    tables = pick_tables(user, day)
    inputs = []
    for t in tables:
        catalog, schema, name = t.split(".")
        mb = random.lognormvariate(4, 1.5) * (5 if is_robot else 1)   # robots read more
        inputs.append({
            "catalogName": catalog,
            "schema": schema,
            "table": name,
            "columns": random.sample(GENERIC_COLUMNS, random.randint(1, 5)),
            "physicalInputBytes": int(mb * 1024 * 1024),
        })

    total_bytes = sum(i["physicalInputBytes"] for i in inputs)
    cpu_ms = int(total_bytes / (50 * 1024 * 1024) * 1000 * random.uniform(0.5, 2)) + 50
    failed = random.random() < FAILED_RATE
    if failed:
        cpu_ms = int(cpu_ms * random.uniform(0.1, 0.6))   # failed queries stop early

    parallelism = random.randint(4, 32)
    queued_ms = random.randint(0, 5000)
    wall_ms = int(cpu_ms / parallelism) + queued_ms + 100
    peak_mem = int(total_bytes * random.uniform(0.2, 1.5))
    end_time = create_time + timedelta(milliseconds=wall_ms)

    return {
        "metadata": {
            "queryId": f"{create_time:%Y%m%d_%H%M%S}_{query_no:05d}_trino",
            "queryState": "FAILED" if failed else "FINISHED",
            "query": f"SELECT ... FROM {', '.join(tables)}",
        },
        "context": {
            "user": user,
            "source": ROBOT_SOURCES.get(user, random.choice(HUMAN_SOURCES)),
        },
        "statistics": {
            "cpuTimeMs": cpu_ms,
            "wallTimeMs": wall_ms,
            "queuedTimeMs": queued_ms,
            "peakUserMemoryBytes": peak_mem,
            "cumulativeMemoryByteSec": int(peak_mem * wall_ms / 1000 * 0.5),
            "physicalInputBytes": total_bytes,
        },
        "ioMetadata": {"inputs": inputs},
        "failureInfo": {"errorCode": random.choice(ERROR_CODES)} if failed else None,
        "createTime": create_time.isoformat(),
        "endTime": end_time.isoformat(),
    }


def main():
    random.seed(SEED)
    write_reference_files()

    if RAW_DIR.exists():
        shutil.rmtree(RAW_DIR)   # start clean so reruns don't add duplicate files

    folders = {}   # arrival folder date -> list of events
    query_no = 0
    late = duplicates = failed = 0

    for d in range(NUM_DAYS):
        day = START_DATE + timedelta(days=d)
        n = random.randint(220, 280) if day.weekday() < 5 else random.randint(40, 70)

        for _ in range(n):
            query_no += 1
            event = make_event(query_no, pick_user(day), day)
            if event["metadata"]["queryState"] == "FAILED":
                failed += 1

            arrival = datetime.fromisoformat(event["endTime"]).date()
            if random.random() < LATE_EVENT_RATE:
                arrival += timedelta(days=1)     # late: lands in the next day's folder
                late += 1
            folders.setdefault(arrival, []).append(event)

            if random.random() < DUPLICATE_RATE:
                folders[arrival].append(event)   # same event delivered twice
                duplicates += 1

    total = 0
    for arrival, events in sorted(folders.items()):
        folder = RAW_DIR / f"date={arrival}"
        folder.mkdir(parents=True, exist_ok=True)
        with open(folder / "events.jsonl", "w") as f:
            for e in events:
                f.write(json.dumps(e) + "\n")
        total += len(events)

    print(f"Reference files written to {REF_DIR}")
    print(f"Queries generated : {query_no}")
    print(f"Events written    : {total} in {len(folders)} folders")
    print(f"Planted cases     : {failed} failed, {late} late, {duplicates} duplicates")
    print(f"                    team change: {TEAM_CHANGER} -> marketing on {TEAM_CHANGE_DATE}")
    print(f"                    unknown user: {UNKNOWN_USER}, cold table: {COLD_TABLE}")


if __name__ == "__main__":
    main()