-- =============================================================================
-- 04_analysis_queries.sql  |  NYC flights 2023  |  MySQL 8.0
-- Twelve business questions about flights departing JFK, LGA and EWR in 2023.
--
-- Definitions used in every query (also stated in each comment block):
--   * On time      = arrival delay under 15 minutes (arr_delay_min < 15).
--   * Delay metrics use COMPLETED flights only (flight_status = 'completed').
--   * Cancellation rate = cancelled flights / all scheduled flights.
--   * Group-level rates (airline, airport, route, weekday, hour, weather group,
--     aircraft age band) must have at least 1,000 flights (HAVING COUNT(*) >= 1000).
--     Exceptions are explained in their comment blocks: q04 and q05 are time series,
--     q10 is a data-quality check over all airlines, q11 uses routes with 100+ flights,
--     and q12 lists the top 10 days.
--
-- Each block starts with a line "-- QUERY: <file name>". export_results.py uses
-- that line to split this file and save each result to results/<file name>.csv.
--
-- Indexes: 01_schema.sql already has the indexes these queries need. All twelve
-- queries ran in well under 10 seconds on the test server (see the README).
-- =============================================================================

USE nyc_flights;

-- QUERY: q01_airline_performance
-- -----------------------------------------------------------------------------
-- Question: Which airlines are most often on time, and which cancel the most?
-- Why a client cares: an airline comparison for route or partner choices, or
--   for a travel-service client who recommends carriers to customers.
-- Technique: INNER JOIN to airlines, CASE conditional aggregation, GROUP BY with HAVING.
-- Definitions: on-time rate uses completed flights only (arrival delay under
--   15 minutes). Cancellation rate uses all scheduled flights.
-- -----------------------------------------------------------------------------
SELECT
    a.carrier,
    a.airline_name,
    COUNT(*)                                                             AS scheduled_flights,
    SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)       AS cancelled_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END)       AS completed_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.arr_delay_min END), 2) AS avg_arr_delay_min
FROM flights AS f
INNER JOIN airlines AS a
    ON a.carrier = f.carrier
GROUP BY
    a.carrier,
    a.airline_name
HAVING COUNT(*) >= 1000
ORDER BY
    on_time_rate_pct DESC;

-- QUERY: q02_origin_airport_performance
-- -----------------------------------------------------------------------------
-- Question: How do JFK, LGA and EWR compare on on-time and cancellation rates?
-- Why a client cares: airport-level performance for travel planning, airport
--   marketing or a city report on the three New York airports.
-- Technique: INNER JOIN to airports, CASE conditional aggregation, GROUP BY with HAVING.
-- Definitions: on time = arrival delay under 15 minutes, completed flights only.
-- -----------------------------------------------------------------------------
SELECT
    f.origin,
    ap.airport_name,
    COUNT(*)                                                             AS scheduled_flights,
    SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)       AS cancelled_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.dep_delay_min END), 2) AS avg_dep_delay_min
FROM flights AS f
INNER JOIN airports AS ap
    ON ap.faa = f.origin
GROUP BY
    f.origin,
    ap.airport_name
HAVING COUNT(*) >= 1000
ORDER BY
    cancellation_rate_pct DESC;

-- QUERY: q03_top_destinations_by_origin
-- -----------------------------------------------------------------------------
-- Question: What are the three busiest routes from each New York airport?
-- Why a client cares: route planning, airport destination marketing, or a
--   partner that wants to target the largest markets from each airport.
-- Technique: two-step CTE chain, DENSE_RANK() window function, GROUP BY with HAVING,
--   join to airports for the destination name.
-- Definitions: a route is an origin and destination pair. Only routes with at
--   least 1,000 flights are ranked. DENSE_RANK keeps ties at the same rank.
-- -----------------------------------------------------------------------------
WITH route_counts AS (
    -- Step 1: flights per route, keeping only routes with at least 1,000 flights.
    SELECT
        f.origin,
        f.dest,
        COUNT(*) AS flights
    FROM flights AS f
    GROUP BY
        f.origin,
        f.dest
    HAVING COUNT(*) >= 1000
),
ranked_routes AS (
    -- Step 2: rank the routes inside each origin airport, busiest first.
    SELECT
        rc.origin,
        rc.dest,
        rc.flights,
        DENSE_RANK() OVER (PARTITION BY rc.origin ORDER BY rc.flights DESC) AS dest_rank
    FROM route_counts AS rc
)
SELECT
    r.origin,
    r.dest_rank,
    r.dest,
    ap.airport_name AS dest_airport_name,
    r.flights
