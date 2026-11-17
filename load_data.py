"""Load the cleaned NYC flights tables into the MySQL database `nyc_flights`.

Run sql/01_schema.sql first (it creates the empty tables), then:

    python load_data.py

Connection settings come from environment variables, so no password is stored
in the code. Defaults suit a local MySQL install:

    MYSQL_HOST      default localhost
    MYSQL_PORT      default 3306
    MYSQL_USER      default root
    MYSQL_PASSWORD  default: asked on the keyboard (nothing is shown or saved)
    MYSQL_DATABASE  default nyc_flights

Windows PowerShell example:
    $env:MYSQL_PASSWORD = "your-password"
    python load_data.py
"""
import getpass
import os
import sys
import time
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

# ---- connection settings (from environment variables) ----------------------
HOST = os.environ.get("MYSQL_HOST", "localhost")
PORT = int(os.environ.get("MYSQL_PORT", "3306"))
USER = os.environ.get("MYSQL_USER", "root")
DATABASE = os.environ.get("MYSQL_DATABASE", "nyc_flights")
PASSWORD = os.environ.get("MYSQL_PASSWORD")
if PASSWORD is None:                       # not set at all -> ask once
    PASSWORD = getpass.getpass(f"MySQL password for {USER}@{HOST}:{PORT} (Enter if none): ")

DATA_DIR = Path(__file__).resolve().parent / "data"   # works from any folder
CHUNK_ROWS = 20_000                                    # rows sent to MySQL per batch

# Columns that hold whole numbers but may be empty. "Int64" keeps them as
# integers with real missing values (a plain int column cannot hold NaN).
FLIGHT_INT_COLS = ["dep_delay_min", "arr_delay_min", "air_time_min"]

# Order matters: parent tables first, because flights and weather point at them.
# (table name, file name, extra read_csv options)
TABLES = [
    ("airlines", "airlines_clean.csv", {}),
    ("airports", "airports_clean.csv", {"dtype": {"utc_offset_hours": "Int64"}}),
    ("planes", "planes_clean.csv", {"dtype": {"year_manufactured": "Int64"}}),
    ("weather", "weather_clean.csv", {"dtype": {"wind_dir_deg": "Int64"}}),
    ("flights", "flights_clean.zip", {"dtype": {c: "Int64" for c in FLIGHT_INT_COLS}}),
]


def clean_chunk(df: pd.DataFrame) -> pd.DataFrame:
    """Turn every missing value (NaN / NA) into None, which MySQL stores as NULL."""
    return df.astype(object).where(df.notna(), None)


def load_table(engine, table: str, file_name: str, read_options: dict) -> int:
    path = DATA_DIR / file_name
    if not path.exists():
        sys.exit(f"Missing data file: {path}")
    start = time.time()
    total = 0
    # chunksize makes read_csv return the file in pieces, so the 62 MB flights
    # file never has to sit in memory all at once. A .zip with one CSV works too.
    for chunk in pd.read_csv(path, chunksize=CHUNK_ROWS, **read_options):
        clean_chunk(chunk).to_sql(table, engine, if_exists="append", index=False)
        total += len(chunk)
    print(f"  {table:<9} {total:>8,} rows loaded in {time.time() - start:5.1f} s")
    return total


def main() -> None:
    url = URL.create("mysql+pymysql", username=USER, password=PASSWORD,
                     host=HOST, port=PORT, database=DATABASE,
                     query={"charset": "utf8mb4"})
    engine = create_engine(url)

    print(f"Connecting to {USER}@{HOST}:{PORT}/{DATABASE}")
    with engine.begin() as conn:
        # Empty the tables so the script can be re-run without duplicate keys.
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 0"))
        for table, _, _ in TABLES:
            conn.execute(text(f"TRUNCATE TABLE {table}"))
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 1"))

    print("Loading:")
    for table, file_name, options in TABLES:
        load_table(engine, table, file_name, options)

    print("Row counts in the database:")
    with engine.connect() as conn:
        for table, _, _ in TABLES:
            n = conn.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar()
            print(f"  {table:<9} {n:>8,}")


if __name__ == "__main__":
    main()
