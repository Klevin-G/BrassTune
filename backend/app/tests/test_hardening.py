import datetime as dt
import importlib.util
import io
import json
import math
import asyncio
import zipfile
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

import app.main as main_module
from app.api.auth import AuthContext, _sync_supabase_user, delete_supabase_identity
from app.api.routes import (
    _filtered_events,
    _group_scoped_sessions,
    _read_limited_body,
    accept_invitation,
    add_member_by_username,
    create_ensemble_group,
    delete_my_account,
    get_ensemble_group,
    join_ensemble_by_code,
    leave_ensemble_group,
    list_ensemble_groups,
    retry_account_deletion_jobs,
    rotate_ensemble_join_code,
    update_ensemble_member,
)
from app.core.security import allowed_origins, cors_allowed_origin_regex
from app.core.analytics.stats import build_instrument_heatmap, calculate_most_improved_notes, calculate_note_stats
from app.core.instruments.profiles import get_instrument_profile
from app.core.music.theory import MIN_RECORDING_CONFIDENCE, frequency_to_pitch_frame, midi_to_frequency
from app.core.pitch.detector import yin_pitch
from app.db.database import Base, DATABASE_URL, SessionLocal, engine
from app.db.maintenance import clear_practice_data, repair_demo_data
from app.db.seed import seed_demo_data
from app.main import app
from app.models.db import AccountDeletionJob, Group, GroupMember, NoteEvent, PitchSample, PracticeSession, UsageEvent, User
from app.schemas.schemas import (
    MAX_BATCH_PITCH_FRAMES,
    AcceptInvitationRequest,
    AccountDeletionRequest,
    AddMemberByUsernameRequest,
    CreateGroupRequest,
    JoinByCodeRequest,
    UpdateGroupMemberRequest,
)
from app.services.audio_storage import delete_audio_for_session
from app.services.session_service import save_pitch_frames

WEBM_AUDIO_BYTES = b"\x1a\x45\xdf\xa3webm-audio-bytes"


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


def test_backend_requirements_use_sqlalchemy_two_floor():
    requirements = (Path(__file__).resolve().parents[2] / "requirements.txt").read_text()
    constraints = (Path(__file__).resolve().parents[2] / "constraints.txt").read_text()
    assert "sqlalchemy>=2.0,<3" in requirements.lower()
    assert "sqlalchemy>=2.0" in constraints.lower()


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
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "test-service-key-placeholder")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app")
    monkeypatch.setenv("BRASSTUNE_DATABASE_URL", "postgresql://postgres@example.supabase.co:5432/postgres")


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
    assert response.headers["x-content-type-options"] == "nosniff"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]


