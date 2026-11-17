-- =============================================================================
-- 05_views.sql  |  NYC flights 2023  |  MySQL 8.0
-- Two reusable views on top of the flights tables. A view stores the query, not
-- the rows, so the numbers always match the current flights table.
-- Run after 01_schema.sql and the data load:
--     mysql -uroot -p nyc_flights < sql/05_views.sql
--
-- Definitions (same as 04_analysis_queries.sql):
--   on time = arrival delay under 15 minutes; delay metrics use completed flights only.
-- =============================================================================

USE nyc_flights;

-- ---------------------------------------------------------------------------
-- v_daily_origin_summary: one row per departure day and origin airport.
-- Use it for daily dashboards, or filter by origin or by month.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_daily_origin_summary;
CREATE VIEW v_daily_origin_summary AS
SELECT
    f.flight_date,
    f.origin,
    ap.airport_name                                                      AS origin_airport_name,
    COUNT(*)                                                             AS scheduled_flights,
    SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END)       AS completed_flights,
    SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)       AS cancelled_flights,
    SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END) AS on_time_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.dep_delay_min END), 2) AS avg_dep_delay_min
FROM flights AS f
INNER JOIN airports AS ap
    ON ap.faa = f.origin
GROUP BY
    f.flight_date,
    f.origin,
    ap.airport_name;

-- ---------------------------------------------------------------------------
-- v_airline_scorecard: one row per airline with its main 2023 numbers.
-- Includes the number of destinations and origins served. No minimum-size
-- filter is applied here; filter on scheduled_flights >= 1000 when comparing.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS v_airline_scorecard;
CREATE VIEW v_airline_scorecard AS
SELECT
    a.carrier,
    a.airline_name,
    COUNT(*)                                                             AS scheduled_flights,
    COUNT(DISTINCT f.dest)                                               AS destinations_served,
    COUNT(DISTINCT f.origin)                                             AS origins_served,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.arr_delay_min END), 2) AS avg_arr_delay_min
FROM flights AS f
INNER JOIN airlines AS a
    ON a.carrier = f.carrier
GROUP BY
    a.carrier,
    a.airline_name;

-- Quick checks (the output is not saved; the results folder holds the query results).
SELECT COUNT(*) AS daily_origin_rows,
       SUM(scheduled_flights) AS flights_total
FROM v_daily_origin_summary;

SELECT COUNT(*) AS airlines_in_scorecard,
       SUM(scheduled_flights) AS flights_total
FROM v_airline_scorecard;
