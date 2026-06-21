import datetime as dt
import importlib.util
import io
import json
import math
import asyncio
import zipfile
from pathlib import Path

import numpy as np
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.main as main_module
from app.api.auth import AuthContext, _sync_supabase_user
from app.api.routes import _filtered_events, _group_scoped_sessions, _read_limited_body, delete_my_account
from app.core.analytics.stats import build_instrument_heatmap, calculate_most_improved_notes, calculate_note_stats
from app.core.instruments.profiles import get_instrument_profile
from app.core.music.theory import MIN_RECORDING_CONFIDENCE, frequency_to_pitch_frame, midi_to_frequency
from app.core.pitch.detector import yin_pitch
from app.db.database import Base, DATABASE_URL, engine
from app.db.maintenance import clear_practice_data, repair_demo_data
from app.db.seed import seed_demo_data
from app.main import app
from app.models.db import AccountDeletionJob, Group, GroupMember, NoteEvent, PitchSample, PracticeSession, User
from app.schemas.schemas import MAX_BATCH_PITCH_FRAMES, AccountDeletionRequest
from app.services.audio_storage import delete_audio_for_session
from app.services.session_service import save_pitch_frames


def _test_db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()


def test_sqlite_engine_uses_busy_timeout_for_browser_ci_contention():
    if not DATABASE_URL.startswith("sqlite"):
        return
    with engine.connect() as connection:
        busy_timeout_ms = connection.exec_driver_sql("PRAGMA busy_timeout").scalar()
        journal_mode = str(connection.exec_driver_sql("PRAGMA journal_mode").scalar()).lower()
    assert busy_timeout_ms >= 30000
    assert journal_mode in {"wal", "memory"}


def test_backend_requirements_install_uvicorn_websocket_protocol():
    requirements = (Path(__file__).resolve().parents[2] / "requirements.txt").read_text()
    assert "uvicorn[standard]" in requirements or "websockets" in requirements or "wsproto" in requirements
    assert importlib.util.find_spec("websockets") or importlib.util.find_spec("wsproto")


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


def _set_production_auth_env(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_test")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brass-tune.vercel.app")


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