def test_configurable_rate_limit_rejects_repeated_requests(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_PER_MINUTE", "1")
    main_module._RATE_LIMIT_BUCKETS.clear()
    with TestClient(app) as client:
        first = client.get("/api/instruments")
        second = client.get("/api/instruments")
    assert first.status_code == 200
    assert second.status_code == 429
    assert second.headers["x-content-type-options"] == "nosniff"
    assert "frame-ancestors 'none'" in second.headers["content-security-policy"]
    main_module._RATE_LIMIT_BUCKETS.clear()


def test_rate_limit_prunes_expired_buckets_before_cardinality_cap(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_PER_MINUTE", "5")
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_MAX_BUCKETS", "1")
    main_module._RATE_LIMIT_BUCKETS.clear()
    expired_timestamp = main_module.time.monotonic() - main_module._RATE_LIMIT_WINDOW_SECONDS - 1
    main_module._RATE_LIMIT_BUCKETS[("old-client", "/api/instruments")].append(expired_timestamp)
    with TestClient(app) as client:
        response = client.get("/api/instruments")
    assert response.status_code == 200
    assert ("old-client", "/api/instruments") not in main_module._RATE_LIMIT_BUCKETS
    main_module._RATE_LIMIT_BUCKETS.clear()


def test_deployed_cors_regex_requires_explicit_escape_hatch(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("CORS_ALLOWED_ORIGIN_REGEX", r"https://.*\.vercel\.app")
    monkeypatch.delenv("BRASSTUNE_ALLOW_CORS_REGEX", raising=False)
    with pytest.raises(RuntimeError):
        cors_allowed_origin_regex()
    monkeypatch.setenv("BRASSTUNE_ALLOW_CORS_REGEX", "1")
    assert cors_allowed_origin_regex() == r"https://.*\.vercel\.app"


def test_deployed_cors_origins_reject_wildcards_and_insecure_values(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.delenv("CORS_ALLOWED_ORIGINS", raising=False)
    monkeypatch.delenv("FRONTEND_ORIGIN", raising=False)
    with pytest.raises(RuntimeError):
        allowed_origins()
    for origin in ["*", "https://*.vercel.app", "http://brasstune.vercel.app", "https://brasstune.vercel.app/callback"]:
        monkeypatch.setenv("CORS_ALLOWED_ORIGINS", origin)
        with pytest.raises(RuntimeError):
            allowed_origins()
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app/")
    assert allowed_origins() == ["https://brasstune.vercel.app"]


def test_default_deployed_environment_requires_explicit_cors_origins(monkeypatch):
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.delenv("CORS_ALLOWED_ORIGINS", raising=False)
    monkeypatch.delenv("FRONTEND_ORIGIN", raising=False)
    with pytest.raises(RuntimeError, match="CORS_ALLOWED_ORIGINS"):
        allowed_origins()


def test_api_responses_include_security_headers():
    with TestClient(app) as client:
        response = client.get("/api/health")
    assert response.status_code == 200
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["referrer-policy"] == "strict-origin-when-cross-origin"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert response.headers["x-frame-options"] == "DENY"


def test_unhandled_http_errors_are_generic_and_hardened():
    route_path = "/api/__test_unhandled_error"

    if not any(getattr(route, "path", None) == route_path for route in app.routes):
        @app.get(route_path)
        def _raise_test_error():
            raise RuntimeError("database password leaked in traceback")

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get(route_path)
    assert response.status_code == 500
    assert response.json()["detail"] == "The server could not complete this request."
    assert "password" not in response.text.lower()
    assert response.headers["x-content-type-options"] == "nosniff"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]


def test_live_and_version_endpoints_are_public(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    with TestClient(app) as client:
        live = client.get("/api/live")
        version = client.get("/api/version")
    assert live.status_code == 200
    assert live.json()["ok"] is True
    assert version.status_code == 200
    assert "commit_sha" in version.json()


def test_ready_endpoint_fails_when_dependency_checks_fail(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setattr(
        "app.api.routes.readiness_report",
        lambda: {
            "ok": False,
            "service": "BrassTune Analytics API",
            "environment": "local",
            "database_backend": "sqlite",
            "checks": {"database": {"ok": False, "issues": ["Missing table: account_deletion_jobs."]}},
        },
    )
    with TestClient(app) as client:
        response = client.get("/api/ready")
    assert response.status_code == 503
    assert response.json()["detail"]["ok"] is False
    assert response.json()["detail"]["checks"]["database"] == {"ok": False}
    assert "Missing table" not in json.dumps(response.json())


def test_ready_endpoint_redacts_operational_secret_names(monkeypatch):
    _set_production_auth_env(monkeypatch)
    monkeypatch.setattr(
        "app.api.routes.readiness_report",
        lambda: {
            "ok": False,
            "service": "BrassTune Analytics API",
            "environment": "production",
            "database_backend": "postgresql",
            "checks": {
                "auth": {"ok": False, "issues": ["SUPABASE_SECRET_KEY is required."]},
                "maintenance": {"ok": False, "issues": ["Missing BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET."]},
            },
        },
    )
    with TestClient(app) as client:
        response = client.get("/api/ready")
    assert response.status_code == 503
    body = response.json()
    assert body["detail"]["checks"] == {"auth": {"ok": False}, "maintenance": {"ok": False}}
    assert "SUPABASE_SECRET_KEY" not in json.dumps(body)
    assert "BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET" not in json.dumps(body)


def test_postgres_readiness_requires_account_deletion_counts_jsonb():
    from app.db.readiness import _postgres_column_type_issues

    assert _postgres_column_type_issues(
        "account_deletion_jobs",
        [{"name": "counts_json", "type": "TEXT"}],
    ) == ["Column account_deletion_jobs.counts_json must be jsonb, not text."]
    assert _postgres_column_type_issues(
        "account_deletion_jobs",
        [{"name": "counts_json", "type": "JSONB"}],
    ) == []


def test_postgres_readiness_accepts_exact_membership_unique_constraint_or_index():
    from app.db.readiness import _postgres_unique_key_issues

    assert _postgres_unique_key_issues(
        "group_members",
        [{"name": "uq_group_members_group_user", "column_names": ["group_id", "user_id"]}],
        [],
    ) == []
    assert _postgres_unique_key_issues(
        "group_members",
        [],
        [{"name": "group_members_group_user_key", "column_names": ["group_id", "user_id"], "unique": True}],
    ) == []


def test_postgres_readiness_rejects_nonunique_partial_or_inexact_membership_indexes():
    from app.db.readiness import _postgres_unique_key_issues

    expected = ["Missing unique constraint or index on group_members(group_id, user_id)."]
    assert _postgres_unique_key_issues(
        "group_members",
        [],
        [{"column_names": ["group_id", "user_id"], "unique": False}],
    ) == expected
    assert _postgres_unique_key_issues(
        "group_members",
        [],
        [{
            "column_names": ["group_id", "user_id"],
            "unique": True,
            "dialect_options": {"postgresql_where": "status = 'active'"},
        }],
    ) == expected
    assert _postgres_unique_key_issues(
        "group_members",
        [{"column_names": ["user_id", "group_id"]}],
        [{"column_names": ["group_id", "user_id", "status"], "unique": True}],
    ) == expected


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
    _set_production_auth_env(monkeypatch)
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
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app")
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


def test_production_disabled_auth_mode_fails_startup(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app")
    monkeypatch.setenv("BRASSTUNE_DATABASE_URL", "postgresql://postgres@example.supabase.co:5432/postgres")
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("SUPABASE_PUBLISHABLE_KEY", raising=False)
    with pytest.raises(RuntimeError, match="disabled"):
        with TestClient(app):
            pass


def test_production_startup_requires_database_url(monkeypatch):
    _set_production_auth_env(monkeypatch)
    monkeypatch.delenv("BRASSTUNE_DATABASE_URL", raising=False)
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(RuntimeError, match="DATABASE_URL"):
        with TestClient(app):
            pass


def test_production_startup_rejects_sqlite_database_url(monkeypatch):
    _set_production_auth_env(monkeypatch)
    monkeypatch.setenv("BRASSTUNE_DATABASE_URL", "sqlite:///./prod.db")
    with pytest.raises(RuntimeError, match="PostgreSQL"):
        with TestClient(app):
            pass


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
            content=WEBM_AUDIO_BYTES,
            headers={"Content-Type": "audio/webm", "X-Audio-Duration-Seconds": "2.5"},
        )
        assert uploaded.status_code == 200
        assert uploaded.json()["audio"]["audio_available"] is True
        playback = client.get(f"/api/sessions/{session['id']}/audio")
        assert playback.status_code == 200
        assert playback.content == WEBM_AUDIO_BYTES


def test_audio_upload_rejects_spoofed_audio_mime():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        for payload in (b"<html>not audio</html>", b"%PDF-1.7", b"PK\x03\x04zip"):
            response = client.post(
                f"/api/sessions/{session['id']}/audio",
                content=payload,
                headers={"Content-Type": "audio/webm"},
            )
            assert response.status_code == 400
            assert "format" in response.json()["detail"].lower()


def test_session_zip_contains_expected_files():
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        client.post(
            f"/api/sessions/{session['id']}/audio",
            content=WEBM_AUDIO_BYTES,
            headers={"Content-Type": "audio/webm", "X-Audio-Duration-Seconds": "1"},
        )
        response = client.get(f"/api/export/session/{session['id']}.zip")
    assert response.status_code == 200
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        names = set(archive.namelist())
    assert {"session.json", "pitch_samples.csv", "note_events.csv", "recommendations.json", "README.txt"}.issubset(names)
    assert any(name.startswith("audio/") for name in names)


def test_session_exports_reject_too_many_rows(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_EXPORT_MAX_ROWS_PER_SESSION", "1")
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        frame = frequency_to_pitch_frame(midi_to_frequency(60), MIN_RECORDING_CONFIDENCE, 0.1, 0, "trumpet", 440.0).to_dict()
        assert client.post(f"/api/sessions/{session['id']}/samples/batch", json=[frame, {**frame, "timestamp_ms": 20}]).status_code == 200
        for path in [
            f"/api/export/session/{session['id']}.csv",
            f"/api/export/session/{session['id']}.json",
            f"/api/export/session/{session['id']}.zip",
        ]:
            response = client.get(path)
            assert response.status_code == 413
            assert "too many" in response.json()["detail"].lower()


def test_account_export_rejects_too_many_sessions(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_EXPORT_MAX_SESSIONS", "1")
    with TestClient(app) as client:
        first = client.post(
            "/api/sessions/start",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"instrument_id": "trumpet", "reference_pitch_hz": 440},
        )
        second = client.post(
            "/api/sessions/start",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"instrument_id": "trumpet", "reference_pitch_hz": 440},
        )
        assert first.status_code == 200
        assert second.status_code == 200
        response = client.get("/api/users/me/export.zip", headers={"Authorization": "Bearer dev-user-1"})
    assert response.status_code == 413
    assert "too many sessions" in response.json()["detail"].lower()


def test_full_json_export_rejects_too_many_total_rows(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_EXPORT_MAX_TOTAL_ROWS", "1")
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        frame = frequency_to_pitch_frame(midi_to_frequency(60), MIN_RECORDING_CONFIDENCE, 0.1, 0, "trumpet", 440.0).to_dict()
        assert client.post(f"/api/sessions/{session['id']}/samples/batch", json=[frame, {**frame, "timestamp_ms": 20}]).status_code == 200
        response = client.get("/api/export/all.json")
    assert response.status_code == 413
    assert "too many rows" in response.json()["detail"].lower()


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
            json={"username": "jordan", "instrument_id": "trombone"},
        )
        assert director_response.status_code == 200
        missing_response = client.post(
            "/api/ensemble/groups/1/members/by-username",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"username": "missing-player", "instrument_id": "horn"},
        )
        assert missing_response.status_code == 404


def test_director_cannot_silently_elevate_or_readd_active_member():
    with TestClient(app) as client:
        response = client.patch(
            "/api/ensemble/groups/1/members/1",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"role_in_group": "assistant", "instrument_id": "horn"},
        )
        assert response.status_code == 409
        duplicate = client.post(
            "/api/ensemble/groups/1/members/by-username",
            headers={"Authorization": "Bearer dev-user-2"},
            json={"username": "avery", "instrument_id": "trumpet", "role_in_group": "student"},
        )
        assert duplicate.status_code == 409
        group = client.get("/api/ensemble/groups/1", headers={"Authorization": "Bearer dev-user-2"}).json()
    avery = next(member for member in group["members"] if member["username"] == "avery")
    assert avery["role_in_group"] == "student"
    assert avery["instrument_id"] == "trumpet"


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


def test_websocket_rejects_any_auth_like_query_parameter():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch?access_token=dev-user-1") as websocket:
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert "query-token" in message["message"]


def test_websocket_rejects_unapproved_origin():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch", headers={"Origin": "https://evil.example"}) as websocket:
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert "origin" in message["message"].lower()


def test_websocket_accepts_regex_matched_origin_not_in_exact_list(monkeypatch):
    """Regression: a frontend origin allowed over HTTP by CORS_ALLOWED_ORIGIN_REGEX
    (but absent from the exact CORS_ALLOWED_ORIGINS list) must also be accepted on
    the pitch WebSocket — otherwise 'cloud practice' silently breaks for that host."""
    _set_production_auth_env(monkeypatch)
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app")
    monkeypatch.setenv("CORS_ALLOWED_ORIGIN_REGEX", r"https://.*\.vercel\.app")
    monkeypatch.setenv("BRASSTUNE_ALLOW_CORS_REGEX", "1")
    with TestClient(app) as client:
        # This origin is NOT in the exact list but DOES match the regex.
        with client.websocket_connect("/ws/pitch", headers={"Origin": "https://brasstune.vercel.app"}) as websocket:
            message = websocket.receive_json()
    # Not rejected on origin — it proceeds to require authentication instead.
    assert message["type"] != "error" or "origin" not in message["message"].lower()


def test_origin_is_allowed_matches_http_cors_policy(monkeypatch):
    from app.core.security import origin_is_allowed
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app")
    monkeypatch.setenv("CORS_ALLOWED_ORIGIN_REGEX", r"https://.*\.vercel\.app")
    monkeypatch.setenv("BRASSTUNE_ALLOW_CORS_REGEX", "1")
    assert origin_is_allowed("https://brasstune.vercel.app") is True
    assert origin_is_allowed("https://brasstune.vercel.app") is True
    assert origin_is_allowed("https://evil.example.com") is False
    # fullmatch prevents subdomain-suffix spoofing
    assert origin_is_allowed("https://brasstune.vercel.app.evil.com") is False
    assert origin_is_allowed(None) is False


def test_deployed_websocket_rejects_missing_origin(monkeypatch):
    monkeypatch.setenv("APP_ENV", "preview")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "test-service-key-placeholder")
    monkeypatch.setenv("BRASSTUNE_DATABASE_URL", "postgresql://postgres@example.supabase.co:5432/postgres")
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://brasstune.vercel.app")
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            message = websocket.receive_json()
    assert "origin" in message["message"].lower()


def test_websocket_closes_after_repeated_unauthenticated_frames(monkeypatch):
    _set_production_auth_env(monkeypatch)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch", headers={"Origin": "https://brasstune.vercel.app"}) as websocket:
            for _ in range(3):
                websocket.send_json({"type": "ping"})
                message = websocket.receive_json()
                assert "authenticate" in message["message"].lower()
            with pytest.raises(WebSocketDisconnect):
                websocket.receive_json()


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


def test_supabase_app_metadata_cannot_create_privileged_role():
    db = _test_db()
    try:
        user = _sync_supabase_user(
            db,
            {
                "id": "supabase-user-director",
                "email": "director-claim@example.com",
                "user_metadata": {"username": "director-claim", "display_name": "Director Claim"},
                "app_metadata": {"role": "director"},
            },
        )
        assert user.role == "student"
        user = _sync_supabase_user(
            db,
            {
                "id": "supabase-user-director",
                "email": "director-claim@example.com",
                "user_metadata": {},
                "app_metadata": {"role": "admin"},
            },
        )
        assert user.role == "student"
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
        assert "seeded" not in str(director_report.json()).lower()
        assert "mvp" not in str(director_report.json()).lower()


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
        sessions = json.loads(archive.read("sessions.json"))
    assert account["id"] == 1
    assert account["role"] == "student"
    assert all("audio_object_key" not in row for row in sessions)
    assert all("audio_storage_provider" not in row for row in sessions)


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
        with client.websocket_connect("/ws/pitch", headers={"Origin": "https://brasstune.vercel.app"}) as websocket:
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
        assert isinstance(job.counts_json, dict)
        assert job.counts_json["practice_sessions"] == 1
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


def test_account_deletion_retryable_job_blocks_existing_user_token():
    db = _test_db()
    try:
        user = User(id=252, username="delete252", name="Delete Pending", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-252")
        db.add(user)
        db.add(
            AccountDeletionJob(
                user_id=user.id,
                supabase_user_id="supabase-252",
                idempotency_key="delete-user-252",
                stage="external_cleanup_failed",
                status="retryable_failure",
                next_retry_at=dt.datetime.utcnow() + dt.timedelta(minutes=5),
                counts_json="{}",
            )
        )
        db.commit()

        with pytest.raises(HTTPException) as exc:
            _sync_supabase_user(
                db,
                {
                    "id": "supabase-252",
                    "email": "delete252@example.com",
                    "user_metadata": {"display_name": "Should Not Update"},
                    "app_metadata": {},
                },
            )

        assert exc.value.status_code == 423
        db.refresh(user)
        assert user.name == "Delete Pending"
    finally:
        db.close()


def test_account_deletion_retry_endpoint_requires_secret(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET", "retry-secret")
    with TestClient(app) as client:
        response = client.post("/api/maintenance/account-deletions/retry")
        assert response.status_code == 403
        response = client.post("/api/maintenance/account-deletions/retry", headers={"X-BrassTune-Maintenance-Secret": "retry-secret"})
        assert response.status_code == 200


def test_account_deletion_retry_executor_completes_external_cleanup(monkeypatch):
    db = _test_db()
    try:
        job = AccountDeletionJob(
            user_id=153,
            supabase_user_id="supabase-153",
            idempotency_key="delete-user-153",
            stage="external_cleanup_failed",
            status="retryable_failure",
            next_retry_at=dt.datetime.utcnow() - dt.timedelta(minutes=1),
            counts_json="{}",
        )
        db.add(job)
        db.commit()
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: user_id == "supabase-153")

        result = retry_account_deletion_jobs(db)

        assert result["processed"] == 1
        assert result["completed"] == 1
        db.refresh(job)
        assert job.status == "completed"
        assert job.stage == "completed"
        assert job.next_retry_at is None
    finally:
        db.close()


def test_account_deletion_retry_executor_keeps_retryable_external_failures(monkeypatch):
    db = _test_db()
    try:
        job = AccountDeletionJob(
            user_id=154,
            supabase_user_id="supabase-154",
            idempotency_key="delete-user-154",
            stage="external_cleanup_failed",
            status="retryable_failure",
            next_retry_at=dt.datetime.utcnow() - dt.timedelta(minutes=1),
            counts_json="{}",
        )
        db.add(job)
        db.commit()
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: False)

        result = retry_account_deletion_jobs(db)

        assert result["processed"] == 1
        assert result["still_retryable"] == 1
        db.refresh(job)
        assert job.status == "retryable_failure"
        assert job.stage == "external_cleanup_failed"
        assert job.retry_count == 1
        assert job.next_retry_at is not None
    finally:
        db.close()


def test_account_deletion_retry_executor_recovers_stale_external_cleanup(monkeypatch):
    db = _test_db()
    try:
        job = AccountDeletionJob(
            user_id=157,
            supabase_user_id="supabase-157",
            idempotency_key="delete-user-157",
            stage="external_cleanup_started",
            status="in_progress",
            updated_at=dt.datetime.utcnow() - dt.timedelta(minutes=20),
            counts_json="{}",
        )
        db.add(job)
        db.commit()
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: user_id == "supabase-157")

        result = retry_account_deletion_jobs(db)

        assert result["processed"] == 1
        assert result["completed"] == 1
        db.refresh(job)
        assert job.status == "completed"
        assert job.stage == "completed"
    finally:
        db.close()


def test_account_deletion_retry_executor_ignores_fresh_in_progress(monkeypatch):
    db = _test_db()
    try:
        job = AccountDeletionJob(
            user_id=158,
            supabase_user_id="supabase-158",
            idempotency_key="delete-user-158",
            stage="external_cleanup_started",
            status="in_progress",
            updated_at=dt.datetime.utcnow(),
            counts_json="{}",
        )
        db.add(job)
        db.commit()

        result = retry_account_deletion_jobs(db)

        assert result["processed"] == 0
        db.refresh(job)
        assert job.status == "in_progress"
    finally:
        db.close()


def test_delete_supabase_identity_treats_missing_user_as_complete(monkeypatch):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "test-service-key")
    monkeypatch.setenv("SUPABASE_URL", "https://project.supabase.co")

    def raise_not_found(*args, **kwargs):
        raise urllib.error.HTTPError("https://project.supabase.co/auth/v1/admin/users/missing", 404, "not found", None, None)

    import urllib.error

    monkeypatch.setattr("urllib.request.urlopen", raise_not_found)

    assert delete_supabase_identity("missing") is True