FROM ranked_routes AS r
INNER JOIN airports AS ap
    ON ap.faa = r.dest
WHERE r.dest_rank <= 3
ORDER BY
    r.origin,
    r.dest_rank,
    r.dest;

-- QUERY: q04_monthly_trend_month_over_month
-- -----------------------------------------------------------------------------
-- Question: How do on-time and cancellation rates change from one month to the next?
-- Why a client cares: seasonality and month-over-month movement for planning
--   staffing, marketing or a monthly performance report.
-- Technique: CTE with DATE_FORMAT (date function), LAG() window function for the
--   previous month, and the change between months.
-- Definitions: on time = arrival delay under 15 minutes, completed flights only.
--   The first month has no previous month, so its change is blank (NULL).
-- -----------------------------------------------------------------------------
WITH monthly AS (
    -- Step 1: totals per calendar month.
    SELECT
        DATE_FORMAT(f.flight_date, '%Y-%m') AS month_label,
        COUNT(*)                                                       AS scheduled_flights,
        SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_flights,
        SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END) AS completed_flights,
        SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END) AS on_time_flights
    FROM flights AS f
    GROUP BY
        DATE_FORMAT(f.flight_date, '%Y-%m')
),
monthly_rates AS (
    -- Step 2: rates per month.
    SELECT
        m.month_label,
        m.scheduled_flights,
        m.cancelled_flights,
        ROUND(100 * m.cancelled_flights / m.scheduled_flights, 2) AS cancellation_rate_pct,
        ROUND(100 * m.on_time_flights / m.completed_flights, 2)   AS on_time_rate_pct
    FROM monthly AS m
)
-- Step 3: compare each month with the month before it.
SELECT
    mr.month_label,
    mr.scheduled_flights,
    mr.cancelled_flights,
    mr.cancellation_rate_pct,
    mr.on_time_rate_pct,
    LAG(mr.on_time_rate_pct) OVER (ORDER BY mr.month_label)                       AS prev_month_on_time_rate_pct,
    ROUND(mr.on_time_rate_pct - LAG(mr.on_time_rate_pct) OVER (ORDER BY mr.month_label), 2) AS on_time_change_pts,
    mr.cancelled_flights - LAG(mr.cancelled_flights) OVER (ORDER BY mr.month_label) AS cancelled_change_flights
FROM monthly_rates AS mr
ORDER BY
    mr.month_label;

