-- 1. Flatten JSON array into FACT_REDEMPTIONS (Idempotent MERGE on txn_id)
MERGE INTO SKYPOINTS_DB.MARTS.FACT_REDEMPTIONS AS tgt
USING (
    SELECT
        r.value:txn_id::VARCHAR(50)                      AS txn_id,
        TRIM(raw_payload:"member id"::VARCHAR(18))       AS member_id,
        TRY_TO_DATE(raw_payload:feed_date::VARCHAR, 'YYYYMMDD') AS feed_date,
        TRY_TO_DATE(r.value:txn_date::VARCHAR, 'YYYYMMDD')      AS txn_date,
        r.value:partner::VARCHAR(100)                    AS partner,
        r.value:miles_redeemed::NUMBER(12,0)             AS miles_redeemed,
        UPPER(r.value:status::VARCHAR(20))               AS status,
        load_ts
    FROM SKYPOINTS_DB.RAW.RAW_REDEMPTIONS_JSON,
         LATERAL FLATTEN(input => raw_payload:redemptions) r
    QUALIFY ROW_NUMBER() OVER (PARTITION BY txn_id ORDER BY load_ts DESC) = 1
) AS src
ON tgt.txn_id = src.txn_id
WHEN MATCHED THEN UPDATE SET
    tgt.status         = src.status,
    tgt.miles_redeemed = src.miles_redeemed,
    tgt.load_ts        = src.load_ts
WHEN NOT MATCHED THEN INSERT (
    txn_id, member_id, feed_date, txn_date, partner, miles_redeemed, status, load_ts
) VALUES (
    src.txn_id, src.member_id, src.feed_date, src.txn_date, src.partner, src.miles_redeemed, src.status, src.load_ts
);

-- 2. Unified Member View for Joining Redemptions Back to Profiles
-- Joining directly to 100+ country tables is unmaintainable; expose a unified view
CREATE OR REPLACE VIEW SKYPOINTS_DB.MARTS.VW_ALL_MEMBERS AS
SELECT * FROM SKYPOINTS_DB.MARTS.TABLE_INDIA
UNION ALL SELECT * FROM SKYPOINTS_DB.MARTS.TABLE_USA
UNION ALL SELECT * FROM SKYPOINTS_DB.MARTS.TABLE_AUSTRALIA
UNION ALL SELECT * FROM SKYPOINTS_DB.MARTS.TABLE_CANADA
UNION ALL SELECT * FROM SKYPOINTS_DB.MARTS.TABLE_PHILIPPINES;

-- 3. Analytical Join Query (Member Profile + Redemption Activity)
SELECT
    m.member_id,
    m.member_name,
    m.country_code,
    m.tier_code,
    m.stale_member,
    f.txn_id,
    f.txn_date,
    f.partner,
    f.miles_redeemed,
    f.status
FROM SKYPOINTS_DB.MARTS.FACT_REDEMPTIONS f
LEFT JOIN SKYPOINTS_DB.MARTS.VW_ALL_MEMBERS m
    ON f.member_id = m.member_id;