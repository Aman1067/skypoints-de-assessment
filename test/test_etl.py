from datetime import date
import pandas as pd
from src.etl import (
    flatten_redemptions_json,
    parse_flat_file,
    split_by_country_latest_wins,
    validate_and_stage,
)


def test_parse_flat_file_handles_missing_pipe_and_header():
    df = parse_flat_file("data/sample_members.txt")
    assert len(df) == 5
    assert "Nora" in df["member_name"].values  # Missing leading pipe row


def test_validate_and_stage_derives_age_stale_and_country_codes():
    raw = parse_flat_file("data/sample_members.txt")
    staged, quarantine = validate_and_stage(raw, ref_date=date(2026, 11, 21))

    assert len(quarantine) == 0
    assert len(staged) == 5
    assert set(staged["country_code"]) == {"USA", "IND", "PHL", "CAN", "AUS"}
    assert staged.loc[staged["member_id"] == "223457", "age"].iloc[0] == 41
    assert bool(staged.loc[staged["member_id"] == "223457", "stale_member"].iloc[0]) is True


def test_quarantine_catches_bad_dates_and_missing_keys():
    dirty_df = pd.DataFrame([
        {
            "member_name": "BadDateUser",
            "member_id": "999",
            "enrollment_date": "20211313",  # Invalid month 13
            "last_flight_date": "20220105",
            "tier_code": "GLD",
            "agent_name": "Sam",
            "state": "NSW",
            "country": "AUS",
            "dob": "3051985",
            "is_active": "A",
        }
    ])
    staged, quarantine = validate_and_stage(dirty_df, ref_date=date(2026, 11, 21))
    assert len(staged) == 0
    assert len(quarantine) == 1
    assert "INVALID_ENROLLMENT_DATE" in quarantine["failure_reason"].iloc[0]


def test_latest_record_wins_across_country_move():
    df = pd.DataFrame([
        {"member_id": "101", "country_code": "USA", "last_flight_date": date(2024, 1, 1), "enrollment_date": date(2020, 1, 1)},
        {"member_id": "101", "country_code": "IND", "last_flight_date": date(2025, 6, 1), "enrollment_date": date(2020, 1, 1)},
    ])
    splits = split_by_country_latest_wins(df)
    assert "USA" not in splits
    assert "IND" in splits
    assert len(splits["IND"]) == 1


def test_flatten_redemptions_json():
    df = flatten_redemptions_json("data/sample_redemptions.json")
    assert len(df) == 2
    assert df["member_id"].iloc[0] == "223457"
    assert set(df["txn_id"]) == {"RX10091", "RX10092"}