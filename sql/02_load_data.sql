-- =============================================================================
-- 02_load_data.sql  |  Pure-SQL alternative to load_data.py (LOAD DATA LOCAL INFILE)
-- =============================================================================
-- The recommended route is `python load_data.py`. Use this file only if you
-- prefer SQL.
--
-- BEFORE YOU RUN IT
--   1. Unzip data/flights_clean.zip so that data/flights_clean.csv exists
--      (LOAD DATA cannot read a .zip). That CSV is git-ignored.
--   2. Replace the relative paths 'data/...' below with FULL paths if your
--      client does not start in the project folder, e.g.
--      'C:/Users/you/nyc-flights-sql-analysis/data/airlines_clean.csv'
--      (use forward slashes on Windows).
--   3. Local loading must be allowed on both sides:
--        - server:  SET GLOBAL local_infile = 1;   (needs an admin account)
--        - client:  the mysql CLI needs --local-infile=1; in DBeaver edit the
--                   connection > Driver properties > allowLoadLocalInfile = true
--   4. Run 01_schema.sql first. Run this file once on empty tables (re-running
--      would hit duplicate primary keys; re-run 01_schema.sql to start over).
--
-- Empty CSV fields mean "missing". LOAD DATA would turn them into 0 or '' so each
-- nullable column is read into a variable and converted with NULLIF(@x, '').
-- Parent tables load first because of the foreign keys.
-- =============================================================================

USE nyc_flights;
SET NAMES utf8mb4;

LOAD DATA LOCAL INFILE 'data/airlines_clean.csv'
INTO TABLE airlines
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(carrier, airline_name);

LOAD DATA LOCAL INFILE 'data/airports_clean.csv'
INTO TABLE airports
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(faa, airport_name, lat, lon, alt_ft, @utc_offset_hours, @dst, @tzone)
SET utc_offset_hours = NULLIF(@utc_offset_hours, ''),
    dst              = NULLIF(@dst, ''),
    tzone            = NULLIF(@tzone, '');

LOAD DATA LOCAL INFILE 'data/planes_clean.csv'
INTO TABLE planes
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(tailnum, @year_manufactured, aircraft_type, manufacturer, model, engines, seats, engine_type)
SET year_manufactured = NULLIF(@year_manufactured, '');

LOAD DATA LOCAL INFILE 'data/weather_clean.csv'
INTO TABLE weather
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(origin, time_hour, @temp_f, @dewpoint_f, @humidity_pct, @wind_dir_deg, @wind_speed_mph,
 precip_in, @pressure_mb, @visibility_miles)
SET temp_f           = NULLIF(@temp_f, ''),
    dewpoint_f       = NULLIF(@dewpoint_f, ''),
    humidity_pct     = NULLIF(@humidity_pct, ''),
    wind_dir_deg     = NULLIF(@wind_dir_deg, ''),
    wind_speed_mph   = NULLIF(@wind_speed_mph, ''),
    pressure_mb      = NULLIF(@pressure_mb, ''),
    visibility_miles = NULLIF(@visibility_miles, '');

-- The big one (about 435,000 rows). Takes a few seconds to a minute.
LOAD DATA LOCAL INFILE 'data/flights_clean.csv'
INTO TABLE flights
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(flight_id, flight_date, carrier, flight_number, @tailnum, origin, dest, flight_status,
 sched_dep_datetime, @actual_dep_datetime, @dep_delay_min, sched_arr_time, @actual_arr_time,
 @arr_delay_min, @air_time_min, distance_miles, time_hour)
SET tailnum             = NULLIF(@tailnum, ''),
    actual_dep_datetime = NULLIF(@actual_dep_datetime, ''),
    dep_delay_min       = NULLIF(@dep_delay_min, ''),
    actual_arr_time     = NULLIF(@actual_arr_time, ''),
    arr_delay_min       = NULLIF(@arr_delay_min, ''),
    air_time_min        = NULLIF(@air_time_min, '');

SELECT 'airlines' AS table_name, COUNT(*) AS row_count FROM airlines
UNION ALL SELECT 'airports', COUNT(*) FROM airports
UNION ALL SELECT 'planes',   COUNT(*) FROM planes
UNION ALL SELECT 'weather',  COUNT(*) FROM weather
UNION ALL SELECT 'flights',  COUNT(*) FROM flights;