def test_account_deletion_retry_executor_recovers_local_cleanup_failure(monkeypatch):
    db = _test_db()
    try:
        user = User(id=155, username="delete155", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-155")
        db.add(user)
        db.commit()
        session = _session(db, user.id, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "155/%s/recording.webm" % session.id
        job = AccountDeletionJob(
            user_id=user.id,
            supabase_user_id=user.supabase_user_id,
            idempotency_key="delete-user-155",
            stage="local_cleanup_failed",
            status="retryable_failure",
            next_retry_at=dt.datetime.utcnow() - dt.timedelta(minutes=1),
            counts_json="{}",
        )
        db.add_all([session, job])
        db.commit()
        monkeypatch.setattr("app.api.routes.delete_audio_for_session", lambda _session: None)
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda user_id: user_id == "supabase-155")

        result = retry_account_deletion_jobs(db)

        assert result["processed"] == 1
        assert db.query(User).filter(User.id == user.id).first() is None
        db.refresh(job)
        assert job.status == "completed"
        assert job.stage == "completed"
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
            content=WEBM_AUDIO_BYTES,
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


def test_account_deletion_rejects_short_confirmation_phrase():
    with TestClient(app) as client:
        response = client.request(
            "DELETE",
            "/api/users/me",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"confirmation": "delete"},
        )
    assert response.status_code == 400
    assert 'delete my account' in response.json()["detail"]


