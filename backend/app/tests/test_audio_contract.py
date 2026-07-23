import json
import math
from pathlib import Path

import pytest
import numpy as np

from app.core.instruments.profiles import get_instrument_profile
from app.core.music.theory import (
    frequency_to_pitch_frame,
    midi_to_frequency,
    note_label_to_midi,
    round_midi_half_up,
    transpose_concert_to_written,
)
from app.core.recommendations.rules import generate_note_recommendation
from app.core.pitch.detector import yin_pitch
from app.core.sessions.segmentation import segment_note_events


ROOT_DIR = Path(__file__).resolve().parents[3]


def fixture(name: str):
    with open(ROOT_DIR / "fixtures" / name, encoding="utf-8") as handle:
        return json.load(handle)


def test_portable_play_along_contract_is_complete_for_python_and_swift_loaders():
    contract = fixture("play_along_contract.json")
    assert contract["policy"] == {
        "centered_cents_inclusive": 5,
        "accepted_cents_inclusive": 15,
        "hold_ms": 2000,
        "minimum_confidence": 0.65,
        "minimum_samples": 5,
        "attack_trim_ms": 120,
        "maximum_dropout_ms": 250,
    }
    assert {case["expected_rating"] for case in contract["rating_cases"]} == {"missed", "excellent", "close", "off"}
    assert [(case["in_tune_percent"], case["expected_stars"]) for case in contract["star_cases"]] == [
        (None, 0),
        (69.9, 0),
        (70, 1),
        (85, 2),
        (95, 3),
    ]


def test_pitch_math_fixture_uses_cross_language_half_up_midpoint_rounding():
    for case in fixture("pitch_math_cases.json"):
        frame = frequency_to_pitch_frame(
            case["frequency_hz"],
            0.99,
            0.1,
            0,
            case["instrument_id"],
            case["reference_pitch_hz"],
        )
        assert frame.nearest_midi == case["expected_nearest_midi"], case["name"]
        assert frame.concert_note_name == case["expected_concert_note"], case["name"]
        assert frame.concert_octave == case["expected_concert_octave"], case["name"]
        assert frame.cents_deviation == pytest.approx(case["expected_cents"], abs=0.05), case["name"]
    assert round_midi_half_up(68.5) == 69
    assert round_midi_half_up(70.5) == 71


def test_instrument_transposition_and_range_fixture_matches_backend_profiles():
    for case in fixture("transposition_cases.json"):
        profile = get_instrument_profile(case["instrument_id"])
        assert transpose_concert_to_written(case["concert_midi"], profile) == case["expected_written_midi"], case["name"]
        assert profile.min_frequency_hz == case["expected_min_frequency_hz"], case["name"]
        assert profile.max_frequency_hz == case["expected_max_frequency_hz"], case["name"]
        assert profile.typical_range_written == case["expected_typical_range_written"], case["name"]


def test_reference_tone_fixture_has_exact_frequency_and_zero_detune():
    for case in fixture("reference_tone_cases.json"):
        profile = get_instrument_profile(case["instrument_id"])
        written_midi = note_label_to_midi(case["written_note"]) + case["interval_semitones"]
        concert_midi = written_midi - profile.transposition_semitones
        frequency = midi_to_frequency(concert_midi, case["reference_pitch_hz"])
        assert frequency == pytest.approx(case["expected_frequency_hz"], abs=1e-10), case["name"]
        assert case["expected_detune_cents"] == 0, case["name"]

    for case in fixture("drone_dyad_cases.json"):
        profile = get_instrument_profile(case["instrument_id"])
        written_midi = note_label_to_midi(case["written_note"])
        concert_midis = [written_midi, written_midi + case["interval_semitones"]]
        frequencies = [midi_to_frequency(midi - profile.transposition_semitones, case["reference_pitch_hz"]) for midi in concert_midis]
        assert frequencies == pytest.approx(case["expected_frequencies_hz"], abs=1e-10), case["name"]
        assert case["expected_detune_cents"] == [0, 0], case["name"]