def test_global_json_body_limit_rejects_oversized_payload(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_MAX_JSON_BODY_BYTES", "8")
    with TestClient(app) as client:
        response = client.post(
            "/api/sessions/start",
            headers={"Content-Type": "application/json"},
            content=b'{"instrument_id":"trumpet","reference_pitch_hz":440}',
        )
    assert response.status_code == 413
    assert response.json()["detail"] == "Request body is too large."


def test_configurable_rate_limit_rejects_repeated_requests(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_PER_MINUTE", "1")
    main_module._RATE_LIMIT_BUCKETS.clear()
    with TestClient(app) as client:
        first = client.get("/api/instruments")
        second = client.get("/api/instruments")
    assert first.status_code == 200
    assert second.status_code == 429
    main_module._RATE_LIMIT_BUCKETS.clear()


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


def test_saved_pitch_frames_are_canonicalized_server_side():
    db = _test_db()
    try:
        session = _session(db, 112, "trumpet", dt.datetime(2026, 6, 15))
        frame = frequency_to_pitch_frame(midi_to_frequency(60), 0.98, 0.1, 0, "trumpet", 440.0).to_dict()
        frame["concert_note_name"] = "Z"
        frame["written_note_name"] = "Z"
        frame["written_octave"] = 9
        frame["cents_deviation"] = 999
        frame["tuning_status"] = "sharp"

        samples = save_pitch_frames(db, session.id, [frame])

        assert len(samples) == 1
        assert samples[0].concert_note != "Z"
        assert samples[0].written_note != "Z"
        assert samples[0].written_octave != 9
        assert abs(samples[0].cents_deviation) < 0.01
        assert samples[0].tuning_status == "in_tune"
    finally:
        db.close()


def test_pitch_frame_instrument_must_match_session_instrument():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        frame = frequency_to_pitch_frame(midi_to_frequency(60), MIN_RECORDING_CONFIDENCE, 0.1, 0, "horn", 440.0).to_dict()
        response = client.post(f"/api/sessions/{session['id']}/samples", json=frame)

    assert response.status_code == 400
    assert "instrument" in response.json()["detail"].lower()


def test_batch_sample_endpoint_saves_imported_media_frames():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        frames = [
            frequency_to_pitch_frame(midi_to_frequency(60), MIN_RECORDING_CONFIDENCE, 0.1, 0, "trumpet", 440.0).to_dict(),
            frequency_to_pitch_frame(midi_to_frequency(62), MIN_RECORDING_CONFIDENCE, 0.1, 110, "trumpet", 440.0).to_dict(),
        ]
        response = client.post(f"/api/sessions/{session['id']}/samples/batch", json=frames)
        assert response.status_code == 200
        assert response.json()["saved"] == 2


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


def test_repair_demo_data_rebuilds_broken_seed_sessions():
    db = _test_db()
    try:
        _session(db, 14, "trumpet", dt.datetime(2026, 6, 15))
        result = repair_demo_data(db)
        assert result["repaired"] is True
        sessions = db.query(PracticeSession).all()
        assert len(sessions) >= 7
        assert db.query(PitchSample).count() > 0
        assert db.query(NoteEvent).count() > 0
        assert all(session.samples for session in sessions)
        assert all(session.note_events for session in sessions)
    finally:
        db.close()


def test_production_startup_does_not_seed_demo_data_by_default(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brass-tune.vercel.app")
    monkeypatch.delenv("BRASSTUNE_SEED_DEMO_DATA", raising=False)
    calls = []

    class EmptyDB:
        def close(self):
            pass

    monkeypatch.setattr(main_module, "init_db", lambda: None)
    monkeypatch.setattr(main_module, "SessionLocal", lambda: EmptyDB())
    monkeypatch.setattr(main_module, "seed_demo_data", lambda db: calls.append(db))
    with TestClient(app) as client:
        assert client.get("/api/health").status_code == 200
    assert calls == []


def test_explicit_demo_seed_override_still_works_in_non_release_envs(monkeypatch):
    monkeypatch.setenv("APP_ENV", "preview")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brass-tune.vercel.app")
    monkeypatch.setenv("BRASSTUNE_SEED_DEMO_DATA", "1")
    calls = []

    class EmptyDB:
        def close(self):
            pass

    monkeypatch.setattr(main_module, "init_db", lambda: None)
    monkeypatch.setattr(main_module, "SessionLocal", lambda: EmptyDB())
    monkeypatch.setattr(main_module, "seed_demo_data", lambda db: calls.append(db))
    with TestClient(app) as client:
        assert client.get("/api/health").status_code == 200
    assert len(calls) == 1


def test_production_startup_requires_explicit_auth_mode(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.delenv("BRASSTUNE_AUTH_MODE", raising=False)
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_PUBLISHABLE_KEY", raising=False)
    with pytest.raises(RuntimeError, match="BRASSTUNE_AUTH_MODE"):
        with TestClient(app):
            pass


def test_invalid_app_env_is_rejected(monkeypatch):
    monkeypatch.setenv("APP_ENV", "prod")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    with pytest.raises(RuntimeError, match="APP_ENV"):
        with TestClient(app):
            pass


def test_deployed_staging_requires_explicit_auth_mode(monkeypatch):
    monkeypatch.setenv("APP_ENV", "staging")
    monkeypatch.delenv("BRASSTUNE_AUTH_MODE", raising=False)
    with pytest.raises(RuntimeError, match="BRASSTUNE_AUTH_MODE"):
        with TestClient(app):
            pass


def test_production_disabled_auth_mode_starts_and_fails_private_routes_closed(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brass-tune.vercel.app")
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_PUBLISHABLE_KEY", raising=False)
    with TestClient(app) as client:
        assert client.get("/api/health").status_code == 200
        assert client.get("/api/instruments").status_code == 200
        assert client.get("/api/sessions").status_code == 401
        token_response = client.get("/api/users/current", headers={"Authorization": "Bearer any-token"})
    assert token_response.status_code == 401
    assert "unavailable" in token_response.json()["detail"].lower()


def test_production_supabase_mode_requires_supabase_config(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_PUBLISHABLE_KEY", raising=False)
    with pytest.raises(RuntimeError, match="SUPABASE_URL"):
        with TestClient(app):
            pass


def test_production_supabase_mode_requires_service_key(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test")
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    with pytest.raises(RuntimeError, match="SUPABASE_SECRET_KEY"):
        with TestClient(app):
            pass


def test_production_rejects_local_auth_override(monkeypatch):
    _set_production_auth_env(monkeypatch)
    monkeypatch.setenv("BRASSTUNE_ALLOW_LOCAL_AUTH", "1")
    with pytest.raises(RuntimeError, match="BRASSTUNE_ALLOW_LOCAL_AUTH"):
        with TestClient(app):
            pass


def test_production_mode_requires_auth(monkeypatch):
    _set_production_auth_env(monkeypatch)
    with TestClient(app) as client:
        response = client.get("/api/sessions")
    assert response.status_code == 401


def test_local_disabled_mode_allows_guest_demo_auth(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    with TestClient(app) as client:
        response = client.get("/api/sessions")
    assert response.status_code == 200


def test_user_cannot_access_another_users_session():
    with TestClient(app) as client:
        created = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        response = client.get(f"/api/sessions/{created['id']}", headers={"Authorization": "Bearer dev-user-2"})
    assert response.status_code == 403


def test_audio_upload_playback_and_bad_mime_are_validated():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        bad = client.post(
            f"/api/sessions/{session['id']}/audio",
            content=b"not audio",
            headers={"Content-Type": "text/plain"},
        )
        assert bad.status_code == 400
        uploaded = client.post(
            f"/api/sessions/{session['id']}/audio",
            content=b"webm-audio-bytes",
            headers={"Content-Type": "audio/webm", "X-Audio-Duration-Seconds": "2.5"},
        )
        assert uploaded.status_code == 200
        assert uploaded.json()["audio"]["audio_available"] is True
        playback = client.get(f"/api/sessions/{session['id']}/audio")
        assert playback.status_code == 200
        assert playback.content == b"webm-audio-bytes"


def test_session_zip_contains_expected_files():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        client.post(
            f"/api/sessions/{session['id']}/audio",
            content=b"zip-audio",
            headers={"Content-Type": "audio/webm", "X-Audio-Duration-Seconds": "1"},
        )
        response = client.get(f"/api/export/session/{session['id']}.zip")
    assert response.status_code == 200
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        names = set(archive.namelist())
    assert {"session.json", "pitch_samples.csv", "note_events.csv", "recommendations.json", "README.txt"}.issubset(names)
    assert any(name.startswith("audio/") for name in names)


def test_director_can_add_member_by_username_but_student_cannot():
    with TestClient(app) as client:
        student_response = client.post(
            "/api/ensemble/groups/1/members/by-username",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"username": "maya", "instrument_id": "horn"},
        )
        assert student_response.status_code == 403
        director_response = client.post(
            "/api/ensemble/groups/1/members/by-username",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"username": "maya", "instrument_id": "horn"},
        )
        assert director_response.status_code == 200
        missing_response = client.post(
            "/api/ensemble/groups/1/members/by-username",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"username": "missing-player", "instrument_id": "horn"},
        )
        assert missing_response.status_code == 404


def test_websocket_stop_session_requires_owner_or_admin():
    with TestClient(app) as client:
        created = client.post(
            "/api/sessions/start",
            headers={"Authorization": "Bearer dev-user-3"},
            json={"instrument_id": "horn", "reference_pitch_hz": 440},
        ).json()
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json({"type": "authenticate", "token": "dev-user-1"})
            assert websocket.receive_json()["type"] == "authenticated"
            websocket.send_json({"type": "stop_session", "session_id": created["id"]})
            message = websocket.receive_json()
        assert message["type"] == "error"
        assert "access" in message["message"].lower()
        session = client.get(f"/api/sessions/{created['id']}", headers={"Authorization": "Bearer dev-user-3"}).json()
        assert session["ended_at"] is None


def test_websocket_pcm_frame_size_is_limited():
    oversized_pcm = [0.0] * 20000
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json({"type": "audio_frame", "instrument_id": "trumpet", "sample_rate": 48000, "pcm": oversized_pcm})
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert "too large" in message["message"].lower()


def test_websocket_rejects_query_token_auth():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch?token=dev-user-1") as websocket:
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert "query-token" in message["message"]


def test_websocket_rejects_unapproved_origin():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch", headers={"Origin": "https://evil.example"}) as websocket:
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert "origin" in message["message"].lower()


def test_websocket_raw_message_size_is_limited():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_text('{"type":"ping","padding":"%s"}' % ("x" * (270 * 1024)))
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert "too large" in message["message"].lower()


def test_batch_pitch_frame_size_is_limited():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        frame = frequency_to_pitch_frame(midi_to_frequency(60), MIN_RECORDING_CONFIDENCE, 0.1, 0, "trumpet", 440.0).to_dict()
        response = client.post(f"/api/sessions/{session['id']}/samples/batch", json=[frame] * (MAX_BATCH_PITCH_FRAMES + 1))
    assert response.status_code == 413


def test_limited_body_reader_rejects_before_unbounded_accumulation():
    class FakeRequest:
        async def stream(self):
            yield b"abc"
            yield b"def"

    try:
        asyncio.run(_read_limited_body(FakeRequest(), max_bytes=5))
        assert False, "Expected HTTPException"
    except Exception as exc:
        assert getattr(exc, "status_code", None) == 413


def test_signed_in_student_cannot_use_full_json_export_bypass():
    with TestClient(app) as client:
        response = client.get("/api/export/all.json", headers={"Authorization": "Bearer dev-user-1"})
    assert response.status_code == 403


def test_supabase_user_does_not_link_to_existing_account_by_email_alone():
    db = _test_db()
    try:
        local_teacher = User(
            email="teacher@example.com",
            username="teacher",
            name="Teacher",
            role="director",
            primary_instrument_id="trumpet",
        )
        db.add(local_teacher)
        db.commit()
        db.refresh(local_teacher)
        user = _sync_supabase_user(
            db,
            {
                "id": "supabase-user-1",
                "email": "teacher@example.com",
                "user_metadata": {},
                "app_metadata": {},
            },
        )
        db.refresh(local_teacher)
        assert user.supabase_user_id == "supabase-user-1"
        assert user.id != local_teacher.id
        assert user.role == "student"
        assert local_teacher.supabase_user_id is None
        assert local_teacher.role == "director"
    finally:
        db.close()


def test_ensemble_aggregate_reports_are_manager_only():
    with TestClient(app) as client:
        group_response = client.get("/api/ensemble/groups/1", headers={"Authorization": "Bearer dev-user-1"})
        assert group_response.status_code == 200
        student_report = client.get("/api/ensemble/groups/1/report", headers={"Authorization": "Bearer dev-user-1"})
        assert student_report.status_code == 403
        director_report = client.get("/api/ensemble/groups/1/report", headers={"Authorization": "Bearer dev-user-2"})
        assert director_report.status_code == 200


def test_director_roster_view_includes_member_identity():
    with TestClient(app) as client:
        response = client.get("/api/ensemble/groups/1", headers={"Authorization": "Bearer dev-user-2"})
    assert response.status_code == 200
    payload = response.json()
    assert payload["roster_scope"] == "full"
    assert payload["director_user_id"] == 2
    usernames = {member.get("username") for member in payload["members"]}
    assert {"avery", "maya", "luis", "sam"}.issubset(usernames)
    assert all("user_id" in member for member in payload["members"])


def test_student_roster_view_is_self_only_and_redacted():
    with TestClient(app) as client:
        response = client.get("/api/ensemble/groups/1", headers={"Authorization": "Bearer dev-user-1"})
        members_response = client.get("/api/ensemble/groups/1/members", headers={"Authorization": "Bearer dev-user-1"})
    assert response.status_code == 200
    assert members_response.status_code == 200
    payload = response.json()
    assert payload["roster_scope"] == "self"
    assert "director_user_id" not in payload
    assert payload["members"] == members_response.json()
    assert len(payload["members"]) == 1
    member = payload["members"][0]
    assert member["instrument_id"] == "trumpet"
    assert member["display_name"] == "You"
    assert member["is_current_user"] is True
    assert "user_id" not in member
    assert "username" not in member


def test_student_group_list_redacts_director_identity():
    with TestClient(app) as client:
        response = client.get("/api/ensemble/groups", headers={"Authorization": "Bearer dev-user-1"})
        director_response = client.get("/api/ensemble/groups", headers={"Authorization": "Bearer dev-user-2"})
    assert response.status_code == 200
    assert director_response.status_code == 200
    assert response.json()
    assert all("director_user_id" not in group for group in response.json())
    assert any("director_user_id" in group for group in director_response.json())


def test_ensemble_aggregate_reports_exclude_pre_membership_sessions():
    db = _test_db()
    try:
        director = User(id=80, username="director80", name="Director", role="director", primary_instrument_id="trumpet")
        student = User(id=81, username="student81", name="Student", role="student", primary_instrument_id="trumpet")
        group = Group(id=82, name="Wind Ensemble", director_user_id=director.id, created_at=dt.datetime(2026, 6, 1))
        db.add_all([director, student, group])
        db.commit()
        before = _session(db, student.id, "trumpet", dt.datetime(2026, 6, 5))
        after = _session(db, student.id, "trumpet", dt.datetime(2026, 6, 12))
        member = GroupMember(
            group_id=group.id,
            user_id=student.id,
            instrument_id="trumpet",
            role_in_group="student",
            status="active",
            created_at=dt.datetime(2026, 6, 10),
        )
        db.add(member)
        db.commit()

        rows = _group_scoped_sessions(db, group.id)

        assert [row.id for row in rows] == [after.id]
        assert before.id not in {row.id for row in rows}
    finally:
        db.close()


def test_ensemble_reactivation_excludes_sessions_from_removed_interval():
    db = _test_db()
    try:
        director = User(id=180, username="director180", name="Director", role="director", primary_instrument_id="trumpet")
        student = User(id=181, username="student181", name="Student", role="student", primary_instrument_id="trumpet")
        group = Group(id=182, name="Wind Ensemble", director_user_id=director.id, created_at=dt.datetime(2026, 6, 1))
        db.add_all([director, student, group])
        db.commit()
        before = _session(db, student.id, "trumpet", dt.datetime(2026, 6, 8))
        removed_interval = _session(db, student.id, "trumpet", dt.datetime(2026, 6, 20))
        after_reactivation = _session(db, student.id, "trumpet", dt.datetime(2026, 7, 2))
        member = GroupMember(
            group_id=group.id,
            user_id=student.id,
            instrument_id="trumpet",
            role_in_group="student",
            status="active",
            created_at=dt.datetime(2026, 6, 5),
            active_since=dt.datetime(2026, 7, 1),
            removed_at=None,
        )
        db.add(member)
        db.commit()

        rows = _group_scoped_sessions(db, group.id)

        assert [row.id for row in rows] == [after_reactivation.id]
        assert before.id not in {row.id for row in rows}
        assert removed_interval.id not in {row.id for row in rows}
    finally:
        db.close()


def test_account_export_contains_profile_and_lifecycle_data():
    with TestClient(app) as client:
        response = client.get("/api/users/me/export.zip", headers={"Authorization": "Bearer dev-user-1"})
    assert response.status_code == 200
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        names = set(archive.namelist())
        assert {"account.json", "sessions.json", "memberships.json", "owned_groups.json", "invitations.json", "recommendations.json"}.issubset(names)
        account = json.loads(archive.read("account.json"))
    assert account["id"] == 1
    assert account["role"] == "student"


def test_clear_practice_data_deletes_audio_before_bulk_rows(monkeypatch):
    db = _test_db()
    calls = []
    try:
        session = _session(db, 51, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "51/%s/recording.webm" % session.id

        def fake_delete_audio(row):
            calls.append(row.audio_object_key)

        monkeypatch.setattr("app.db.maintenance.delete_audio_for_session", fake_delete_audio)
        counts = clear_practice_data(db)
        assert counts["practice_sessions"] == 1
        assert calls == ["51/%s/recording.webm" % session.id]
        assert db.query(PracticeSession).count() == 0
    finally:
        db.close()


def test_websocket_accepts_first_message_auth_without_token_query(monkeypatch):
    _set_production_auth_env(monkeypatch)

    def fake_auth_context(db, token):
        assert token == "dev-ws-token"
        user = db.query(User).filter(User.id == 1).first()
        return AuthContext(user=user, is_guest=False, access_token=token)

    monkeypatch.setattr("app.api.websocket.auth_context_from_token", fake_auth_context)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch", headers={"Origin": "https://brass-tune.vercel.app"}) as websocket:
            websocket.send_json({"type": "ping"})
            assert websocket.receive_json()["message"].lower().startswith("authenticate")
            websocket.send_json({"type": "authenticate", "token": "dev-ws-token"})
            assert websocket.receive_json()["type"] == "authenticated"
            websocket.send_json({"type": "ping"})
            assert websocket.receive_json()["type"] == "pong"


def test_supabase_audio_delete_is_called_before_metadata_is_cleared(monkeypatch):
    db = _test_db()
    calls = []
    try:
        session = _session(db, 50, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "50/%s/recording.webm" % session.id
        session.audio_mime_type = "audio/webm"

        def fake_delete(object_key):
            calls.append(object_key)

        monkeypatch.setattr("app.services.audio_storage._delete_supabase_object", fake_delete)
        delete_audio_for_session(session)
        assert calls == ["50/%s/recording.webm" % session.id]
        assert session.audio_object_key is None
        assert session.audio_storage_provider is None
    finally:
        db.close()


def test_account_deletion_local_cleanup_failure_does_not_delete_external_identity(monkeypatch):
    db = _test_db()
    external_calls = []
    try:
        user = User(id=150, username="delete150", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-150")
        db.add(user)
        db.commit()
        session = _session(db, user.id, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "150/%s/recording.webm" % session.id
        db.add(session)
        db.commit()

        def fail_local_audio_cleanup(_session):
            raise RuntimeError("storage unavailable")

        monkeypatch.setattr("app.api.routes.delete_audio_for_session", fail_local_audio_cleanup)
        monkeypatch.setattr("app.api.routes.supabase_global_sign_out", lambda token: external_calls.append(("signout", token)) or True)
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: external_calls.append(("delete", user_id)) or True)

        with pytest.raises(HTTPException) as exc:
            delete_my_account(
                AccountDeletionRequest(confirmation="delete my account"),
                db,
                AuthContext(user=user, is_guest=False, access_token="access-token"),
            )

        assert exc.value.status_code == 503
        assert external_calls == []
        assert db.query(User).filter(User.id == user.id).first() is not None
        job = db.query(AccountDeletionJob).filter(AccountDeletionJob.user_id == user.id).one()
        assert job.status == "retryable_failure"
        assert job.stage == "local_cleanup_failed"
        assert job.safe_error_category == "audio_cleanup_failed"
    finally:
        db.close()


def test_account_deletion_records_completed_job_and_external_cleanup_last(monkeypatch):
    db = _test_db()
    external_calls = []
    try:
        user = User(id=151, username="delete151", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-151")
        db.add(user)
        db.commit()
        _session(db, user.id, "trumpet", dt.datetime(2026, 6, 15))
        monkeypatch.setattr("app.api.routes.supabase_global_sign_out", lambda token: external_calls.append(("signout", token, db.query(User).filter(User.id == user.id).first() is None)) or True)
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: external_calls.append(("delete", user_id, db.query(User).filter(User.id == user.id).first() is None)) or True)

        payload = delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=False, access_token="access-token"),
        )

        assert payload["deleted"] is True
        assert payload["deletion_status"] == "completed"
        assert db.query(User).filter(User.id == user.id).first() is None
        assert external_calls == [("signout", "access-token", True), ("delete", "supabase-151", True)]
        job = db.query(AccountDeletionJob).filter(AccountDeletionJob.user_id == user.id).one()
        assert job.status == "completed"
        assert job.stage == "completed"
    finally:
        db.close()


def test_account_deletion_external_failure_blocks_supabase_recreation(monkeypatch):
    db = _test_db()
    try:
        user = User(id=152, username="delete152", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-152")
        db.add(user)
        db.commit()
        monkeypatch.setattr("app.api.routes.supabase_global_sign_out", lambda token: True)
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: False)

        payload = delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=False, access_token="access-token"),
        )

        assert payload["deletion_status"] == "external_cleanup_queued"
        assert db.query(User).filter(User.id == user.id).first() is None
        job = db.query(AccountDeletionJob).filter(AccountDeletionJob.supabase_user_id == "supabase-152").one()
        assert job.status == "retryable_failure"
        with pytest.raises(HTTPException) as exc:
            _sync_supabase_user(
                db,
                {
                    "id": "supabase-152",
                    "email": "delete152@example.com",
                    "user_metadata": {},
                    "app_metadata": {},
                },
            )
        assert exc.value.status_code == 423
        assert db.query(User).filter(User.supabase_user_id == "supabase-152").first() is None
    finally:
        db.close()


def test_account_deletion_removes_sessions_audio_and_teacher_owned_group():
    with TestClient(app) as client:
        session = client.post(
            "/api/sessions/start",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"instrument_id": "trombone", "reference_pitch_hz": 440},
        ).json()
        upload = client.post(
            f"/api/sessions/{session['id']}/audio",
            headers={"Authorization": "Bearer dev-user-2", "Content-Type": "audio/webm"},
            content=b"delete-me",
        )
        assert upload.status_code == 200
        response = client.request(
            "DELETE",
            "/api/users/me",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"confirmation": "delete my account"},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["deleted"] is True
        assert payload["counts"]["teacher_owned_groups"] >= 1
        assert client.get("/api/ensemble/groups/1", headers={"Authorization": "Bearer dev-user-1"}).status_code in {403, 404}
