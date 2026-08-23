import json
import math
import statistics
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
from app.core.pitch.detector import PitchDetector, yin_pitch
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
        "minimum_confidence": 0.95,
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
    assert contract["schema_version"] == 2
    assert "synthetic" in contract["temporal_evidence_kind"]
    assert {case["name"] for case in contract["temporal_cases"]} == {
        "exact two-second boundary",
        "brief confidence dropout pauses without filling or resetting",
        "long confidence dropout exceeds grace and resets",
        "confident wrong note resets accumulated hold",
        "attack transient is trimmed before scoring",
        "median scoring rejects a single detector outlier",
    }


def _play_along_rating(cents):
    if cents is None:
        return "missed"
    if abs(cents) <= 5:
        return "excellent"
    if abs(cents) <= 15:
        return "close"
    return "off"


def _evaluate_play_along_timeline(case, policy):
    note_index = 0
    first_match_ms = None
    last_match_ms = None
    previous_frame_ms = None
    previous_matched = False
    held_ms = 0
    cents_samples = []
    results = []
    checkpoints = {item["after_frame_index"]: item for item in case["checkpoints"]}

    def reset():
        nonlocal first_match_ms, last_match_ms, previous_frame_ms, previous_matched, held_ms, cents_samples
        first_match_ms = None
        last_match_ms = None
        previous_frame_ms = None
        previous_matched = False
        held_ms = 0
        cents_samples = []

    for frame_index, frame in enumerate(case["frames"]):
        timestamp_ms = frame["timestamp_ms"]
        target = case["notes"][note_index]
        confident = frame["confidence"] >= policy["minimum_confidence"] and frame["written_note"] is not None
        matches = confident and frame["written_note"] == target and frame["cents"] is not None and math.isfinite(frame["cents"])

        if matches:
            if last_match_ms is not None and timestamp_ms - last_match_ms > policy["maximum_dropout_ms"]:
                reset()
            if first_match_ms is None:
                first_match_ms = timestamp_ms
            if previous_matched and previous_frame_ms is not None:
                held_ms += max(0, timestamp_ms - previous_frame_ms)
            last_match_ms = timestamp_ms
            previous_frame_ms = timestamp_ms
            previous_matched = True
            cents_samples.append((timestamp_ms, frame["cents"]))

            if held_ms >= policy["hold_ms"] and len(cents_samples) >= policy["minimum_samples"]:
                sustained = [
                    cents
                    for sample_ms, cents in cents_samples
                    if sample_ms - first_match_ms >= policy["attack_trim_ms"]
                ]
                source = sustained if len(sustained) >= min(policy["minimum_samples"], 3) else [item[1] for item in cents_samples]
                scored = statistics.median(source)
                if abs(scored) <= policy["accepted_cents_inclusive"]:
                    results.append(
                        {
                            "name": target,
                            "median_cents": round(scored, 1),
                            "sample_count": len(cents_samples),
                            "rating": _play_along_rating(scored),
                        }
                    )
                    note_index += 1
                reset()
        elif confident and frame["written_note"] != target:
            reset()
        else:
            previous_frame_ms = timestamp_ms
            previous_matched = False
            if last_match_ms is not None and timestamp_ms - last_match_ms > policy["maximum_dropout_ms"]:
                reset()

        checkpoint = checkpoints.get(frame_index)
        if checkpoint:
            assert case["notes"][note_index] == checkpoint["expected_current_note"], case["name"]
            assert held_ms == checkpoint["expected_held_ms"], case["name"]
            assert len(results) == checkpoint["expected_result_count"], case["name"]
            assert (note_index >= len(case["notes"])) is checkpoint["expected_done"], case["name"]

    return results


def test_play_along_temporal_fixture_has_self_consistent_reference_outcomes():
    """Python owns no Play-Along runtime; this is the portable fixture's reference oracle."""
    contract = fixture("play_along_contract.json")
    for case in contract["temporal_cases"]:
        assert _evaluate_play_along_timeline(case, contract["policy"]) == case["expected_results"], case["name"]


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
        assert profile.min_frequency_hz == case["expected_detector_min_frequency_hz"], case["name"]
        assert profile.max_frequency_hz == case["expected_detector_max_frequency_hz"], case["name"]
        assert profile.typical_range_written == case["expected_typical_range_written"], case["name"]

        # The legacy keys remain aliases for practical sounding limits until
        # every app consumer has migrated to the explicit schema.
        assert case["expected_min_frequency_hz"] == case["expected_practical_min_frequency_hz"]
        assert case["expected_max_frequency_hz"] == case["expected_practical_max_frequency_hz"]
        practical_start, practical_end = profile.typical_range_written.split("-", 1)
        assert midi_to_frequency(note_label_to_midi(practical_start) - profile.transposition_semitones) == pytest.approx(
            case["expected_practical_min_frequency_hz"]
        )
        assert midi_to_frequency(note_label_to_midi(practical_end) - profile.transposition_semitones) == pytest.approx(
            case["expected_practical_max_frequency_hz"]
        )


