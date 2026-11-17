-- =============================================================================
-- 01_schema.sql  |  NYC flights 2023  |  MySQL 8.0
-- Creates the database and five tables. Safe to re-run: it drops and rebuilds.
-- Run this first, then load the data (python load_data.py or 02_load_data.sql).
-- =============================================================================

DROP DATABASE IF EXISTS nyc_flights;
CREATE DATABASE nyc_flights
    CHARACTER SET utf8mb4          -- airport names contain accented characters
    COLLATE utf8mb4_0900_ai_ci;
USE nyc_flights;

-- ---------------------------------------------------------------------------
-- Lookup tables (parents). Loaded first because flights points at them.
-- ---------------------------------------------------------------------------

CREATE TABLE airlines (
    carrier       CHAR(2)      NOT NULL,   -- two-character airline code, e.g. 'UA'
    airline_name  VARCHAR(50)  NOT NULL,
    PRIMARY KEY (carrier)
) ENGINE = InnoDB;

CREATE TABLE airports (
    faa               CHAR(3)       NOT NULL,   -- FAA airport code, e.g. 'JFK'
    airport_name      VARCHAR(100)  NOT NULL,   -- NOT unique (5 names are shared), so faa is the key
    lat               DECIMAL(9,6)  NOT NULL,
    lon               DECIMAL(9,6)  NOT NULL,
    alt_ft            DECIMAL(6,1)  NOT NULL,
    utc_offset_hours  TINYINT       NULL,       -- NULL = unknown (only on airports no flight uses)
    dst               CHAR(1)       NULL,       -- 'A' = US daylight-saving rules, 'N' = none
    tzone             VARCHAR(30)   NULL,       -- IANA name, e.g. 'America/New_York'
    PRIMARY KEY (faa)
) ENGINE = InnoDB;

CREATE TABLE planes (
    tailnum            VARCHAR(6)   NOT NULL,   -- aircraft registration, e.g. 'N101DQ'
    year_manufactured  SMALLINT UNSIGNED NULL,  -- NULL for 89 aircraft; never imputed
    aircraft_type      VARCHAR(30)  NOT NULL,
    manufacturer       VARCHAR(30)  NOT NULL,
    model              VARCHAR(20)  NOT NULL,
    engines            TINYINT UNSIGNED  NOT NULL,
    seats              SMALLINT UNSIGNED NOT NULL,  -- registry figure, not the real cabin size
    engine_type        VARCHAR(20)  NOT NULL,
    PRIMARY KEY (tailnum),
    -- Supports the fleet query (manufacturer / age against delays).
    KEY idx_planes_manufacturer (manufacturer)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Weather: one row per airport per hour.
-- ---------------------------------------------------------------------------

CREATE TABLE weather (
    origin            CHAR(3)       NOT NULL,
    time_hour         DATETIME      NOT NULL,   -- hour the observation belongs to (time zone unconfirmed, see README)
    temp_f            DECIMAL(4,1)  NULL,
    dewpoint_f        DECIMAL(4,1)  NULL,
    humidity_pct      DECIMAL(5,2)  NULL,
    wind_dir_deg      SMALLINT UNSIGNED NULL,   -- 0 = calm, not north
    wind_speed_mph    DECIMAL(5,2)  NULL,
    precip_in         DECIMAL(6,4)  NOT NULL,   -- 0.0001 is a code for "trace"
    pressure_mb       DECIMAL(6,1)  NULL,
    visibility_miles  DECIMAL(4,2)  NULL,       -- capped at 10
    -- Natural composite key: one observation per airport-hour. The same pair is
    -- the join key from flights, so this primary key also serves that join.
    PRIMARY KEY (origin, time_hour),
    -- Every weather row is for a real airport (verified in 03_data_checks.sql).
    CONSTRAINT fk_weather_origin FOREIGN KEY (origin) REFERENCES airports (faa)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Flights (child of airlines and airports).
-- ---------------------------------------------------------------------------

CREATE TABLE flights (
    flight_id            INT UNSIGNED      NOT NULL,   -- surrogate key from the cleaning step (1..435,352)
    flight_date          DATE              NOT NULL,   -- scheduled departure date, local NY time
    carrier              CHAR(2)           NOT NULL,
    flight_number        SMALLINT UNSIGNED NOT NULL,
    tailnum              VARCHAR(6)        NULL,       -- NULL on 1,913 cancelled flights
    origin               CHAR(3)           NOT NULL,   -- EWR, JFK or LGA
    dest                 CHAR(3)           NOT NULL,
    flight_status        VARCHAR(22)       NOT NULL,   -- completed / cancelled / diverted_or_incomplete
    sched_dep_datetime   DATETIME          NOT NULL,
    actual_dep_datetime  DATETIME          NULL,       -- NULL = cancelled
    dep_delay_min        SMALLINT          NULL,       -- negative = early; NULL = cancelled
    sched_arr_time       TIME              NOT NULL,   -- destination local clock time, no date
    actual_arr_time      TIME              NULL,
    arr_delay_min        SMALLINT          NULL,       -- NULL unless flight_status = 'completed'
    air_time_min         SMALLINT UNSIGNED NULL,
    distance_miles       SMALLINT UNSIGNED NOT NULL,
    time_hour            DATETIME          NOT NULL,   -- sched_dep_datetime rounded down to the hour
    PRIMARY KEY (flight_id),

    -- Foreign keys that the data fully supports (checked: zero orphans).
    -- Each FK also creates/uses an index on its column, which speeds the joins
    -- to airlines and airports.
    CONSTRAINT fk_flights_carrier FOREIGN KEY (carrier) REFERENCES airlines (carrier),
    CONSTRAINT fk_flights_origin  FOREIGN KEY (origin)  REFERENCES airports (faa),
    CONSTRAINT fk_flights_dest    FOREIGN KEY (dest)    REFERENCES airports (faa),

    -- DELIBERATELY NO FOREIGN KEY on tailnum -> planes.tailnum.
    -- 9,371 flights (277 aircraft) use a tail number that is not in the FAA
    -- extract, and 1,913 cancelled flights have none. A strict FK would reject
    -- the load or force us to delete real flights. The column is indexed and
    -- queries use LEFT JOIN so the gap stays visible instead of hidden.
    -- (Same idea for weather: 826 flights have no weather row, so there is no
    -- FK on (origin, time_hour) either.)

    -- Indexes chosen for the queries in 04_analysis_queries.sql:
    -- daily / monthly / weekday trends and "worst days" (GROUP BY flight_date).
    -- Including carrier lets per-airline-per-day queries read the index only.
    KEY idx_flights_date_carrier (flight_date, carrier),
    -- Route queries (top routes per origin, route views, anti-join on airports).
    KEY idx_flights_origin_dest (origin, dest),
    -- Join to weather on airport + hour. Leading column origin also serves
    -- per-airport filters.
    KEY idx_flights_origin_hour (origin, time_hour),
    -- Join to planes (fleet query) and the anti-join to find unmatched aircraft.
    KEY idx_flights_tailnum (tailnum)
) ENGINE = InnoDB;
