USE DATABASE SKYPOINTS_DB;
USE SCHEMA STAGING;

-- 1. Deduplicate staging so only the latest record per member_id wins
CREATE OR REPLACE TEMP TABLE TMP_LATEST_MEMBERS AS
SELECT *
FROM SKYPOINTS_DB.STAGING.STG_MEMBERS
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY member_id
    ORDER BY load_ts DESC, last_flight_date DESC NULLS LAST, enrollment_date DESC
) = 1;

-- 2. Upsert into TABLE_INDIA (Repeat MERGE pattern for USA, AUS, CAN, PHL)
MERGE INTO SKYPOINTS_DB.MARTS.TABLE_INDIA AS tgt
USING (SELECT * FROM TMP_LATEST_MEMBERS WHERE country_code = 'IND') AS src
ON tgt.member_id = src.member_id
WHEN MATCHED THEN UPDATE SET
    tgt.member_name      = src.member_name,
    tgt.enrollment_date  = src.enrollment_date,
    tgt.last_flight_date = src.last_flight_date,
    tgt.tier_code        = src.tier_code,
    tgt.agent_name       = src.agent_name,
    tgt.state            = src.state,
    tgt.country_code     = src.country_code,
    tgt.dob              = src.dob,
    tgt.is_active        = src.is_active,
    tgt.age              = src.age,
    tgt.stale_member     = src.stale_member,
    tgt.updated_ts       = src.load_ts
WHEN NOT MATCHED THEN INSERT (
    member_id, member_name, enrollment_date, last_flight_date,
    tier_code, agent_name, state, country_code, dob, is_active,
    age, stale_member, updated_ts
) VALUES (
    src.member_id, src.member_name, src.enrollment_date, src.last_flight_date,
    src.tier_code, src.agent_name, src.state, src.country_code, src.dob, src.is_active,
    src.age, src.stale_member, src.load_ts
);

-- 3. Cross-Country Move Cleanup: Remove members who moved OUT of India
DELETE FROM SKYPOINTS_DB.MARTS.TABLE_INDIA tgt
USING TMP_LATEST_MEMBERS src
WHERE tgt.member_id = src.member_id
  AND src.country_code <> 'IND';