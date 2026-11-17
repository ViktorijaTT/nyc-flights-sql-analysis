-- =============================================================================
-- 03_data_checks.sql  |  NYC flights 2023  |  MySQL 8.0
-- Data quality checks run after loading. Read the results top to bottom.
-- Expected values come from the CSV files (line counts minus the header) and
-- from the cleaning project's data dictionary. Each check returns a number;
-- 0 means "no problem found" unless the label says otherwise.
--
-- Run:  mysql -uroot -p nyc_flights < sql/03_data_checks.sql
-- =============================================================================

USE nyc_flights;

-- ---------------------------------------------------------------------------
-- 1. Row counts per table, compared with the expected counts from the CSVs
-- ---------------------------------------------------------------------------
SELECT 'airlines' AS table_name, COUNT(*) AS row_count, 14     AS expected_rows, COUNT(*) = 14     AS matches FROM airlines
UNION ALL
SELECT 'airports',  COUNT(*), 1255,   COUNT(*) = 1255   FROM airports
UNION ALL
SELECT 'planes',    COUNT(*), 4840,   COUNT(*) = 4840   FROM planes
UNION ALL
SELECT 'weather',   COUNT(*), 26207,  COUNT(*) = 26207  FROM weather
UNION ALL
SELECT 'flights',   COUNT(*), 435352, COUNT(*) = 435352 FROM flights;

-- ---------------------------------------------------------------------------
-- 2. Primary keys are unique (MySQL enforces these; the check confirms it).
--    duplicate_keys should be 0 for every row.
-- ---------------------------------------------------------------------------
SELECT 'airlines.carrier' AS key_name,
       COUNT(*) - COUNT(DISTINCT carrier) AS duplicate_keys FROM airlines
UNION ALL
SELECT 'airports.faa',
       COUNT(*) - COUNT(DISTINCT faa) FROM airports
UNION ALL
SELECT 'planes.tailnum',
       COUNT(*) - COUNT(DISTINCT tailnum) FROM planes
UNION ALL
SELECT 'weather (origin, time_hour)',
       COUNT(*) - COUNT(DISTINCT origin, time_hour) FROM weather
UNION ALL
SELECT 'flights.flight_id',
       COUNT(*) - COUNT(DISTINCT flight_id) FROM flights;

-- flight_id should run from 1 to 435,352 with no gaps.
SELECT MIN(flight_id) AS min_id,
       MAX(flight_id) AS max_id,
       COUNT(*)       AS row_count,
       MAX(flight_id) - MIN(flight_id) + 1 - COUNT(*) AS gaps   -- 0 = no gaps
FROM flights;

-- ---------------------------------------------------------------------------
-- 3. Orphan checks: links that point at nothing.
--    Expected: 0 for airlines, airports and weather. The tail-number and
--    weather links are known exceptions (see the data dictionary), so their
--    expected values are shown next to the result.
-- ---------------------------------------------------------------------------
SELECT 'flights.carrier not in airlines' AS check_name,
       COUNT(*) AS orphan_rows, 0 AS expected
FROM flights f
LEFT JOIN airlines a ON a.carrier = f.carrier
WHERE a.carrier IS NULL
UNION ALL
SELECT 'flights.origin not in airports',
       COUNT(*), 0
FROM flights f
LEFT JOIN airports a ON a.faa = f.origin
WHERE a.faa IS NULL
UNION ALL
SELECT 'flights.dest not in airports',
       COUNT(*), 0
FROM flights f
LEFT JOIN airports a ON a.faa = f.dest
WHERE a.faa IS NULL
UNION ALL
SELECT 'weather.origin not in airports',
       COUNT(*), 0
FROM weather w
LEFT JOIN airports a ON a.faa = w.origin
WHERE a.faa IS NULL
UNION ALL
SELECT 'flights.tailnum not in planes (tail number present)',
       COUNT(*), 9371          -- known exception: 277 aircraft missing from the FAA extract
FROM flights f
LEFT JOIN planes p ON p.tailnum = f.tailnum
WHERE f.tailnum IS NOT NULL
  AND p.tailnum IS NULL
UNION ALL
SELECT 'flights with no weather row (origin + hour)',
       COUNT(*), 826           -- known exception: 31 Dec at all airports, 2 May at LGA
FROM flights f
LEFT JOIN weather w ON w.origin = f.origin AND w.time_hour = f.time_hour
WHERE w.origin IS NULL;

-- Distinct aircraft behind the tail-number exception (expected 277).
SELECT COUNT(DISTINCT f.tailnum) AS aircraft_not_in_planes
FROM flights f
LEFT JOIN planes p ON p.tailnum = f.tailnum
WHERE f.tailnum IS NOT NULL
  AND p.tailnum IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Null counts for the key columns of each table.
--    Expected nulls are in the data dictionary (cleaning project).
-- ---------------------------------------------------------------------------
SELECT
    SUM(flight_date IS NULL)          AS flight_date_nulls,        -- expected 0
    SUM(carrier IS NULL)              AS carrier_nulls,            -- expected 0
    SUM(origin IS NULL)               AS origin_nulls,             -- expected 0
    SUM(dest IS NULL)                 AS dest_nulls,               -- expected 0
    SUM(flight_status IS NULL)        AS status_nulls,             -- expected 0
    SUM(sched_dep_datetime IS NULL)   AS sched_dep_nulls,          -- expected 0
    SUM(tailnum IS NULL)              AS tailnum_nulls,            -- expected 1,913
    SUM(actual_dep_datetime IS NULL)  AS actual_dep_nulls,         -- expected 10,738
    SUM(dep_delay_min IS NULL)        AS dep_delay_nulls,          -- expected 10,738
    SUM(actual_arr_time IS NULL)      AS actual_arr_nulls,         -- expected 11,453
    SUM(arr_delay_min IS NULL)        AS arr_delay_nulls,          -- expected 12,534
    SUM(air_time_min IS NULL)         AS air_time_nulls,           -- expected 12,534
    SUM(time_hour IS NULL)            AS time_hour_nulls           -- expected 0
FROM flights;

SELECT
    SUM(year_manufactured IS NULL) AS year_manufactured_nulls     -- expected 89
FROM planes;

SELECT
    SUM(visibility_miles IS NULL) AS visibility_nulls,            -- expected 23
    SUM(temp_f IS NULL)           AS temp_nulls                   -- expected 2
FROM weather;

-- ---------------------------------------------------------------------------
-- 5. Logic checks on the status rules (all expected to be 0).
-- ---------------------------------------------------------------------------
SELECT
    SUM(flight_status = 'cancelled' AND dep_delay_min IS NOT NULL)       AS cancelled_with_delay,
    SUM(flight_status = 'completed' AND arr_delay_min IS NULL)           AS completed_without_arr_delay,
    SUM(flight_status = 'completed' AND dep_delay_min IS NULL)           AS completed_without_dep_delay,
    SUM(flight_status <> 'cancelled' AND dep_delay_min IS NULL)          AS departed_without_delay
FROM flights;

-- Status counts (expected 422,818 completed; 10,738 cancelled; 1,796 diverted_or_incomplete).
SELECT flight_status, COUNT(*) AS flights
FROM flights
GROUP BY flight_status
ORDER BY flights DESC;