-- QUERY: q05_daily_running_total_and_7day_average
-- -----------------------------------------------------------------------------
-- Question: How many flights were cancelled each day, what is the running total
--   for the year, and what is the 7-day moving average of the cancellation rate?
-- Why a client cares: smooths out day-to-day noise so that operational
--   problems stand out, and shows how the year-to-date total builds up.
-- Technique: daily CTE, running total with SUM() OVER (ROWS UNBOUNDED PRECEDING),
--   7-day moving average with ROWS BETWEEN 6 PRECEDING AND CURRENT ROW.
-- Definitions: the moving average is a ratio of sums over the last seven days
--   (cancelled / scheduled), not an average of daily percentages. The first six
--   days use fewer than seven days. This is a time series, so the 1,000-flight
--   rule does not apply here.
-- -----------------------------------------------------------------------------
WITH daily AS (
    -- Step 1: totals per day.
    SELECT
        f.flight_date,
        COUNT(*)                                                       AS scheduled_flights,
        SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_flights
    FROM flights AS f
    GROUP BY
        f.flight_date
)
SELECT
    d.flight_date,
    d.scheduled_flights,
    d.cancelled_flights,
    ROUND(100 * d.cancelled_flights / d.scheduled_flights, 2) AS cancellation_rate_pct,
    SUM(d.cancelled_flights) OVER (
        ORDER BY d.flight_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total_cancelled,
    ROUND(100 * SUM(d.cancelled_flights) OVER (
            ORDER BY d.flight_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
          / SUM(d.scheduled_flights) OVER (
            ORDER BY d.flight_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS cancellation_rate_7day_pct
FROM daily AS d
ORDER BY
    d.flight_date;

-- QUERY: q06_weekday_pattern
-- -----------------------------------------------------------------------------
-- Question: Which days of the week have the most cancellations and the most delays?
-- Why a client cares: staffing and scheduling; a weekday pattern is easy to act on.
-- Technique: date functions WEEKDAY() and DAYNAME(), GROUP BY with HAVING, CASE.
-- Definitions: delay averages use completed flights only. Weekday 1 = Monday.
-- -----------------------------------------------------------------------------
SELECT
    WEEKDAY(f.flight_date) + 1                                           AS weekday_order,
    DAYNAME(f.flight_date)                                               AS weekday_name,
    COUNT(*)                                                             AS scheduled_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.dep_delay_min END), 2) AS avg_dep_delay_min
FROM flights AS f
GROUP BY
    weekday_order,
    weekday_name
HAVING COUNT(*) >= 1000
ORDER BY
    weekday_order;

-- QUERY: q07_hour_of_day_delays
-- -----------------------------------------------------------------------------
-- Question: How do delays and cancellations change through the day?
-- Why a client cares: a common finding in aviation is that delays build up
--   during the day, so the time of departure matters when choosing a flight.
-- Technique: HOUR() date/time function, CASE conditional aggregation, GROUP BY with HAVING.
-- Definitions: hour = scheduled departure hour (local New York time). Delay
--   averages use completed flights only.
-- -----------------------------------------------------------------------------
SELECT
    HOUR(f.sched_dep_datetime)                                           AS sched_dep_hour,
    COUNT(*)                                                             AS scheduled_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.dep_delay_min END), 2) AS avg_dep_delay_min
FROM flights AS f
GROUP BY
    sched_dep_hour
HAVING COUNT(*) >= 1000
ORDER BY
    sched_dep_hour;

