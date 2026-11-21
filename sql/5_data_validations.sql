INSERT INTO SKYPOINTS_DB.STAGING.QUARANTINE_MEMBERS (
    raw_member_id, raw_member_name, raw_payload, failure_reason
)
WITH checks AS (
    SELECT
        member_id,
        member_name,
        OBJECT_CONSTRUCT(*) AS raw_payload,
        ARRAY_COMPACT(ARRAY_CONSTRUCT(
            IFF(TRIM(member_id) IS NULL OR TRIM(member_id) = '', 'MISSING_MANDATORY_MEMBER_ID', NULL),
            IFF(TRIM(member_name) IS NULL OR TRIM(member_name) = '', 'MISSING_MANDATORY_MEMBER_NAME', NULL),
            IFF(TRY_TO_DATE(TRIM(enrollment_date), 'YYYYMMDD') IS NULL, 'INVALID_ENROLLMENT_DATE', NULL),
            IFF(TRIM(dob) IS NOT NULL AND TRY_TO_DATE(LPAD(TRIM(dob), 8, '0'), 'DDMMYYYY') IS NULL, 'INVALID_DOB_FORMAT', NULL),
            IFF(TRY_TO_DATE(TRIM(last_flight_date), 'YYYYMMDD') < TRY_TO_DATE(TRIM(enrollment_date), 'YYYYMMDD'), 'FLIGHT_BEFORE_ENROLLMENT', NULL),
            IFF(UPPER(TRIM(is_active)) NOT IN ('A', 'I'), 'INVALID_ACTIVE_FLAG', NULL),
            IFF(COUNT(*) OVER (PARTITION BY TRIM(member_id), load_ts) > 1, 'DUPLICATE_MEMBER_ID_IN_BATCH', NULL)
        )) AS errors
    FROM SKYPOINTS_DB.RAW.RAW_MEMBERS_FLAT
    WHERE UPPER(TRIM(record_type)) = 'D'
)
SELECT
    member_id,
    member_name,
    raw_payload,
    ARRAY_TO_STRING(errors, '; ') AS failure_reason
FROM checks
WHERE ARRAY_SIZE(errors) > 0;