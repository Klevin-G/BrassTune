import json
import math
from pathlib import Path

from app.core.analytics.stats import calculate_most_improved_notes, heatmap_severity
from app.core.instruments.profiles import get_instrument_profile
from app.core.music.theory import (
    calculate_cents_deviation,
    frequency_to_midi,
    frequency_to_pitch_frame,
    midi_to_note_name,
    midi_to_frequency,
    transpose_concert_to_written,
)
from app.core.recommendations.rules import generate_note_recommendation
from app.core.sessions.segmentation import compute_session_summary, segment_note_events

ROOT_DIR = Path(__file__).resolve().parents[3]


def _fixture(name: str):
    with open(ROOT_DIR / "fixtures" / name, encoding="utf-8") as file:
        return json.load(file)


def test_a4_440_maps_to_a4_zero_cents():
    frame = frequency_to_pitch_frame(440.0, 0.95, 0.1, 0, "trombone", 440.0)
    assert frame.concert_note_name == "A"
    assert frame.concert_octave == 4
    assert frame.nearest_midi == 69
    assert abs(frame.cents_deviation or 0) < 0.001
    assert frame.tuning_status == "in_tune"


def test_466_16_maps_near_bb4():
    frame = frequency_to_pitch_frame(466.16, 0.95, 0.1, 0, "trombone", 440.0)
    assert frame.concert_note_name == "Bb"
    assert frame.concert_octave == 4
    assert abs(frame.cents_deviation or 0) < 0.05


def test_plus_10_cents_calculation():
    target = midi_to_frequency(69, 440.0)
    raised = target * (2 ** (10 / 1200.0))
    cents = calculate_cents_deviation(raised, target)
    assert abs(cents - 10) < 0.001


def test_trumpet_written_transposition():
    trumpet = get_instrument_profile("trumpet")
    assert transpose_concert_to_written(60, trumpet) == 62
    frame = frequency_to_pitch_frame(midi_to_frequency(60), 0.95, 0.1, 0, "trumpet", 440.0)
    assert frame.concert_note_name == "C"
    assert frame.written_note_name == "D"
    assert frame.written_octave == 4


def test_french_horn_written_transposition():
    horn = get_instrument_profile("horn")
    assert transpose_concert_to_written(60, horn) == 67
    frame = frequency_to_pitch_frame(midi_to_frequency(60), 0.95, 0.1, 0, "horn", 440.0)
    assert frame.written_note_name == "G"
    assert frame.written_octave == 4


def _frame(ts, note="D", octave=5, cents=8.0, status="sharp"):
    return {
        "timestamp_ms": ts,
        "frequency_hz": 600.0,
        "confidence": 0.9,
        "rms": 0.1,
        "midi_note_float": 74.0,
        "nearest_midi": 74,
        "concert_note_name": "C",
        "concert_octave": 5,
        "written_note_name": note,
        "written_octave": octave,
        "cents_deviation": cents,
        "tuning_status": status,
        "instrument_id": "trumpet",
        "reference_pitch_hz": 440.0,
        "is_valid_for_recording": True,
    }


def test_note_event_segmentation():
    frames = [_frame(0), _frame(100), _frame(200), _frame(420, "G", 4, -5, "flat"), _frame(520, "G", 4, -4, "in_tune")]
    events = segment_note_events(frames, max_merge_gap_ms=180, min_duration_ms=100)
    assert len(events) == 2
    assert events[0]["written_note"] == "D"
    assert events[1]["written_note"] == "G"


def test_session_average_calculations_weight_by_duration():
    summary = compute_session_summary(
        [
            {"duration_ms": 1000, "avg_signed_cents": 10, "avg_abs_cents": 10, "in_tune_percentage": 40},
            {"duration_ms": 3000, "avg_signed_cents": -2, "avg_abs_cents": 4, "in_tune_percentage": 90},
        ]
    )
    assert math.isclose(summary["average_signed_cents"], 1.0)
    assert math.isclose(summary["average_abs_cents"], 5.5)
    assert math.isclose(summary["in_tune_percentage"], 77.5)


