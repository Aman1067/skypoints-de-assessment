-- 1. Environment Setup
CREATE DATABASE IF NOT EXISTS SKYPOINTS_DB;
CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.RAW;
CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.STAGING;
CREATE SCHEMA IF NOT EXISTS SKYPOINTS_DB.MARTS;

-- 2. Raw / Landing Tables (All strings/VARIANT to prevent ingestion failures)
CREATE OR REPLACE TABLE SKYPOINTS_DB.RAW.RAW_MEMBERS_FLAT (
    record_type       VARCHAR(10),
    member_name       VARCHAR(255),
    member_id         VARCHAR(50),
    enrollment_date   VARCHAR(50),
    last_flight_date  VARCHAR(50),
    tier_code         VARCHAR(20),
    agent_name        VARCHAR(255),
    state             VARCHAR(20),
    country           VARCHAR(20),
    dob               VARCHAR(50),
    is_active         VARCHAR(10),
    source_file_name  VARCHAR(255),
    load_ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE SKYPOINTS_DB.RAW.RAW_REDEMPTIONS_JSON (
    raw_payload       VARIANT,
    source_file_name  VARCHAR(255),
    load_ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 3. Staging Table (Typed, cleansed, with derived Age and Stale_Member)
CREATE OR REPLACE TABLE SKYPOINTS_DB.STAGING.STG_MEMBERS (
    member_id         VARCHAR(18) NOT NULL,
    member_name       VARCHAR(255) NOT NULL,
    enrollment_date   DATE NOT NULL,
    last_flight_date  DATE,
    tier_code         VARCHAR(5),
    agent_name        VARCHAR(255),
    state             VARCHAR(10),
    country_code      VARCHAR(5) NOT NULL,
    dob               DATE,
    is_active         CHAR(1),
    age               NUMBER(3,0),
    stale_member      BOOLEAN,
    load_ts           TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (country_code, last_flight_date);

-- 4. Quarantine Table (Dead-letter table for failed validation records)
CREATE OR REPLACE TABLE SKYPOINTS_DB.STAGING.QUARANTINE_MEMBERS (
    raw_member_id     VARCHAR(50),
    raw_member_name   VARCHAR(255),
    raw_payload       VARIANT,
    failure_reason    VARCHAR(500),
    load_ts           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 5. Country-Specific Target Tables (Template repeated per country)
CREATE OR REPLACE TABLE SKYPOINTS_DB.MARTS.TABLE_INDIA (
    member_id         VARCHAR(18) PRIMARY KEY,
    member_name       VARCHAR(255) NOT NULL,
    enrollment_date   DATE NOT NULL,
    last_flight_date  DATE,
    tier_code         VARCHAR(5),
    agent_name        VARCHAR(255),
    state             VARCHAR(10),
    country_code      VARCHAR(5) NOT NULL,
    dob               DATE,
    is_active         CHAR(1),
    age               NUMBER(3,0),
    stale_member      BOOLEAN,
    updated_ts        TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (last_flight_date, tier_code);

CREATE OR REPLACE TABLE SKYPOINTS_DB.MARTS.TABLE_USA         CLONE SKYPOINTS_DB.MARTS.TABLE_INDIA;
CREATE OR REPLACE TABLE SKYPOINTS_DB.MARTS.TABLE_AUSTRALIA   CLONE SKYPOINTS_DB.MARTS.TABLE_INDIA;
CREATE OR REPLACE TABLE SKYPOINTS_DB.MARTS.TABLE_CANADA      CLONE SKYPOINTS_DB.MARTS.TABLE_INDIA;
CREATE OR REPLACE TABLE SKYPOINTS_DB.MARTS.TABLE_PHILIPPINES CLONE SKYPOINTS_DB.MARTS.TABLE_INDIA;

-- 6. Flattened Redemptions Fact Table
CREATE OR REPLACE TABLE SKYPOINTS_DB.MARTS.FACT_REDEMPTIONS (
    txn_id            VARCHAR(50) PRIMARY KEY,
    member_id         VARCHAR(18) NOT NULL,
    feed_date         DATE NOT NULL,
    txn_date          DATE NOT NULL,
    partner           VARCHAR(100),
    miles_redeemed    NUMBER(12,0),
    status            VARCHAR(20),
    load_ts           TIMESTAMP_NTZ NOT NULL
)
CLUSTER BY (feed_date, member_id);