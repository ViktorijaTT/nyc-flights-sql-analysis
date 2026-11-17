# Data folder

Cleaned tables used by `load_data.py`. Full column-level data dictionary: the companion project
`nyc-flights-data-cleaning`, file `data/README.md` (the same tables, with the cleaning rules).

| File | Rows | Primary key | Notes |
|---|---|---|---|
| `airlines_clean.csv` | 14 | `carrier` | Airline codes and names |
| `airports_clean.csv` | 1,255 | `faa` | Airport codes, names, location, time zone. Only 121 are used by flights |
| `planes_clean.csv` | 4,840 | `tailnum` | Aircraft from the FAA registry. Year is missing for 89 aircraft |
| `weather_clean.csv` | 26,207 | `origin` + `time_hour` | Hourly weather at the three NYC airports. Time zone unconfirmed |
| `flights_clean.zip` | 435,352 | `flight_id` | Scheduled departures from JFK, LGA and EWR in 2023. Zip holding one CSV, `flights_clean.csv` (61.7 MB unzipped) |

- Missing values are empty fields in the CSV files. The loader turns them into NULL.
- Delay columns are blank for cancelled flights. Arrival delay is also blank for diverted flights.
- `flights_clean.zip` is read directly by `load_data.py`, so the unzipped CSV is not needed. If you use
  `sql/02_load_data.sql` instead, unzip the file first. The unzipped CSV is listed in `.gitignore`.
- Source and licence: CC0, from the `nycflights23` package (see the project README).