def test_heatmap_severity_classifications():
    assert heatmap_severity({"duration_seconds": 1, "sample_count": 20, "avg_abs_cents": 2}) == "insufficient"
    assert heatmap_severity({"duration_seconds": 4, "sample_count": 20, "avg_abs_cents": 4}) == "green"
    assert heatmap_severity({"duration_seconds": 4, "sample_count": 20, "avg_abs_cents": 9}) == "yellow"
    assert heatmap_severity({"duration_seconds": 4, "sample_count": 20, "avg_abs_cents": 13}) == "orange"
    assert heatmap_severity({"duration_seconds": 4, "sample_count": 20, "avg_abs_cents": 18}) == "red"


def test_recommendation_rules():
    rec = generate_note_recommendation(
        {
            "note_label": "D5",
            "avg_signed_cents": 14,
            "avg_abs_cents": 15,
            "stddev_cents": 4,
            "duration_seconds": 10,
            "in_tune_percentage": 42,
        },
        get_instrument_profile("trumpet"),
    )
    assert rec["category"] == "Sharp tendency"
    assert "sharp" in rec["message"]
    assert rec["related_note"] == "D5"


def test_shared_pitch_math_fixtures():
    for case in _fixture("pitch_math_cases.json"):
        frame = frequency_to_pitch_frame(case["frequency_hz"], 0.99, 0.1, 0, case["instrument_id"], case["reference_pitch_hz"])
        assert frame.concert_note_name == case["expected_concert_note"]
        assert frame.concert_octave == case["expected_concert_octave"]
        assert frame.written_note_name == case["expected_written_note"]
        assert frame.written_octave == case["expected_written_octave"]
        assert frame.nearest_midi == case["expected_nearest_midi"]
        assert abs((frame.cents_deviation or 0) - case["expected_cents"]) < 0.05


def test_shared_transposition_fixtures():
    for case in _fixture("transposition_cases.json"):
        profile = get_instrument_profile(case["instrument_id"])
        written_midi = transpose_concert_to_written(case["concert_midi"], profile)
        written = midi_to_note_name(written_midi, profile.preferred_note_spellings)
        assert written_midi == case["expected_written_midi"]
        assert "%s%s" % (written["note"], written["octave"]) == case["expected_written_label"]


def test_shared_segmentation_fixtures():
    for case in _fixture("note_segmentation_cases.json"):
        frames = []
        for item in case["frames"]:
            frames.append(
                {
                    "timestamp_ms": item["timestamp_ms"],
                    "frequency_hz": 440.0,
                    "confidence": 0.99,
                    "rms": 0.1,
                    "midi_note_float": 69.0,
                    "nearest_midi": 69,
                    "concert_note_name": item["concert_note_name"],
                    "concert_octave": item["concert_octave"],
                    "written_note_name": item["written_note_name"],
                    "written_octave": item["written_octave"],
                    "cents_deviation": item["cents_deviation"],
                    "tuning_status": item["tuning_status"],
                    "instrument_id": "trumpet",
                    "reference_pitch_hz": 440.0,
                    "is_valid_for_recording": True,
                }
            )
        events = segment_note_events(frames, max_merge_gap_ms=180, min_duration_ms=100)
        assert len(events) == len(case["expected_events"])
        for event, expected in zip(events, case["expected_events"]):
            assert event["written_note"] == expected["written_note"]
            assert event["written_octave"] == expected["written_octave"]
            assert abs(event["avg_signed_cents"] - expected["avg_signed_cents"]) < 0.01


def test_shared_recommendation_fixtures():
    for case in _fixture("recommendation_cases.json"):
        rec = generate_note_recommendation(case["note_stats"], get_instrument_profile(case["instrument_id"]))
        assert rec["category"] == case["expected_category"]
        assert rec["related_note"] == case["expected_related_note"]


def test_most_improved_notes():
    improved = calculate_most_improved_notes(
        [{"note_label": "A4", "avg_abs_cents": 5, "duration_seconds": 8}],
        [{"note_label": "A4", "avg_abs_cents": 13, "duration_seconds": 9}],
    )
    assert improved[0]["improvement"] == 8
