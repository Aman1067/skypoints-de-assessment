INSERT INTO SKYPOINTS_DB.STAGING.STG_MEMBERS (
    member_id, member_name, enrollment_date, last_flight_date,
    tier_code, agent_name, state, country_code, dob, is_active,
    age, stale_member, load_ts
)
WITH cleaned AS (
    SELECT
        TRIM(member_id)                                               AS member_id,
        TRIM(member_name)                                             AS member_name,
        TRY_TO_DATE(TRIM(enrollment_date), 'YYYYMMDD')                AS enrollment_date,
        TRY_TO_DATE(TRIM(last_flight_date), 'YYYYMMDD')               AS last_flight_date,
        UPPER(TRIM(tier_code))                                        AS tier_code,
        NULLIF(TRIM(agent_name), '')                                  AS agent_name,
        UPPER(TRIM(state))                                            AS state,
        CASE UPPER(TRIM(country))
            WHEN 'AU'   THEN 'AUS'
            WHEN 'PHIL' THEN 'PHL'
            ELSE UPPER(TRIM(country))
        END                                                           AS country_code,
        -- Pad 7-digit DOBs (e.g., 3051985 -> 03051985) before parsing DDMMYYYY
        TRY_TO_DATE(LPAD(TRIM(dob), 8, '0'), 'DDMMYYYY')              AS dob,
        UPPER(TRIM(is_active))                                        AS is_active,
        load_ts
    FROM SKYPOINTS_DB.RAW.RAW_MEMBERS_FLAT
    WHERE UPPER(TRIM(record_type)) = 'D' -- Exclude Header ('H') rows
)
SELECT
    member_id,
    member_name,
    enrollment_date,
    last_flight_date,
    tier_code,
    agent_name,
    state,
    country_code,
    dob,
    is_active,
    -- Accurate Age calculation accounting for whether birthday occurred this year
    CASE
        WHEN dob IS NULL THEN NULL
        ELSE DATEDIFF('year', dob, CURRENT_DATE())
             - IFF(DATEADD('year', DATEDIFF('year', dob, CURRENT_DATE()), dob) > CURRENT_DATE(), 1, 0)
    END                                                               AS age,
    -- Stale_Member flag: TRUE if > 90 days since last flight (or never flew)
    CASE
        WHEN last_flight_date IS NULL THEN TRUE
        WHEN DATEDIFF('day', last_flight_date, CURRENT_DATE()) > 90 THEN TRUE
        ELSE FALSE
    END                                                               AS stale_member,
    load_ts
FROM cleaned
WHERE member_id IS NOT NULL
  AND member_name IS NOT NULL
  AND enrollment_date IS NOT NULL
  AND country_code IS NOT NULL;