def _create_class(client, token, name):
    response = client.post("/api/ensemble/groups", headers={"Authorization": f"Bearer {token}"}, json={"name": name})
    assert response.status_code == 200, response.text
    return response.json()


def test_manager_cannot_force_activate_invited_member():
    # A director must not be able to convert a pending invite into an active
    # membership; only the invited student can accept (consent gate).
    with TestClient(app) as client:
        group = _create_class(client, "dev-user-1", "Force Activate Test Class")
        gid = group["id"]
        invite = client.post(
            f"/api/ensemble/groups/{gid}/members/by-username",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"username": "maya"},
        )
        assert invite.status_code == 200, invite.text
        member_id = invite.json()["id"]
        assert invite.json()["status"] == "invited"
        forced = client.patch(
            f"/api/ensemble/groups/{gid}/members/{member_id}",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"status": "active"},
        )
        assert forced.status_code == 409
        # The victim's activity is NOT exposed while merely invited.
        roster = client.get(f"/api/ensemble/groups/{gid}/roster", headers={"Authorization": "Bearer dev-user-1"}).json()
        maya = next(s for s in roster["students"] if s["username"] == "maya")
        assert maya["status"] == "invited"
        assert maya["last_active_at"] is None


def test_invited_student_sets_own_instrument_on_accept():
    with TestClient(app) as client:
        group = _create_class(client, "dev-user-1", "Accept Instrument Test Class")
        gid = group["id"]
        # Director invites without specifying an instrument.
        invite = client.post(
            f"/api/ensemble/groups/{gid}/members/by-username",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"username": "maya"},
        )
        assert invite.status_code == 200, invite.text
        member_id = invite.json()["id"]
        # The invited student (maya = dev-user-3) accepts and picks her own instrument.
        accepted = client.post(
            f"/api/ensemble/invitations/{member_id}/accept",
            headers={"Authorization": "Bearer dev-user-3"},
            json={"instrument_id": "tuba"},
        )
        assert accepted.status_code == 200, accepted.text
        roster = client.get(f"/api/ensemble/groups/{gid}/roster", headers={"Authorization": "Bearer dev-user-1"}).json()
        maya = next(s for s in roster["students"] if s["username"] == "maya")
        assert maya["status"] == "active"
        assert maya["instrument_id"] == "tuba"


