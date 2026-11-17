"""Run every query in sql/04_analysis_queries.sql and save each result as a CSV.

Run after the database is loaded (see README):

    python export_results.py

Output: results/q01_airline_performance.csv ... results/q12_worst_cancellation_days.csv

How it works:
  1. The SQL file is split at the lines "-- QUERY: <name>". Each part is one query.
  2. The comment lines are removed, so only the SQL is sent to MySQL.
  3. Each query runs and its rows are written to results/<name>.csv.

Connection settings come from the same environment variables as load_data.py
(MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE).
"""
import getpass
import os
import re
import sys
import time
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

# ---- connection settings (from environment variables) ----------------------
HOST = os.environ.get("MYSQL_HOST", "localhost")
PORT = int(os.environ.get("MYSQL_PORT", "3306"))
USER = os.environ.get("MYSQL_USER", "root")
DATABASE = os.environ.get("MYSQL_DATABASE", "nyc_flights")
PASSWORD = os.environ.get("MYSQL_PASSWORD")
if PASSWORD is None:                       # not set at all -> ask once
    PASSWORD = getpass.getpass(f"MySQL password for {USER}@{HOST}:{PORT} (Enter if none): ")

PROJECT_DIR = Path(__file__).resolve().parent
SQL_FILE = PROJECT_DIR / "sql" / "04_analysis_queries.sql"
RESULTS_DIR = PROJECT_DIR / "results"


def split_queries(sql_text: str) -> list[tuple[str, str]]:
    """Return (query name, SQL without comment lines) for each block in the file."""
    parts = re.split(r"^-- QUERY: (\w+)\s*$", sql_text, flags=re.MULTILINE)
    queries = []
    for i in range(1, len(parts), 2):          # parts = [header, name1, body1, name2, body2, ...]
        name, body = parts[i], parts[i + 1]
        lines = [line for line in body.splitlines() if not line.strip().startswith("--")]
        sql = "\n".join(lines).strip().rstrip(";")
        queries.append((name, sql))
    return queries


def main() -> None:
    url = URL.create("mysql+pymysql", username=USER, password=PASSWORD,
                     host=HOST, port=PORT, database=DATABASE,
                     query={"charset": "utf8mb4"})
    engine = create_engine(url)
    RESULTS_DIR.mkdir(exist_ok=True)

    queries = split_queries(SQL_FILE.read_text(encoding="utf-8"))
    if not queries:
        sys.exit(f"No '-- QUERY:' blocks found in {SQL_FILE}")

    # The raw DB-API connection is used on purpose: it sends the SQL text
    # unchanged. (SQLAlchemy would pass an empty parameter list, and PyMySQL would
    # then read the '%Y-%m' date formats in the SQL as placeholders.)
    raw = engine.raw_connection()
    try:
        cursor = raw.cursor()
        for name, sql in queries:
            start = time.time()
            cursor.execute(sql)                       # no parameters
            columns = [col[0] for col in cursor.description]
            df = pd.DataFrame(cursor.fetchall(), columns=columns)
            out_path = RESULTS_DIR / f"{name}.csv"
            df.to_csv(out_path, index=False, encoding="utf-8")
            print(f"  {name:<40} {len(df):>5} rows  {time.time() - start:5.1f} s  -> {out_path.name}")
        cursor.close()
    finally:
        raw.close()


if __name__ == "__main__":
    main()
