# SkyPoints Global Airline Loyalty — Data Engineering Assessment

End-to-end ETL solution for **SkyPoints**, designed to ingest daily member profile flat files and semi-structured partner airline JSON redemption feeds at billion-record scale, cleanse and validate data, split members into per-country target tables using a **latest-record-wins** rule, and expose unified analytics views.

---

## Architecture Overview (Medallion Pattern)

```text
Daily Feeds (Flat File + JSON)
        │
        ▼
┌─────────────────────┐
│   RAW (Landing)     │  RAW_MEMBERS_FLAT (VARCHAR), RAW_REDEMPTIONS_JSON (VARIANT)
└─────────┬───────────┘
          │  Cleansing, Date Parsing, ISO-3 Country Mapping, Validation
          ├──────────────────────────────────┐
          ▼                                  ▼
┌─────────────────────┐          ┌──────────────────────────┐
│  STAGING (Silver)   │          │   QUARANTINE_MEMBERS     │
│  STG_MEMBERS        │          │   (Dead-letter table)    │
│  + Age, Stale_Flag  │          └──────────────────────────┘
└─────────┬───────────┘
          │  Deduplication (Latest Record Wins) + Cross-Country Move Cleanup
          ▼
┌───────────────────────────────────────────────────────────┐
│                      MARTS (Gold)                         │
│  TABLE_INDIA | TABLE_USA | TABLE_AUSTRALIA | TABLE_CANADA │
│  TABLE_PHILIPPINES  ──► VW_ALL_MEMBERS ◄── FACT_REDEMPTIONS│
└───────────────────────────────────────────────────────────┘