def _fixture_frame(item):
    return {
        "timestamp_ms": item["timestamp_ms"],
        "frequency_hz": 440.0 if item.get("is_valid_for_recording", True) else None,
        "confidence": 0.99 if item.get("is_valid_for_recording", True) else 0.1,
        "rms": 0.1,
        "midi_note_float": 69.0 if item.get("is_valid_for_recording", True) else None,
        "nearest_midi": 69 if item.get("is_valid_for_recording", True) else None,
        "concert_note_name": item["concert_note_name"],
        "concert_octave": item["concert_octave"],
        "written_note_name": item["written_note_name"],
        "written_octave": item["written_octave"],
        "cents_deviation": item["cents_deviation"],
        "tuning_status": item["tuning_status"],
        "instrument_id": "trumpet",
        "reference_pitch_hz": 440.0,
        "is_valid_for_recording": item.get("is_valid_for_recording", True),
    }


def test_segmentation_fixture_covers_duration_median_stability_and_dropout():
    for case in fixture("note_segmentation_cases.json"):
        events = segment_note_events([_fixture_frame(item) for item in case["frames"]])
        assert len(events) == len(case["expected_events"]), case["name"]
        for event, expected in zip(events, case["expected_events"]):
            for key in ("written_note", "written_octave", "duration_ms", "sample_count"):
                assert event[key] == expected[key], "%s: %s" % (case["name"], key)
            for key in ("avg_signed_cents", "median_cents", "stddev_cents", "in_tune_percentage", "stability_score"):
                assert event[key] == pytest.approx(expected[key], abs=1e-9), "%s: %s" % (case["name"], key)


def test_recommendation_fixture_never_promotes_unstable_evidence_as_centered():
    for case in fixture("recommendation_cases.json"):
        recommendation = generate_note_recommendation(case["note_stats"], get_instrument_profile(case["instrument_id"]))
        assert recommendation["category"] == case["expected_category"], case["name"]
        assert recommendation["related_note"] == case["expected_related_note"], case["name"]
        if case["expected_category"] == "Inconsistent pitch":
            assert "is generally centered" not in recommendation["message"].lower()


def _p95(values):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)]


def test_synthetic_pitch_quality_gate_is_executable_not_physical_mic_evidence():
    contract = fixture("pitch_quality_contract.json")
    sample_rate = contract["sample_rate_hz"]
    frame_size = contract["frame_size"]
    amplitudes = contract["harmonic_amplitudes"]
    time_axis = np.arange(frame_size, dtype=np.float64) / sample_rate
    signed_errors = []
    correct = 0
    gross_octave_errors = 0
    for case in contract["cases"]:
        samples = sum(
            amplitude * np.sin(2 * np.pi * case["frequency_hz"] * (index + 1) * time_axis)
            for index, amplitude in enumerate(amplitudes)
        ).astype(np.float32)
        frequency, confidence = yin_pitch(samples, sample_rate, 30, 1500)
        assert confidence > 0.95, case["note"]
        midi = 69 + 12 * math.log2(frequency / 440)
        signed_error = (midi - case["midi"]) * 100
        signed_errors.append(signed_error)
        assert signed_error == pytest.approx(case["expected_python_signed_cents_error"], abs=0.001), case["note"]
        correct += round_midi_half_up(midi) == case["midi"]
        gross_octave_errors += abs(midi - case["midi"]) >= 11.5

    thresholds = contract["thresholds"]
    absolute_errors = [abs(value) for value in signed_errors]
    assert correct / len(signed_errors) * 100 >= thresholds["steady_note_octave_accuracy_min_percent"]
    assert gross_octave_errors / len(signed_errors) * 100 <= thresholds["gross_octave_error_max_percent"]
    assert np.median(absolute_errors) <= thresholds["median_abs_cents_error_max"]
    assert _p95(absolute_errors) <= thresholds["p95_abs_cents_error_max"]
    assert frame_size / sample_rate * 1000 <= thresholds["onset_p95_ms_max"]
