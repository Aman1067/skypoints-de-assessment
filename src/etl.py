import json
from datetime import date, datetime
from pathlib import Path
from typing import Dict, List, Tuple

import pandas as pd

COUNTRY_MAP = {
    "AU": "AUS",
    "PHIL": "PHL",
}


def parse_flat_file(filepath: str | Path) -> pd.DataFrame:
    """Parse pipe-delimited member flat file, handling missing leading pipes and extra whitespace."""
    rows = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = [p.strip() for p in line.strip("|").split("|")]
            if not parts or parts[0].upper() != "D":
                continue  # Skip header ('H') or malformed non-detail lines
            # Pad or trim to 11 columns: record_type + 10 member fields
            parts = (parts + [""] * 11)[:11]
            rows.append({
                "member_name": parts[1],
                "member_id": parts[2],
                "enrollment_date": parts[3],
                "last_flight_date": parts[4],
                "tier_code": parts[5].upper(),
                "agent_name": parts[6] or None,
                "state": parts[7].upper(),
                "country": parts[8].upper(),
                "dob": parts[9],
                "is_active": parts[10].upper(),
            })
    return pd.DataFrame(rows)


def _parse_date(val: str, fmt: str, pad_zero: bool = False) -> date | None:
    if not val or str(val).strip().upper() in ("", "NULL", "NAN"):
        return None
    s = str(val).strip()
    if pad_zero and len(s) == 7 and s.isdigit():
        s = s.zfill(8)  # Fixes dropped leading zero (e.g., 3051985 -> 03051985)
    try:
        return datetime.strptime(s, fmt).date()
    except ValueError:
        return None


def compute_age(dob: date | None, ref_date: date | None = None) -> int | None:
    if dob is None:
        return None
    ref = ref_date or date.today()
    return ref.year - dob.year - ((ref.month, ref.day) < (dob.month, dob.day))


def validate_and_stage(
    raw_df: pd.DataFrame, ref_date: date | None = None
) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Validate raw records, derive Age and Stale_Member, and split valid vs quarantine."""
    ref = ref_date or date.today()
    valid_rows: List[dict] = []
    quarantine_rows: List[dict] = []

    id_counts = raw_df["member_id"].value_counts()

    for _, row in raw_df.iterrows():
        errors = []
        mid = str(row.get("member_id", "")).strip()
        mname = str(row.get("member_name", "")).strip()

        if not mid:
            errors.append("MISSING_MANDATORY_MEMBER_ID")
        if not mname:
            errors.append("MISSING_MANDATORY_MEMBER_NAME")

        enroll_dt = _parse_date(row.get("enrollment_date", ""), "%Y%m%d")
        if enroll_dt is None:
            errors.append("INVALID_ENROLLMENT_DATE")

        flight_dt = _parse_date(row.get("last_flight_date", ""), "%Y%m%d")
        if row.get("last_flight_date") and flight_dt is None:
            errors.append("INVALID_LAST_FLIGHT_DATE")

        if enroll_dt and flight_dt and flight_dt < enroll_dt:
            errors.append("FLIGHT_BEFORE_ENROLLMENT")

        dob_dt = _parse_date(row.get("dob", ""), "%d%m%Y", pad_zero=True)
        if row.get("dob") and str(row.get("dob")).upper() != "NULL" and dob_dt is None:
            errors.append("INVALID_DOB_FORMAT")

        is_active = str(row.get("is_active", "")).strip().upper()
        if is_active not in ("A", "I"):
            errors.append("INVALID_ACTIVE_FLAG")

        if mid and id_counts.get(mid, 0) > 1:
            errors.append("DUPLICATE_MEMBER_ID_IN_BATCH")

        if errors:
            q_row = row.to_dict()
            q_row["failure_reason"] = "; ".join(errors)
            quarantine_rows.append(q_row)
        else:
            raw_country = str(row.get("country", "")).strip().upper()
            country_code = COUNTRY_MAP.get(raw_country, raw_country)
            stale = True if flight_dt is None else (ref - flight_dt).days > 90

            valid_rows.append({
                "member_id": mid,
                "member_name": mname,
                "enrollment_date": enroll_dt,
                "last_flight_date": flight_dt,
                "tier_code": row.get("tier_code"),
                "agent_name": row.get("agent_name"),
                "state": row.get("state"),
                "country_code": country_code,
                "dob": dob_dt,
                "is_active": is_active,
                "age": compute_age(dob_dt, ref),
                "stale_member": stale,
            })

    return pd.DataFrame(valid_rows), pd.DataFrame(quarantine_rows)


def split_by_country_latest_wins(staged_df: pd.DataFrame) -> Dict[str, pd.DataFrame]:
    """Deduplicate by member_id (latest flight/enrollment wins) and split into per-country tables."""
    if staged_df.empty:
        return {}
    deduped = (
        staged_df.sort_values(
            by=["last_flight_date", "enrollment_date"],
            ascending=[False, False],
            na_position="last",
        )
        .drop_duplicates(subset=["member_id"], keep="first")
        .reset_index(drop=True)
    )
    return {
        country: group.reset_index(drop=True)
        for country, group in deduped.groupby("country_code")
    }


def flatten_redemptions_json(filepath: str | Path) -> pd.DataFrame:
    """Flatten nested JSON redemptions feed, handling the 'member id' key with a space."""
    with open(filepath, "r", encoding="utf-8") as f:
        payload = json.load(f)

    if isinstance(payload, dict):
        payload = [payload]

    records = []
    for entry in payload:
        member_id = str(entry.get("member id") or entry.get("member_id", "")).strip()
        feed_date = _parse_date(entry.get("feed_date", ""), "%Y%m%d")
        for txn in entry.get("redemptions", []):
            records.append({
                "txn_id": txn.get("txn_id"),
                "member_id": member_id,
                "feed_date": feed_date,
                "txn_date": _parse_date(txn.get("txn_date", ""), "%Y%m%d"),
                "partner": txn.get("partner"),
                "miles_redeemed": int(txn.get("miles_redeemed", 0)),
                "status": str(txn.get("status", "")).upper(),
            })
    return pd.DataFrame(records).drop_duplicates(subset=["txn_id"], keep="last")


if __name__ == "__main__":
    raw_members = parse_flat_file("data/sample_members.txt")
    staged, quarantine = validate_and_stage(raw_members)
    country_tables = split_by_country_latest_wins(staged)
    redemptions = flatten_redemptions_json("data/sample_redemptions.json")

    print(f"Staged: {len(staged)} | Quarantined: {len(quarantine)}")
    print("Country splits:", {k: len(v) for k, v in country_tables.items()})
    print("\nJoined Redemptions + Member Profiles:")
    joined = redemptions.merge(staged, on="member_id", how="left")
    print(joined[["txn_id", "member_id", "member_name", "country_code", "partner", "miles_redeemed", "status"]])