def test_self_join_by_class_code():
    with TestClient(app) as client:
        group = _create_class(client, "dev-user-1", "Join Code Test Class")
        gid = group["id"]
        code = group["join_code"]
        assert code and len(code) >= 4
        # A user not in the class joins with the code and picks their instrument.
        joined = client.post("/api/ensemble/join", headers={"Authorization": "Bearer dev-user-3"}, json={"code": code, "instrument_id": "trumpet"})
        assert joined.status_code == 200, joined.text
        assert joined.json()["group_id"] == gid
        # Joining again is a no-op conflict.
        again = client.post("/api/ensemble/join", headers={"Authorization": "Bearer dev-user-3"}, json={"code": code})
        assert again.status_code == 409
        # A wrong code is rejected.
        bad = client.post("/api/ensemble/join", headers={"Authorization": "Bearer dev-user-4"}, json={"code": "ZZZZZZ"})
        assert bad.status_code == 404
        # The director cannot join their own class.
        own = client.post("/api/ensemble/join", headers={"Authorization": "Bearer dev-user-1"}, json={"code": code})
        assert own.status_code == 400
        # The joined student now appears on the roster.
        roster = client.get(f"/api/ensemble/groups/{gid}/roster", headers={"Authorization": "Bearer dev-user-1"}).json()
        assert any(s["username"] == "maya" and s["instrument_id"] == "trumpet" for s in roster["students"])


def test_member_can_join_multiple_classes_and_leave_only_one():
    with TestClient(app) as client:
        first = _create_class(client, "dev-user-1", "Multi Membership One")
        second = _create_class(client, "dev-user-1", "Multi Membership Two")
        headers = {"Authorization": "Bearer dev-user-4"}
        for group in (first, second):
            joined = client.post(
                "/api/ensemble/join",
                headers=headers,
                json={"code": group["join_code"], "instrument_id": "trombone"},
            )
            assert joined.status_code == 200, joined.text

        before = client.get("/api/ensemble/groups", headers=headers).json()
        assert {first["id"], second["id"]}.issubset({group["id"] for group in before})

        left = client.delete(f"/api/ensemble/groups/{first['id']}/membership", headers=headers)
        assert left.status_code == 200, left.text
        assert left.json() == {"left": True, "group_id": first["id"]}
        after = client.get("/api/ensemble/groups", headers=headers).json()
        after_ids = {group["id"] for group in after}
        assert first["id"] not in after_ids
        assert second["id"] in after_ids
        assert client.get(f"/api/ensemble/groups/{first['id']}", headers=headers).status_code == 403
        assert client.get(f"/api/ensemble/groups/{second['id']}", headers=headers).status_code == 200


def test_leave_is_self_scoped_and_class_owner_cannot_leave():
    with TestClient(app) as client:
        group = _create_class(client, "dev-user-1", "Leave Authorization Class")
        member_headers = {"Authorization": "Bearer dev-user-4"}
        joined = client.post(
            "/api/ensemble/join",
            headers=member_headers,
            json={"code": group["join_code"]},
        )
        assert joined.status_code == 200, joined.text

        not_a_member = client.delete(
            f"/api/ensemble/groups/{group['id']}/membership",
            headers={"Authorization": "Bearer dev-user-3"},
        )
        assert not_a_member.status_code == 404
        assert client.get(f"/api/ensemble/groups/{group['id']}", headers=member_headers).status_code == 200

        owner = client.delete(
            f"/api/ensemble/groups/{group['id']}/membership",
            headers={"Authorization": "Bearer dev-user-1"},
        )
        assert owner.status_code == 409
        assert "owner" in owner.json()["detail"].lower()


def test_join_code_rejoin_resets_removed_elevated_role_and_timestamps():
    with TestClient(app) as client:
        group = _create_class(client, "dev-user-1", "Safe Rejoin Class")
        invited = client.post(
            f"/api/ensemble/groups/{group['id']}/members/by-username",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"username": "luis", "role_in_group": "assistant"},
        )
        assert invited.status_code == 200, invited.text
        member_id = invited.json()["id"]
        accepted = client.post(
            f"/api/ensemble/invitations/{member_id}/accept",
            headers={"Authorization": "Bearer dev-user-4"},
            json={"instrument_id": "trombone"},
        )
        assert accepted.status_code == 200, accepted.text
        assistant_details = client.get(
            f"/api/ensemble/groups/{group['id']}",
            headers={"Authorization": "Bearer dev-user-4"},
        ).json()
        assert assistant_details["roster_scope"] == "active_redacted"
        assert "join_code" not in assistant_details
        assert "director_user_id" not in assistant_details
        assert all("user_id" not in member and "username" not in member for member in assistant_details["members"])
        first_active_since = next(
            member["active_since"]
            for member in assistant_details["members"]
            if member["id"] == member_id
        )

        removed = client.delete(
            f"/api/ensemble/groups/{group['id']}/members/{member_id}",
            headers={"Authorization": "Bearer dev-user-1"},
        )
        assert removed.status_code == 200, removed.text
        rejoined = client.post(
            "/api/ensemble/join",
            headers={"Authorization": "Bearer dev-user-4"},
            json={"code": group["join_code"], "instrument_id": "tuba"},
        )
        assert rejoined.status_code == 200, rejoined.text

        details = client.get(
            f"/api/ensemble/groups/{group['id']}",
            headers={"Authorization": "Bearer dev-user-4"},
        ).json()
        membership = details["members"][0]
        assert details["roster_scope"] == "self"
        assert "join_code" not in details
        assert "director_user_id" not in details
        assert membership["role_in_group"] == "student"
        assert membership["instrument_id"] == "tuba"
        assert membership["removed_at"] is None
        assert membership["active_since"] >= first_active_since