-- QUERY: q08_weather_conditions_and_delays
-- -----------------------------------------------------------------------------
-- Question: Do flights that depart in low-visibility or rainy hours run later
--   than flights that depart in clear hours?
-- Why a client cares: weather is a common explanation for delays; a clear
--   comparison shows how large the gap is in this data.
-- Technique: INNER JOIN of flights to hourly weather on origin and hour
--   (composite key), CASE to group the weather, conditional aggregation.
-- Definitions: each flight is matched to the weather hour of its scheduled
--   departure at its origin airport. Groups are checked in order: low visibility
--   (under 1 mile) first, then rain (0.01 inch or more), then clear (10 miles
--   and no rain). Other hours fall in 'Other'. Hours with no visibility value
--   are left out. Completed flights only for delay metrics.
--   Association only: this does not show that weather caused the delays.
--   Weather timestamps have an unconfirmed time zone (see the data dictionary).
-- -----------------------------------------------------------------------------
WITH flight_weather AS (
    -- Step 1: attach a weather group to each flight.
    SELECT
        f.flight_status,
        f.arr_delay_min,
        f.dep_delay_min,
        CASE
            WHEN w.visibility_miles < 1     THEN 'Low visibility (under 1 mile)'
            WHEN w.precip_in >= 0.01        THEN 'Rain (0.01 inch or more)'
            WHEN w.visibility_miles >= 10   THEN 'Clear (10 miles, no rain)'
            ELSE 'Other'
        END AS weather_group
    FROM flights AS f
    INNER JOIN weather AS w
        ON  w.origin    = f.origin
        AND w.time_hour = f.time_hour
    WHERE w.visibility_miles IS NOT NULL
)
-- Step 2: compare the groups.
SELECT
    fw.weather_group,
    COUNT(*)                                                             AS scheduled_flights,
    ROUND(100 * SUM(CASE WHEN fw.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(100 * SUM(CASE WHEN fw.flight_status = 'completed' AND fw.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN fw.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN fw.flight_status = 'completed' THEN fw.dep_delay_min END), 2) AS avg_dep_delay_min,
    ROUND(AVG(CASE WHEN fw.flight_status = 'completed' THEN fw.arr_delay_min END), 2) AS avg_arr_delay_min
FROM flight_weather AS fw
GROUP BY
    fw.weather_group
HAVING COUNT(*) >= 1000
ORDER BY
    avg_arr_delay_min DESC;

-- QUERY: q09_aircraft_age_and_delays
-- -----------------------------------------------------------------------------
-- Question: Do older aircraft have more delays than newer ones?
-- Why a client cares: fleet planning and maintenance; an age comparison is a
--   simple, common question for airlines and aircraft lessors.
-- Technique: INNER JOIN to planes on tail number, CASE to build age bands,
--   GROUP BY with HAVING.
-- Definitions: age = 2023 minus year of manufacture (the data year). Only flights
--   whose tail number is in the planes table are included (about 97 percent of
--   flights; see q10). Delay metrics use completed flights only.
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN p.year_manufactured IS NULL THEN 5
        WHEN 2023 - p.year_manufactured < 10 THEN 1
        WHEN 2023 - p.year_manufactured < 20 THEN 2
        ELSE 3
    END AS age_order,
    CASE
        WHEN p.year_manufactured IS NULL THEN 'Year unknown'
        WHEN 2023 - p.year_manufactured < 10 THEN 'Under 10 years old'
        WHEN 2023 - p.year_manufactured < 20 THEN '10 to 19 years old'
        ELSE '20 years or older'
    END AS aircraft_age_band,
    COUNT(*)                                                             AS scheduled_flights,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS cancellation_rate_pct,
    ROUND(100 * SUM(CASE WHEN f.flight_status = 'completed' AND f.arr_delay_min < 15 THEN 1 ELSE 0 END)
          / SUM(CASE WHEN f.flight_status = 'completed' THEN 1 ELSE 0 END), 2) AS on_time_rate_pct,
    ROUND(AVG(CASE WHEN f.flight_status = 'completed' THEN f.arr_delay_min END), 2) AS avg_arr_delay_min
FROM flights AS f
INNER JOIN planes AS p
    ON p.tailnum = f.tailnum
GROUP BY
    age_order,
    aircraft_age_band
HAVING COUNT(*) >= 1000
ORDER BY
    age_order;

-- QUERY: q10_unregistered_aircraft_by_airline
-- -----------------------------------------------------------------------------
-- Question: Which airlines fly aircraft whose tail number is missing from the
--   planes table (the FAA registry extract)?
-- Why a client cares: a data-quality and fleet-coverage check. An analyst who
--   joins flights to planes must know how much of the data is lost in the join.
-- Technique: anti-join with LEFT JOIN ... WHERE right key IS NULL, two-step CTE chain.
-- Definitions: cancelled flights with no tail number are not counted here (they
--   have no tail number at all). Percentages use all scheduled flights of the airline.
--   All airlines are listed, without the 1,000-flight rule: this is a data-quality
--   check, not a ranking.
-- -----------------------------------------------------------------------------
WITH carrier_totals AS (
    -- Step 1: all scheduled flights per airline.
    SELECT
        f.carrier,
        COUNT(*) AS scheduled_flights
    FROM flights AS f
    GROUP BY
        f.carrier
),
unmatched AS (
    -- Step 2: flights whose tail number has no match in planes (anti-join).
    SELECT
        f.carrier,
        f.tailnum,
        f.flight_id
    FROM flights AS f
    LEFT JOIN planes AS p
        ON p.tailnum = f.tailnum
    WHERE f.tailnum IS NOT NULL
      AND p.tailnum IS NULL
)
SELECT
    a.carrier,
    a.airline_name,
    ct.scheduled_flights,
    COUNT(u.flight_id)                                                   AS flights_unregistered_tailnum,
    COUNT(DISTINCT u.tailnum)                                            AS aircraft_not_in_registry,
    ROUND(100 * COUNT(u.flight_id) / ct.scheduled_flights, 2)            AS share_of_flights_pct
FROM carrier_totals AS ct
INNER JOIN airlines AS a
    ON a.carrier = ct.carrier
LEFT JOIN unmatched AS u
    ON u.carrier = ct.carrier
GROUP BY
    a.carrier,
    a.airline_name,
    ct.scheduled_flights
ORDER BY
    flights_unregistered_tailnum DESC;

-- QUERY: q11_single_airline_routes
-- -----------------------------------------------------------------------------
-- Question: Which routes are flown by only one airline?
-- Why a client cares: a route served by one carrier has no direct competitor
--   on that route, which matters for pricing, marketing and route-planning work.
-- Technique: two-step CTE chain (flights per route and airline), then a NOT EXISTS
--   subquery (EXISTS family) that looks for any other airline on the same route.
--   The subquery reads the small CTE, not the 435,352-row table, to stay fast.
-- Definitions: a route is an origin and destination pair. Routes with at least
--   100 flights for the airline are listed.
-- -----------------------------------------------------------------------------
WITH route_airlines AS (
    -- Step 1: one row per route and airline, with its number of flights.
    SELECT
        f.origin,
        f.dest,
        f.carrier,
        COUNT(*) AS flights
    FROM flights AS f
    GROUP BY
        f.origin,
        f.dest,
        f.carrier
)
SELECT
    ra.origin,
    ra.dest,
    ra.carrier,
    a.airline_name,
    ra.flights
FROM route_airlines AS ra
INNER JOIN airlines AS a
    ON a.carrier = ra.carrier
WHERE ra.flights >= 100
  AND NOT EXISTS (
        -- True only when no other airline flies the same origin and destination.
        SELECT 1
        FROM route_airlines AS other
        WHERE other.origin  = ra.origin
          AND other.dest    = ra.dest
          AND other.carrier <> ra.carrier
  )
ORDER BY
    ra.flights DESC;

-- QUERY: q12_worst_cancellation_days
-- -----------------------------------------------------------------------------
-- Question: What were the 10 days of 2023 with the most cancelled flights, and
--   what was the weather on those days?
-- Why a client cares: a short list of the days that caused the most disruption,
--   for a review of operations or a case study of a storm.
-- Technique: two-step CTE chain (flights per day, weather per day), LEFT JOIN
--   on date, ORDER BY with LIMIT.
-- Definitions: ties on cancelled flights are broken by the cancellation rate.
--   Rainy hours counts hours with 0.01 inch or more of rain, across the three
--   airports (up to 72 airport-hours per day). Minimum visibility is the lowest
--   value across the three airports. Weather timestamps have an unconfirmed time
--   zone (see the data dictionary).
-- -----------------------------------------------------------------------------
WITH daily_flights AS (
    -- Step 1: flights and cancellations per day.
    SELECT
        f.flight_date,
        COUNT(*)                                                         AS scheduled_flights,
        SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)   AS cancelled_flights,
        ROUND(100 * SUM(CASE WHEN f.flight_status = 'cancelled' THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                             AS cancellation_rate_pct
    FROM flights AS f
    GROUP BY
        f.flight_date
),
daily_weather AS (
    -- Step 2: weather per calendar day, across the three airports.
    SELECT
        DATE(w.time_hour) AS weather_date,
        SUM(CASE WHEN w.precip_in >= 0.01 THEN 1 ELSE 0 END) AS rainy_hours,
        MIN(w.visibility_miles)                              AS min_visibility_miles
    FROM weather AS w
    GROUP BY
        DATE(w.time_hour)
)
SELECT
    df.flight_date,
    DAYNAME(df.flight_date) AS weekday_name,
    df.scheduled_flights,
    df.cancelled_flights,
    df.cancellation_rate_pct,
    dw.rainy_hours,
    dw.min_visibility_miles
FROM daily_flights AS df
LEFT JOIN daily_weather AS dw
    ON dw.weather_date = df.flight_date
ORDER BY
    df.cancelled_flights DESC,
    df.cancellation_rate_pct DESC,
    df.flight_date
LIMIT 10;