@pytest.mark.parametrize("reference_pitch_hz", [430.0, 440.0, 450.0])
def test_detector_window_boundaries_are_inclusive_and_independent_of_practical_range(reference_pitch_hz):
    profile = get_instrument_profile("trumpet")
    practical_written_midis = range(note_label_to_midi("F#3"), note_label_to_midi("C6") + 1)

    for frequency_hz in (profile.min_frequency_hz, profile.max_frequency_hz):
        frame = frequency_to_pitch_frame(
            frequency_hz,
            confidence=0.99,
            rms=0.1,
            timestamp_ms=0,
            instrument_id=profile.id,
            reference_pitch_hz=reference_pitch_hz,
        )
        assert frame.is_valid_for_recording is True
        assert frame.nearest_midi is not None
        assert frame.written_note_name is not None
        written_midi = frame.nearest_midi + profile.transposition_semitones
        assert written_midi not in practical_written_midis

    for frequency_hz in (
        math.nextafter(profile.min_frequency_hz, 0.0),
        math.nextafter(profile.max_frequency_hz, math.inf),
    ):
        frame = frequency_to_pitch_frame(
            frequency_hz,
            confidence=0.99,
            rms=0.1,
            timestamp_ms=0,
            instrument_id=profile.id,
            reference_pitch_hz=reference_pitch_hz,
        )
        assert frame.is_valid_for_recording is False
        assert frame.nearest_midi is None
        assert frame.save_eligibility_reason == "outside instrument range"


def test_b_flat_treble_low_brass_profiles_keep_major_ninth_transposition_and_family_detector_window():
    for instrument_id in ("baritone", "euphonium-treble"):
        profile = get_instrument_profile(instrument_id)
        assert profile.transposition_semitones == 14
        assert transpose_concert_to_written(46, profile) == 60
        assert (profile.min_frequency_hz, profile.max_frequency_hz) == (55.0, 800.0)


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


def _harmonic_tone(contract, frequency_hz, amplitude_multiplier=1):
    sample_rate = contract["sample_rate_hz"]
    frame_size = contract["frame_size"]
    time_axis = np.arange(frame_size, dtype=np.float64) / sample_rate
    return sum(
        amplitude * amplitude_multiplier * np.sin(2 * np.pi * frequency_hz * (index + 1) * time_axis)
        for index, amplitude in enumerate(contract["harmonic_amplitudes"])
    ).astype(np.float32)


def test_synthetic_steady_pitch_quality_gate_is_executable_not_physical_mic_evidence():
    contract = fixture("pitch_quality_contract.json")
    sample_rate = contract["sample_rate_hz"]
    signed_errors = []
    correct = 0
    gross_octave_errors = 0
    for case in contract["cases"]:
        samples = _harmonic_tone(contract, case["frequency_hz"])
        frequency, confidence = yin_pitch(samples, sample_rate, 30, 1500)
        assert confidence > 0.95, case["note"]
        midi = 69 + 12 * math.log2(frequency / 440)
        signed_error = (midi - case["midi"]) * 100
        signed_errors.append(signed_error)
        assert signed_error == pytest.approx(case["expected_python_signed_cents_error"], abs=0.001), case["note"]
        correct += round_midi_half_up(midi) == case["midi"]
        gross_octave_errors += abs(signed_error) >= contract["benchmark_policy"]["gross_octave_error_cents_inclusive"]

    thresholds = contract["thresholds"]
    absolute_errors = [abs(value) for value in signed_errors]
    assert correct / len(signed_errors) * 100 >= thresholds["steady_note_octave_accuracy_min_percent"]
    assert gross_octave_errors / len(signed_errors) * 100 <= thresholds["gross_octave_error_max_percent"]
    assert np.median(absolute_errors) <= thresholds["median_abs_cents_error_max"]
    assert _p95(absolute_errors) <= thresholds["p95_abs_cents_error_max"]


def test_pitch_quality_benchmark_semantics_cover_gross_error_boundary_and_nearest_note_tie():
    contract = fixture("pitch_quality_contract.json")
    policy = contract["benchmark_policy"]
    assert policy["accuracy_definition"] == "nearest_midi_half_up_equals_expected_midi"

    for case in contract["benchmark_semantics_cases"]:
        signed_error_cents = (case["detected_midi"] - case["expected_midi"]) * 100
        assert (round_midi_half_up(case["detected_midi"]) == case["expected_midi"]) is case["expected_accurate"], case["name"]
        assert (
            abs(signed_error_cents) >= policy["gross_octave_error_cents_inclusive"]
        ) is case["expected_gross_octave_error"], case["name"]


def test_synthetic_onset_p95_measures_time_to_first_detector_lock():
    contract = fixture("pitch_quality_contract.json")
    protocol = contract["synthetic_onset_protocol"]
    assert "synthetic" in protocol["evidence_kind"]
    assert "not physical microphone" in protocol["evidence_kind"]
    frame_duration_ms = contract["frame_size"] / contract["sample_rate_hz"] * 1000
    onset_latencies_ms = []

    for case in contract["cases"]:
        detector = PitchDetector(contract["sample_rate_hz"], contract["frame_size"])
        onset_frame = next(index for index, amplitude in enumerate(case["onset_amplitude_multipliers"]) if amplitude > 0)
        first_lock_frame = None
        for frame_index, amplitude in enumerate(case["onset_amplitude_multipliers"]):
            estimate = detector.estimate(
                _harmonic_tone(contract, case["frequency_hz"], amplitude),
                contract["sample_rate_hz"],
                30,
                1500,
            )
            frequency_hz = float(estimate["frequency_hz"])
            cents_error = math.inf if frequency_hz <= 0 else abs(1200 * math.log2(frequency_hz / case["frequency_hz"]))
            if (
                frequency_hz > 0
                and float(estimate["confidence"]) >= protocol["lock_confidence_min"]
                and cents_error <= protocol["lock_frequency_tolerance_cents_max"]
            ):
                first_lock_frame = frame_index
                break

        assert first_lock_frame is not None, case["note"]
        assert first_lock_frame >= onset_frame, case["note"]
        onset_latencies_ms.append((first_lock_frame - onset_frame + 1) * frame_duration_ms)

    assert len(onset_latencies_ms) == len(contract["cases"])
    assert _p95(onset_latencies_ms) <= contract["thresholds"]["onset_p95_ms_max"]