def test_global_director_role_does_not_reveal_other_class_management_fields():
    with TestClient(app) as client:
        owned = _create_class(client, "dev-user-1", "Owned Redaction Class")
        foreign = _create_class(client, "dev-user-2", "Foreign Redaction Class")
        joined = client.post(
            "/api/ensemble/join",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"code": foreign["join_code"]},
        )
        assert joined.status_code == 200, joined.text

        groups = client.get(
            "/api/ensemble/groups",
            headers={"Authorization": "Bearer dev-user-1"},
        ).json()
        owned_payload = next(group for group in groups if group["id"] == owned["id"])
        foreign_payload = next(group for group in groups if group["id"] == foreign["id"])
        assert owned_payload["join_code"] == owned["join_code"]
        assert owned_payload["director_user_id"] == 1
        assert "join_code" not in foreign_payload
        assert "director_user_id" not in foreign_payload


def test_group_membership_is_unique_per_user_and_group():
    db = _test_db()
    try:
        db.add_all([
            User(id=301, username="unique301", name="Unique Director", role="director", primary_instrument_id="trumpet"),
            User(id=302, username="unique302", name="Unique Student", role="student", primary_instrument_id="horn"),
        ])
        db.commit()
        group = Group(name="Unique Membership Class", director_user_id=301, join_code="UNIQ42")
        db.add(group)
        db.commit()
        db.refresh(group)
        db.add(GroupMember(group_id=group.id, user_id=302, instrument_id="horn"))
        db.commit()
        db.add(GroupMember(group_id=group.id, user_id=302, instrument_id="horn"))
        with pytest.raises(IntegrityError):
            db.commit()
    finally:
        db.rollback()
        db.close()


def test_concurrent_join_integrity_error_is_only_translated_for_verified_active_member():
    group = Group(id=401, name="Concurrent Join Class", director_user_id=402, join_code="RACE42")
    concurrent = GroupMember(group_id=401, user_id=403, instrument_id="horn", status="active")

    class FakeQuery:
        def __init__(self, first_result):
            self.first_result = first_result

        def filter(self, *_args):
            return self

        def first(self):
            return self.first_result

        def count(self):
            return 0

        def with_for_update(self):
            return self

    class FakeDB:
        def __init__(self, concurrent_result):
            self.concurrent_result = concurrent_result
            self.membership_queries = 0
            self.rolled_back = False

        def query(self, model):
            if model is Group:
                return FakeQuery(group)
            if model is User.id:
                return FakeQuery(None)
            self.membership_queries += 1
            return FakeQuery(None if self.membership_queries == 1 else self.concurrent_result)

        def add(self, _member):
            return None

        def commit(self):
            raise IntegrityError("insert group membership", {}, Exception("unique violation"))

        def rollback(self):
            self.rolled_back = True

    auth = SimpleNamespace(user=SimpleNamespace(id=403, primary_instrument_id="horn"))
    payload = JoinByCodeRequest(code="RACE42")

    winning_db = FakeDB(concurrent)
    with pytest.raises(HTTPException) as conflict:
        join_ensemble_by_code(payload, db=winning_db, auth=auth)
    assert conflict.value.status_code == 409
    assert "already" in conflict.value.detail.lower()
    assert winning_db.rolled_back is True

    unrelated_db = FakeDB(None)
    with pytest.raises(IntegrityError):
        join_ensemble_by_code(payload, db=unrelated_db, auth=auth)
    assert unrelated_db.rolled_back is True


def test_manager_cannot_reactivate_member_after_join_and_leave():
    with TestClient(app) as client:
        group = _create_class(client, "dev-user-1", "Consent After Leave Class")
        joined = client.post(
            "/api/ensemble/join",
            headers={"Authorization": "Bearer dev-user-3"},
            json={"code": group["join_code"], "instrument_id": "horn"},
        )
        assert joined.status_code == 200, joined.text
        owner_view = client.get(
            f"/api/ensemble/groups/{group['id']}",
            headers={"Authorization": "Bearer dev-user-1"},
        ).json()
        member_id = next(member["id"] for member in owner_view["members"] if member.get("username") == "maya")

        left = client.delete(
            f"/api/ensemble/groups/{group['id']}/membership",
            headers={"Authorization": "Bearer dev-user-3"},
        )
        assert left.status_code == 200, left.text
        forced = client.patch(
            f"/api/ensemble/groups/{group['id']}/members/{member_id}",
            headers={"Authorization": "Bearer dev-user-1"},
            json={"status": "active"},
        )
        assert forced.status_code == 409
        group_after = client.get(
            f"/api/ensemble/groups/{group['id']}",
            headers={"Authorization": "Bearer dev-user-1"},
        ).json()
        maya = next(member for member in group_after["members"] if member["id"] == member_id)
        assert maya["status"] == "removed"


def test_class_ownership_active_membership_and_pending_invitation_quotas(monkeypatch):
    db = _test_db()
    try:
        owner = User(id=610, username="owner610", name="Owner", role="student", primary_instrument_id="trumpet")
        student = User(id=611, username="student611", name="Student", role="student", primary_instrument_id="horn")
        db.add_all([owner, student])
        db.commit()

        monkeypatch.setenv("BRASSTUNE_MAX_OWNED_CLASSES_PER_USER", "1")
        first = create_ensemble_group(CreateGroupRequest(name="Owned One"), db=db, auth=AuthContext(user=owner))
        with pytest.raises(HTTPException) as ownership_limit:
            create_ensemble_group(CreateGroupRequest(name="Owned Two"), db=db, auth=AuthContext(user=owner))
        assert ownership_limit.value.status_code == 409
        assert "ownership limit" in ownership_limit.value.detail

        second_group = Group(name="Membership Two", director_user_id=owner.id, join_code="MEMB2345")
        db.add(second_group)
        db.commit()
        db.refresh(second_group)
        db.add(GroupMember(group_id=first["id"], user_id=student.id, instrument_id="horn", status="active"))
        db.commit()
        monkeypatch.setenv("BRASSTUNE_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER", "1")
        with pytest.raises(HTTPException) as membership_limit:
            join_ensemble_by_code(JoinByCodeRequest(code=second_group.join_code), db=db, auth=AuthContext(user=student))
        assert membership_limit.value.status_code == 409
        assert "active class limit" in membership_limit.value.detail

        third_group = Group(name="Invite One", director_user_id=owner.id, join_code="INVT2345")
        fourth_group = Group(name="Invite Two", director_user_id=owner.id, join_code="INVT6789")
        db.add_all([third_group, fourth_group])
        db.commit()
        db.refresh(third_group)
        db.refresh(fourth_group)
        db.add(GroupMember(group_id=third_group.id, user_id=student.id, instrument_id="horn", status="invited"))
        db.commit()
        monkeypatch.setenv("BRASSTUNE_MAX_PENDING_CLASS_INVITATIONS_PER_USER", "1")
        with pytest.raises(HTTPException) as invitation_limit:
            add_member_by_username(
                fourth_group.id,
                AddMemberByUsernameRequest(username=student.username),
                db=db,
                auth=AuthContext(user=owner),
            )
        assert invitation_limit.value.status_code == 409
        assert invitation_limit.value.detail == "That username could not be invited right now."
    finally:
        db.close()


