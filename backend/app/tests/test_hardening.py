import datetime as dt
import math

import numpy as np
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.api.routes import _filtered_events
from app.core.analytics.stats import build_instrument_heatmap, calculate_most_improved_notes, calculate_note_stats
from app.core.instruments.profiles import get_instrument_profile
from app.core.music.theory import MIN_RECORDING_CONFIDENCE, frequency_to_pitch_frame, midi_to_frequency
from app.core.pitch.detector import yin_pitch
from app.db.database import Base
from app.db.seed import seed_demo_data
from app.main import app
from app.models.db import NoteEvent, PitchSample, PracticeSession, User
from app.services.session_service import save_pitch_frames


def _test_db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()


def _session(db, user_id: int, instrument_id: str, started_at: dt.datetime):
    if db.query(User).filter(User.id == user_id).first() is None:
        db.add(User(id=user_id, name="Test User", role="student", primary_instrument_id=instrument_id))
        db.commit()
    row = PracticeSession(
        user_id=user_id,
        instrument_id=instrument_id,
        name="Test session",
        started_at=started_at,
        created_at=started_at,
        duration_seconds=8,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def _event(db, session, note: str, octave: int, avg_abs: float, avg_signed: float = None):
    avg_signed = avg_abs if avg_signed is None else avg_signed
    row = NoteEvent(
        session_id=session.id,
        instrument_id=session.instrument_id,
        written_note=note,
        written_octave=octave,
        concert_note=note,
        concert_octave=octave,
        started_at_ms=0,
        ended_at_ms=4000,
        duration_ms=4000,
        sample_count=20,
        avg_signed_cents=avg_signed,
        avg_abs_cents=avg_abs,
        median_cents=avg_signed,
        stddev_cents=2,
        min_cents=avg_signed - 2,
        max_cents=avg_signed + 2,
        in_tune_percentage=50,
        stability_score=90,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def test_invalid_instrument_rejected_by_api():
    with TestClient(app) as client:
        response = client.post("/api/sessions/start", json={"instrument_id": "trumpett", "reference_pitch_hz": 440})
        assert response.status_code == 400
        response = client.get("/api/recommendations?instrument_id=trumpett")
        assert response.status_code == 400


def test_websocket_audio_frame_returns_pitch_frame_for_synthetic_pcm():
    sample_rate = 48000
    t = np.arange(4096) / sample_rate
    samples = (0.8 * np.sin(2 * math.pi * 440.0 * t)).tolist()
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json(
                {
                    "type": "audio_frame",
                    "instrument_id": "trumpet",
                    "reference_pitch_hz": 440,
                    "sample_rate": sample_rate,
                    "pcm": samples,
                }
            )
            message = websocket.receive_json()
    assert message["type"] == "pitch_frame"
    assert message["frame"]["tuning_status"] == "in_tune"
    assert message["frame"]["written_note_name"] == "B"


def test_date_filters_change_returned_analytics():
    with TestClient(app) as client:
        all_rows = client.get("/api/analytics/notes?instrument_id=trumpet").json()
        future_rows = client.get("/api/analytics/notes?instrument_id=trumpet&date_from=2099-01-01&date_to=2099-01-02").json()
        assert len(all_rows) > 0
        assert future_rows == []


def test_filtered_events_use_session_started_at_dates():
    db = _test_db()
    try:
        old = _session(db, 10, "trumpet", dt.datetime(2026, 6, 1))
        recent = _session(db, 10, "trumpet", dt.datetime(2026, 6, 15))
        _event(db, old, "D", 5, 16)
        _event(db, recent, "D", 5, 6)
        rows = _filtered_events(db, 10, "trumpet", dt.datetime(2026, 6, 10), dt.datetime(2026, 6, 20))
        assert len(rows) == 1
        assert rows[0].session_id == recent.id
    finally:
        db.close()


def test_current_previous_period_improvement_uses_dates():
    db = _test_db()
    try:
        previous = _session(db, 11, "trumpet", dt.datetime(2026, 6, 4))
        current = _session(db, 11, "trumpet", dt.datetime(2026, 6, 14))
        _event(db, previous, "D", 5, 18)
        _event(db, current, "D", 5, 7)
        previous_events = _filtered_events(db, 11, "trumpet", dt.datetime(2026, 6, 1), dt.datetime(2026, 6, 8))
        current_events = _filtered_events(db, 11, "trumpet", dt.datetime(2026, 6, 8), dt.datetime(2026, 6, 15))
        improved = calculate_most_improved_notes(
            calculate_note_stats(current_events),
            calculate_note_stats(previous_events),
        )
        assert improved[0]["note_label"] == "D5"
        assert improved[0]["improvement"] == 11
    finally:
        db.close()


def test_full_heatmap_includes_missing_insufficient_cells():
    profile = get_instrument_profile("trumpet")
    cells = build_instrument_heatmap(
        [{"note_label": "D5", "written_note": "D", "written_octave": 5, "avg_signed_cents": 12, "avg_abs_cents": 12, "median_cents": 12, "stddev_cents": 2, "in_tune_percentage": 20, "duration_seconds": 4, "duration_ms": 4000, "sample_count": 20, "event_count": 1, "stability_score": 88, "trend": "Mostly sharp", "severity": "moderate issue", "problem_severity": 40}],
        profile,
    )
    labels = [cell["note_label"] for cell in cells]
    assert "F#3" in labels
    assert "D5" in labels
    assert "C6" in labels
    missing = next(cell for cell in cells if cell["note_label"] == "F#3")
    measured = next(cell for cell in cells if cell["note_label"] == "D5")
    assert missing["has_data"] is False
    assert missing["severity_color"] == "insufficient"
    assert measured["has_data"] is True
    assert measured["severity_color"] == "orange"


def test_yin_fallback_clean_tones_are_accurate():
    sample_rate = 48000
    duration = 0.12
    t = np.arange(int(sample_rate * duration)) / sample_rate
    cases = [
        (440.0, 80, 1000),
        (466.16, 80, 1000),
        (midi_to_frequency(62), 130, 1500),
        (midi_to_frequency(48), 50, 700),
        (midi_to_frequency(34), 30, 500),
    ]
    for frequency, min_freq, max_freq in cases:
        samples = 0.8 * np.sin(2 * math.pi * frequency * t)
        estimated, confidence = yin_pitch(samples, sample_rate, min_freq, max_freq)
        assert confidence >= MIN_RECORDING_CONFIDENCE
        assert abs(1200 * math.log2(estimated / frequency)) < 3.0


def test_yin_fallback_detects_plus_and_minus_ten_cents():
    sample_rate = 48000
    t = np.arange(int(sample_rate * 0.12)) / sample_rate
    for cents in (10, -10):
        frequency = 440.0 * (2 ** (cents / 1200.0))
        samples = 0.8 * np.sin(2 * math.pi * frequency * t)
        estimated, _ = yin_pitch(samples, sample_rate, 80, 1000)
        frame = frequency_to_pitch_frame(estimated, 0.95, 0.1, 0, "trombone", 440.0)
        assert abs((frame.cents_deviation or 0) - cents) < 3.0


def test_batch_save_commits_multiple_pitch_frames():
    db = _test_db()
    try:
        session = _session(db, 12, "trumpet", dt.datetime(2026, 6, 15))
        frame_a = frequency_to_pitch_frame(midi_to_frequency(60), 0.95, 0.1, 0, "trumpet", 440.0).to_dict()
        frame_b = frequency_to_pitch_frame(midi_to_frequency(62), 0.95, 0.1, 110, "trumpet", 440.0).to_dict()
        samples = save_pitch_frames(db, session.id, [frame_a, frame_b])
        assert len(samples) == 2
    finally:
        db.close()


def test_low_confidence_pitch_frames_are_not_recordable_or_saved():
    low_confidence = MIN_RECORDING_CONFIDENCE - 0.01
    frame = frequency_to_pitch_frame(midi_to_frequency(69), low_confidence, 0.1, 0, "trombone", 440.0)
    assert frame.tuning_status == "unstable"
    assert frame.is_valid_for_recording is False

    db = _test_db()
    try:
        session = _session(db, 13, "trombone", dt.datetime(2026, 6, 15))
        forged = frequency_to_pitch_frame(midi_to_frequency(69), MIN_RECORDING_CONFIDENCE, 0.1, 0, "trombone", 440.0).to_dict()
        forged["confidence"] = low_confidence
        forged["is_valid_for_recording"] = True
        assert save_pitch_frames(db, session.id, [forged]) == []
    finally:
        db.close()


def test_fresh_seed_creates_recordable_samples_and_note_events():
    db = _test_db()
    try:
        seed_demo_data(db)
        sessions = db.query(PracticeSession).all()
        assert len(sessions) >= 7
        assert db.query(PitchSample).count() > 0
        assert db.query(NoteEvent).count() > 0
        assert all(session.samples for session in sessions)
        assert all(session.note_events for session in sessions)
        assert db.query(PitchSample).filter(PitchSample.confidence < MIN_RECORDING_CONFIDENCE).count() == 0
    finally:
        db.close()