def test_invitation_acceptance_respects_active_membership_quota(monkeypatch):
    db = _test_db()
    try:
        owner = User(id=612, username="owner612", name="Owner", role="director", primary_instrument_id="trumpet")
        student = User(id=613, username="student613", name="Student", role="student", primary_instrument_id="horn")
        db.add_all([owner, student])
        db.commit()
        groups = [
            Group(name="Already Active", director_user_id=owner.id, join_code="ACTV2345"),
            Group(name="Pending Invite", director_user_id=owner.id, join_code="PEND2345"),
        ]
        db.add_all(groups)
        db.commit()
        db.add_all([
            GroupMember(group_id=groups[0].id, user_id=student.id, instrument_id="horn", status="active"),
            GroupMember(group_id=groups[1].id, user_id=student.id, instrument_id="horn", status="invited"),
        ])
        db.commit()
        invitation = db.query(GroupMember).filter(GroupMember.group_id == groups[1].id).first()
        monkeypatch.setenv("BRASSTUNE_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER", "1")

        with pytest.raises(HTTPException) as limit:
            accept_invitation(
                invitation.id,
                AcceptInvitationRequest(instrument_id="horn"),
                db=db,
                auth=AuthContext(user=student),
            )
        assert limit.value.status_code == 409
        assert invitation.status == "invited"
    finally:
        db.close()


def test_legacy_director_membership_can_leave_and_owner_admin_can_rotate_code():
    db = _test_db()
    try:
        owner = User(id=614, username="owner614", name="Owner", role="director", primary_instrument_id="trumpet")
        legacy = User(id=615, username="legacy615", name="Legacy", role="student", primary_instrument_id="horn")
        admin = User(id=616, username="admin616", name="Admin", role="admin", primary_instrument_id="tuba")
        db.add_all([owner, legacy, admin])
        db.commit()
        group = Group(name="Legacy Director Class", director_user_id=owner.id, join_code="LEGACY")
        db.add(group)
        db.commit()
        db.refresh(group)
        membership = GroupMember(
            group_id=group.id,
            user_id=legacy.id,
            instrument_id="horn",
            role_in_group="director",
            status="active",
        )
        db.add(membership)
        db.commit()

        first_rotation = rotate_ensemble_join_code(group.id, db=db, auth=AuthContext(user=owner))
        assert len(first_rotation["join_code"]) == 8
        assert first_rotation["join_code"] != "LEGACY"
        second_rotation = rotate_ensemble_join_code(group.id, db=db, auth=AuthContext(user=admin))
        assert second_rotation["join_code"] != first_rotation["join_code"]
        with pytest.raises(HTTPException) as denied_rotation:
            rotate_ensemble_join_code(group.id, db=db, auth=AuthContext(user=legacy))
        assert denied_rotation.value.status_code == 403

        left = leave_ensemble_group(group.id, db=db, auth=AuthContext(user=legacy))
        assert left == {"left": True, "group_id": group.id}
        db.refresh(membership)
        assert membership.status == "removed"
        assert membership.removed_at is not None
    finally:
        db.close()


def test_active_member_elevation_requires_fresh_invitation_and_acceptance():
    db = _test_db()
    try:
        owner = User(id=617, username="owner617", name="Owner", role="director", primary_instrument_id="trumpet")
        student = User(id=618, username="student618", name="Student", role="student", primary_instrument_id="horn")
        db.add_all([owner, student])
        db.commit()
        group = Group(name="Elevation Consent", director_user_id=owner.id, join_code="ELEV2345")
        db.add(group)
        db.commit()
        db.refresh(group)
        member = GroupMember(group_id=group.id, user_id=student.id, instrument_id="horn", role_in_group="student", status="active")
        db.add(member)
        db.commit()
        db.refresh(member)

        with pytest.raises(HTTPException) as silent_elevation:
            update_ensemble_member(
                group.id,
                member.id,
                UpdateGroupMemberRequest(role_in_group="assistant"),
                db=db,
                auth=AuthContext(user=owner),
            )
        assert silent_elevation.value.status_code == 409

        invited = update_ensemble_member(
            group.id,
            member.id,
            UpdateGroupMemberRequest(role_in_group="assistant", status="invited"),
            db=db,
            auth=AuthContext(user=owner),
        )
        assert invited["status"] == "invited"
        assert invited["role_in_group"] == "assistant"
        accepted = accept_invitation(
            member.id,
            AcceptInvitationRequest(instrument_id="horn"),
            db=db,
            auth=AuthContext(user=student),
        )
        assert accepted["accepted"] is True
        db.refresh(member)
        assert member.status == "active"
        assert member.role_in_group == "assistant"
    finally:
        db.close()


def test_missing_invitation_username_uses_generic_failure_wording():
    db = _test_db()
    try:
        owner = User(id=619, username="owner619", name="Owner", role="director", primary_instrument_id="trumpet")
        db.add(owner)
        db.commit()
        group = Group(name="Generic Lookup", director_user_id=owner.id, join_code="LOOK2345")
        db.add(group)
        db.commit()
        db.refresh(group)

        with pytest.raises(HTTPException) as missing:
            add_member_by_username(
                group.id,
                AddMemberByUsernameRequest(username="missing-user"),
                db=db,
                auth=AuthContext(user=owner),
            )
        assert missing.value.status_code == 404
        assert missing.value.detail == "That username could not be invited."
        assert "exists" not in missing.value.detail.lower()
    finally:
        db.close()


def test_account_deletion_removes_linked_usage_events_and_reports_count():
    db = _test_db()
    try:
        user = User(id=620, username="delete620", name="Delete Usage", role="student", primary_instrument_id="trumpet")
        db.add(user)
        db.add_all([
            UsageEvent(user_id=user.id, event_name="practice_started", properties={"source": "test"}),
            UsageEvent(user_id=None, event_name="anonymous_event", properties={}),
        ])
        db.commit()
        payload = delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=True, access_token=None),
        )
        assert payload["counts"]["usage_events"] == 1
        assert db.query(UsageEvent).filter(UsageEvent.user_id == user.id).count() == 0
        assert db.query(UsageEvent).filter(UsageEvent.user_id.is_(None)).count() == 1
    finally:
        db.close()


def test_group_list_detail_capabilities_and_assistant_roster_privacy_are_isolated():
    db = _test_db()
    try:
        users = [
            User(id=630, username="owner630", name="Owner", role="director", primary_instrument_id="trumpet"),
            User(id=631, username="student631", name="Student", role="student", primary_instrument_id="horn"),
            User(id=632, username="assistant632", name="Assistant", role="student", primary_instrument_id="trombone"),
            User(id=633, username="admin633", name="Admin", role="admin", primary_instrument_id="tuba"),
            User(id=634, username="adminmember634", name="Admin Member", role="admin", primary_instrument_id="horn"),
        ]
        db.add_all(users)
        db.commit()
        group = Group(name="Capability Contract Class", director_user_id=630, join_code=None)
        db.add(group)
        db.commit()
        db.refresh(group)
        db.add_all([
            GroupMember(group_id=group.id, user_id=631, instrument_id="horn", role_in_group="student", status="active"),
            GroupMember(group_id=group.id, user_id=632, instrument_id="trombone", role_in_group="assistant", status="active"),
            GroupMember(group_id=group.id, user_id=634, instrument_id="horn", role_in_group="assistant", status="active"),
            User(id=635, username="removed635", name="Removed", role="student", primary_instrument_id="tuba"),
            User(id=636, username="invited636", name="Invited", role="student", primary_instrument_id="trumpet"),
        ])
        db.commit()
        db.add_all([
            GroupMember(group_id=group.id, user_id=635, instrument_id="tuba", role_in_group="student", status="removed"),
            GroupMember(group_id=group.id, user_id=636, instrument_id="trumpet", role_in_group="student", status="invited"),
        ])
        db.commit()

        expected = {
            630: {"viewer_role": "owner", "viewer_can_leave": False, "viewer_can_manage": True},
            631: {"viewer_role": "student", "viewer_can_leave": True, "viewer_can_manage": False},
            632: {"viewer_role": "assistant", "viewer_can_leave": True, "viewer_can_manage": False},
            633: {"viewer_role": "admin_observer", "viewer_can_leave": False, "viewer_can_manage": True},
            634: {"viewer_role": "assistant", "viewer_can_leave": True, "viewer_can_manage": True},
        }
        for user_id, capabilities in expected.items():
            user = next(row for row in users if row.id == user_id)
            auth = AuthContext(user=user)
            listed_group = next(row for row in list_ensemble_groups(db=db, auth=auth) if row["id"] == group.id)
            detailed = get_ensemble_group(group.id, db=db, auth=auth)
            for payload in (listed_group, detailed):
                assert {key: payload[key] for key in capabilities} == capabilities
            if user_id in {631, 632}:
                assert "join_code" not in listed_group
                assert "join_code" not in detailed
            else:
                assert listed_group["join_code"] is None
                assert detailed["join_code"] is None
            if user_id == 632:
                assert detailed["roster_scope"] == "active_redacted"
                assert {member["status"] for member in detailed["members"]} == {"active"}
                assert all("user_id" not in member and "username" not in member for member in detailed["members"])
                assert {member["display_name"] for member in detailed["members"]} == {"Student", "Assistant", "Admin Member"}
    finally:
        db.close()


def test_unique_group_membership_migration_is_fail_closed_and_idempotent():
    migration = (
        Path(__file__).resolve().parents[3]
        / "supabase"
        / "migrations"
        / "20260712200824_enforce_unique_group_membership.sql"
    ).read_text().lower()
    assert "having count(*) > 1" in migration
    assert "raise exception" in migration
    assert "pg_index" in migration
    assert "indpred is null" in migration
    assert "indnkeyatts = 2" in migration
    assert "pg_get_indexdef(i.indexrelid, 1, true) = 'group_id'" in migration
    assert "pg_get_indexdef(i.indexrelid, 2, true) = 'user_id'" in migration
    assert "uq_group_members_group_user" in migration
    assert "unique (group_id, user_id)" in migration
    assert "delete" not in migration


def test_join_code_rotation_migration_targets_only_legacy_or_missing_codes():
    migration = (
        Path(__file__).resolve().parents[3]
        / "supabase"
        / "migrations"
        / "20260712222509_rotate_and_backfill_class_join_codes.sql"
    ).read_text().lower()
    assert "join_code is null or char_length(join_code) <= 6" in migration
    assert "share row exclusive" in migration
    assert "not exists" in migration
    assert "alphabet constant text := 'abcdefghjkmnpqrstuvwxyz23456789'" in migration
    assert "generate_series(1, 8)" in migration
    assert "floor(random() * length(alphabet))" in migration
    assert "create unique index if not exists groups_join_code_key" in migration


def test_env_granted_admin_is_revoked_when_email_removed(monkeypatch):
    db = _test_db()
    try:
        monkeypatch.setenv("BRASSTUNE_ADMIN_EMAILS", "owner@example.com")
        user = _sync_supabase_user(db, {"id": "admin-sub", "email": "owner@example.com", "user_metadata": {}, "app_metadata": {}})
        assert user.role == "admin"
        assert user.admin_granted_by_env is True
        # Remove the email from the list; the next sign-in revokes admin.
        monkeypatch.setenv("BRASSTUNE_ADMIN_EMAILS", "")
        user2 = _sync_supabase_user(db, {"id": "admin-sub", "email": "owner@example.com", "user_metadata": {}, "app_metadata": {}})
        assert user2.role != "admin"
        assert user2.admin_granted_by_env is False
    finally:
        db.close()


def test_manually_granted_admin_is_not_revoked_by_env(monkeypatch):
    db = _test_db()
    try:
        monkeypatch.setenv("BRASSTUNE_ADMIN_EMAILS", "")
        manual = User(
            supabase_user_id="manual-sub",
            email="manual@example.com",
            username="manualadmin",
            name="Manual Admin",
            role="admin",
            admin_granted_by_env=False,
            primary_instrument_id="trumpet",
        )
        db.add(manual)
        db.commit()
        user = _sync_supabase_user(db, {"id": "manual-sub", "email": "manual@example.com", "user_metadata": {}, "app_metadata": {}})
        assert user.role == "admin"  # not touched — was not env-granted
    finally:
        db.close()
