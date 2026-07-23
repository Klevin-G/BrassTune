import datetime as dt
import importlib.util
import io
import json
import math
import asyncio
import os
import subprocess
import sys
import threading
import zipfile
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

import app.main as main_module
import app.db.database as database_module
import app.services.audio_storage as audio_storage_module
import app.services.account_deletion as account_deletion_module
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
from app.db.database import Base, DATABASE_URL, SessionLocal, database_backend, engine
from app.db.maintenance import clear_practice_data, repair_demo_data
from app.db.seed import _sync_explicit_identity_sequences, seed_demo_data
from app.main import app
from app.models.db import AccountDeletionJob, AudioStorageJob, DeletedIdentityTombstone, Group, GroupMember, NoteEvent, PitchSample, PracticeSession, UsageEvent, User
from app.services.account_deletion import ensure_deletion_tombstone_key_state
from app.schemas.schemas import (
    MAX_BATCH_PITCH_FRAMES,
    AcceptInvitationRequest,
    AccountDeletionRequest,
    AddMemberByUsernameRequest,
    CreateGroupRequest,
    JoinByCodeRequest,
    UpdateGroupMemberRequest,
)
from app.services.audio_storage import AudioReplaceResult, delete_audio_for_session, prepare_audio_upload, replace_audio_for_session, reserve_audio_upload, retry_audio_storage_jobs
from app.services.serializers import session_to_dict
from app.services.session_service import save_pitch_frames, start_session

WEBM_AUDIO_BYTES = b"\x1a\x45\xdf\xa3webm-audio-bytes"


def _test_db():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    ensure_deletion_tombstone_key_state(db, allow_initialization=True)
    db.commit()
    return db


def test_sqlite_engine_uses_busy_timeout_for_browser_ci_contention():
    if not DATABASE_URL.startswith("sqlite"):
        return
    with engine.connect() as connection:
        busy_timeout_ms = connection.exec_driver_sql("PRAGMA busy_timeout").scalar()
        journal_mode = str(connection.exec_driver_sql("PRAGMA journal_mode").scalar()).lower()
    assert busy_timeout_ms >= 30000
    assert journal_mode in {"wal", "memory"}


def test_legacy_sqlite_account_deletion_jobs_are_rebuilt_nullable_without_data_loss(monkeypatch, tmp_path):
    legacy_engine = create_engine("sqlite:///%s" % (tmp_path / "legacy.db"))
    with legacy_engine.begin() as connection:
        connection.execute(
            text(
                "create table account_deletion_jobs ("
                "id integer not null primary key, user_id integer not null, supabase_user_id varchar, "
                "idempotency_key varchar not null unique, stage varchar not null, status varchar not null, "
                "retry_count integer not null, next_retry_at datetime, safe_error_category varchar, "
                "counts_json json not null, completed_at datetime, created_at datetime not null, updated_at datetime not null)"
            )
        )
        connection.execute(
            text(
                "insert into account_deletion_jobs values "
                "(1, 42, 'subject-42', 'delete-user-42', 'external_cleanup_failed', 'retryable_failure', "
                "1, null, 'external_identity_cleanup_failed', '{}', null, current_timestamp, current_timestamp)"
            )
        )
    monkeypatch.setattr(database_module, "engine", legacy_engine)

    database_module._ensure_sqlite_account_deletion_user_id_nullable()

    with legacy_engine.connect() as connection:
        columns = {row[1]: row for row in connection.execute(text("pragma table_info(account_deletion_jobs)"))}
        row = connection.execute(text("select user_id, supabase_user_id, status from account_deletion_jobs")).one()
    assert columns["user_id"][3] == 0
    assert row == (42, "subject-42", "retryable_failure")


def test_fresh_sqlite_tombstone_config_has_expand_phase_and_is_readiness_compatible(monkeypatch):
    import app.db.readiness as readiness_module

    fresh_engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(fresh_engine)
    monkeypatch.setattr(database_module, "engine", fresh_engine)
    database_module.ensure_additive_columns()

    with fresh_engine.begin() as connection:
        columns = {
            row[1]: row
            for row in connection.execute(text("pragma table_info(deleted_identity_tombstone_config)"))
        }
        connection.execute(
            text(
                "insert into deleted_identity_tombstone_config (id, key_verifier, created_at) "
                "values (1, :verifier, current_timestamp)"
            ),
            {"verifier": "a" * 64},
        )
        phase = connection.execute(
            text("select enforcement_phase from deleted_identity_tombstone_config where id = 1")
        ).scalar_one()

    assert columns["enforcement_phase"][3] == 1
    assert columns["enforcement_phase"][4] == "'expand'"
    assert phase == "expand"
    monkeypatch.setattr(
        readiness_module,
        "_configured_engine",
        lambda: (fresh_engine, False, "sqlite:///:memory:"),
    )
    assert readiness_module.database_readiness_issues() == []


def test_existing_sqlite_tombstone_config_adds_expand_phase(monkeypatch):
    legacy_engine = create_engine("sqlite:///:memory:")
    with legacy_engine.begin() as connection:
        connection.execute(
            text(
                "create table deleted_identity_tombstone_config ("
                "id integer not null primary key, key_verifier varchar(64) not null, "
                "created_at datetime not null)"
            )
        )
        connection.execute(
            text(
                "insert into deleted_identity_tombstone_config (id, key_verifier, created_at) "
                "values (1, :verifier, current_timestamp)"
            ),
            {"verifier": "b" * 64},
        )
    monkeypatch.setattr(database_module, "engine", legacy_engine)
    monkeypatch.setattr(database_module, "DATABASE_URL", "postgresql+psycopg://selected-by-ci")

    database_module.ensure_additive_columns()
    with legacy_engine.begin() as connection:
        connection.execute(
            text(
                "update deleted_identity_tombstone_config "
                "set enforcement_phase = 'legacy-invalid'"
            )
        )
    database_module.ensure_additive_columns()

    with legacy_engine.connect() as connection:
        columns = {
            row[1]: row
            for row in connection.execute(text("pragma table_info(deleted_identity_tombstone_config)"))
        }
        phase = connection.execute(
            text("select enforcement_phase from deleted_identity_tombstone_config where id = 1")
        ).scalar_one()
    assert columns["enforcement_phase"][3] == 1
    assert columns["enforcement_phase"][4] == "'expand'"
    assert phase == "expand"


def test_default_pytest_database_is_process_isolated():
    if os.getenv("BRASSTUNE_PYTEST_DATABASE_ISOLATED") != "1":
        pytest.skip("Caller explicitly selected the test database.")
    assert DATABASE_URL.startswith("sqlite:///")
    assert not DATABASE_URL.endswith("/backend/data/brasstune.db")
    assert "brasstune-pytest-" in DATABASE_URL


def _probe_pytest_database_environment(env):
    code = """
import json
import os
import runpy
import sys

state = runpy.run_path(sys.argv[1])
from app.db.database import DATABASE_URL
print(json.dumps({
    "database_url": DATABASE_URL,
    "isolated": os.getenv("BRASSTUNE_PYTEST_DATABASE_ISOLATED"),
}))
"""
    result = subprocess.run(
        [sys.executable, "-c", code, str(Path(__file__).with_name("conftest.py"))],
        cwd=Path(__file__).resolve().parents[2],
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout.strip().splitlines()[-1])


def test_pytest_ignores_ambient_application_database_urls(tmp_path):
    env = os.environ.copy()
    env.pop("BRASSTUNE_TEST_DATABASE_URL", None)
    env["BRASSTUNE_DATABASE_URL"] = "sqlite:///%s" % (tmp_path / "ambient-brasstune.db")
    env["DATABASE_URL"] = "sqlite:///%s" % (tmp_path / "ambient-generic.db")
    result = _probe_pytest_database_environment(env)
    assert result["isolated"] == "1"
    assert "brasstune-pytest-" in result["database_url"]
    assert "ambient" not in result["database_url"]


def test_pytest_requires_test_only_database_url_for_explicit_database(tmp_path):
    explicit_url = "sqlite:///%s" % (tmp_path / "explicit-test.db")
    env = os.environ.copy()
    env["BRASSTUNE_TEST_DATABASE_URL"] = explicit_url
    env["BRASSTUNE_DATABASE_URL"] = "sqlite:///%s" % (tmp_path / "ambient-brasstune.db")
    env["DATABASE_URL"] = "sqlite:///%s" % (tmp_path / "ambient-generic.db")
    result = _probe_pytest_database_environment(env)
    assert result == {"database_url": explicit_url, "isolated": None}


def test_backend_requirements_install_uvicorn_websocket_protocol():
    requirements = (Path(__file__).resolve().parents[2] / "requirements.txt").read_text()
    assert "uvicorn[standard]" in requirements or "websockets" in requirements or "wsproto" in requirements
    assert importlib.util.find_spec("websockets") or importlib.util.find_spec("wsproto")


def test_backend_requirements_use_sqlalchemy_two_floor():
    requirements = (Path(__file__).resolve().parents[2] / "requirements.txt").read_text()
    constraints = (Path(__file__).resolve().parents[2] / "constraints.txt").read_text()
    assert "sqlalchemy>=2.0,<3" in requirements.lower()
    assert "sqlalchemy>=2.0" in constraints.lower()


def test_backend_deploy_and_ci_use_hash_pinned_lockfiles():
    root = Path(__file__).resolve().parents[3]
    prod_lock = (root / "backend" / "requirements-prod.lock").read_text()
    dev_lock = (root / "backend" / "requirements-dev.lock").read_text()
    assert "--hash=sha256:" in prod_lock
    assert "--hash=sha256:" in dev_lock
    assert "fastapi==" in prod_lock
    assert "pytest==" in dev_lock
    assert "pip-audit==" in dev_lock
    assert "pip install --require-hashes -r requirements-prod.lock" in (root / "render.yaml").read_text()
    for workflow in ("backend.yml", "frontend.yml", "device-simulation.yml", "security.yml"):
        contents = (root / ".github" / "workflows" / workflow).read_text()
        assert "pip install --require-hashes -r requirements" in contents
        assert "--upgrade pip" not in contents


def test_postgresql_integration_workflow_supplies_test_only_tombstone_secret_to_readiness():
    root = Path(__file__).resolve().parents[3]
    workflow = (root / ".github" / "workflows" / "backend.yml").read_text()
    test_secret = "ci-test-only-deletion-tombstone-secret-20260723"

    assert f"BRASSTUNE_DELETION_TOMBSTONE_SECRET: {test_secret}" in workflow
    assert len(test_secret.encode("utf-8")) >= 32
    assert "python -m app.db.scrub_deletion_privacy && python -m app.db.check_ready" in workflow


def test_deploy_uses_an_audited_locked_local_vercel_cli_and_disallows_all_target():
    root = Path(__file__).resolve().parents[3]
    deploy = (root / ".github" / "workflows" / "deploy.yml").read_text()
    security = (root / ".github" / "workflows" / "security.yml").read_text()
    vercel_cli_dir = root / ".github" / "tools" / "vercel-cli"
    package = json.loads((vercel_cli_dir / "package.json").read_text())
    lock = json.loads((vercel_cli_dir / "package-lock.json").read_text())

    assert package["dependencies"]["vercel"] == "54.14.0"
    assert package["overrides"] == {
        "@tootallnate/once": "2.0.1",
        "ajv": "8.18.0",
        "js-yaml": "4.3.0",
        "minimatch@10.1.1": "10.2.5",
        "path-to-regexp@6.1.0": "6.3.0",
        "path-to-regexp@8.2.0": "8.4.0",
        "path-to-regexp@8.3.0": "8.4.0",
        "smol-toml": "1.6.1",
        "srvx": "0.11.13",
        "tar": "7.5.19",
        "undici@5.28.4": "6.27.0",
    }
    locked_vercel = lock["packages"]["node_modules/vercel"]
    assert locked_vercel["version"] == "54.14.0"
    assert locked_vercel["integrity"].startswith("sha512-")
    locked_overrides = {
        "node_modules/@tootallnate/once": "2.0.1",
        "node_modules/ajv": "8.18.0",
        "node_modules/js-yaml": "4.3.0",
        "node_modules/minimatch": "10.2.5",
        "node_modules/path-to-regexp": "8.4.0",
        "node_modules/@vercel/node/node_modules/path-to-regexp": "6.3.0",
        "node_modules/smol-toml": "1.6.1",
        "node_modules/srvx": "0.11.13",
        "node_modules/tar": "7.5.19",
        "node_modules/undici": "6.27.0",
    }
    for path, version in locked_overrides.items():
        assert lock["packages"][path]["version"] == version
        assert lock["packages"][path]["integrity"].startswith("sha512-")

    install = "npm ci --prefix .github/tools/vercel-cli --ignore-scripts"
    audit = "npm audit --omit=dev --prefix .github/tools/vercel-cli"
    first_credential = "VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}"
    assert install in deploy
    assert audit in deploy
    assert deploy.index(install) < deploy.index(audit) < deploy.index(first_credential)
    assert "cache-dependency-path: .github/tools/vercel-cli/package-lock.json" in deploy
    assert "npm install -g vercel" not in deploy
    assert ".github/tools/vercel-cli/node_modules/.bin/vercel" in deploy
    assert "default: all" not in deploy
    assert "- all" not in deploy
    assert "target == 'all'" not in deploy

    assert security.count('".github/workflows/deploy.yml"') == 2
    assert security.count('".github/tools/vercel-cli/**"') == 2
    assert "frontend/package-lock.json\n            .github/tools/vercel-cli/package-lock.json" in security
    assert install in security
    assert audit in security
    assert security.index(install) < security.index(audit) < security.index("secrets.GITHUB_TOKEN")
    assert "VERCEL_TOKEN" not in security


def test_render_deploy_removes_legacy_cors_regex_and_uses_authoritative_runtime_values():
    root = Path(__file__).resolve().parents[3]
    render = (root / "render.yaml").read_text()
    deploy = (root / ".github" / "workflows" / "deploy.yml").read_text()
    assert "BRASSTUNE_ALLOW_CORS_REGEX" not in render
    assert "CORS_ALLOWED_ORIGIN_REGEX" not in render
    assert "BRASSTUNE_DELETION_TOMBSTONE_SECRET" in render
    assert "BRASSTUNE_DELETION_TOMBSTONE_SECRET\n        sync: false" in render
    assert "generateValue: true" not in render
    assert 'PYTHON_VERSION\n        value: "3.11.15"' in render
    assert "/env-vars/BRASSTUNE_DELETION_TOMBSTONE_SECRET" in deploy
    assert "secrets.BRASSTUNE_DELETION_TOMBSTONE_SECRET" in deploy
    assert "--request DELETE" in deploy
    assert "/env-vars/${key}" in deploy
    assert "delete_render_env_var BRASSTUNE_ALLOW_CORS_REGEX" in deploy
    assert "delete_render_env_var CORS_ALLOWED_ORIGIN_REGEX" in deploy
    assert deploy.index("delete_render_env_var CORS_ALLOWED_ORIGIN_REGEX") < deploy.index(
        "delete_render_env_var BRASSTUNE_ALLOW_CORS_REGEX"
    )
    assert "204)" in deploy
    assert "404)" in deploy
    assert deploy.index("Disable Render auto-deploy") < deploy.index("Remove legacy Render CORS regex variables")
    assert deploy.index("Remove legacy Render CORS regex variables") < deploy.index("Trigger exact Render deploy")
    assert "/env-vars/PYTHON_VERSION" in deploy
    assert 'BRASSTUNE_RENDER_PYTHON_VERSION: "3.11.15"' in deploy


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
        assert response.json()["code"] == "bad_request"
        response = client.get("/api/recommendations?instrument_id=trumpett")
        assert response.status_code == 400
        assert response.json()["code"] == "bad_request"


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
    assert response.json()["code"] == "payload_too_large"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]


def test_global_json_body_limit_covers_structured_json_and_is_bounded(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_MAX_JSON_BODY_BYTES", "8")
    with TestClient(app) as client:
        response = client.post(
            "/api/sessions/start",
            headers={"Content-Type": "application/problem+json"},
            content=b'{"instrument_id":"trumpet"}',
        )
    assert response.status_code == 413
    assert response.json()["code"] == "payload_too_large"

    monkeypatch.setenv("BRASSTUNE_MAX_JSON_BODY_BYTES", "0")
    assert main_module._bounded_json_body_limit() == main_module._DEFAULT_MAX_JSON_BODY_BYTES
    monkeypatch.setenv("BRASSTUNE_MAX_JSON_BODY_BYTES", str(10**12))
    assert main_module._bounded_json_body_limit() == main_module._ABSOLUTE_MAX_JSON_BODY_BYTES


def test_validation_error_has_stable_code_and_preserves_detail_shape():
    with TestClient(app) as client:
        response = client.post(
            "/api/sessions/start",
            json={"instrument_id": "trumpet", "name": "x" * 121},
        )
    assert response.status_code == 422
    assert response.json()["code"] == "request_validation_failed"
    assert isinstance(response.json()["detail"], list)


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


def test_local_cors_origins_still_reject_wildcards_credentials_and_paths(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    for origin in ("*", "http://user:password@localhost:5173", "http://localhost:5173/path"):
        monkeypatch.setenv("CORS_ALLOWED_ORIGINS", origin)
        with pytest.raises(RuntimeError):
            allowed_origins()


def test_cors_preflight_allows_public_headers_but_not_maintenance_secret():
    with TestClient(app) as client:
        allowed = client.options(
            "/api/sessions/start",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )
        blocked = client.options(
            "/api/maintenance/audio-storage/retry",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "x-brasstune-maintenance-secret",
            },
        )
    assert allowed.status_code == 200
    assert blocked.status_code == 400


def test_overlong_origin_is_rejected_before_cors_regex_processing():
    with TestClient(app) as client:
        response = client.get("/api/instruments", headers={"Origin": "https://" + ("a" * 600)})
    assert response.status_code == 400
    assert response.json()["code"] == "bad_request"


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
    assert response.headers["cache-control"] == "no-store"
    assert len(response.headers["x-request-id"]) == 32


def test_unhandled_http_errors_are_generic_hardened_and_secret_free_in_logs(caplog):
    route_path = "/api/__test_unhandled_error"

    if not any(getattr(route, "path", None) == route_path for route in app.routes):
        @app.get(route_path)
        def _raise_test_error():
            raise RuntimeError("database password leaked in traceback")

    with caplog.at_level("ERROR", logger="brasstune.api"):
        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.get(route_path)
    assert response.status_code == 500
    assert response.json()["detail"] == "The server could not complete this request."
    assert "password" not in response.text.lower()
    assert response.headers["x-content-type-options"] == "nosniff"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert response.json()["code"] == "internal_error"
    assert "password" not in caplog.text.lower()
    assert route_path in caplog.text


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
    assert _postgres_column_type_issues(
        "audio_storage_jobs",
        [{"name": "details_json", "type": "TEXT"}],
    ) == ["Column audio_storage_jobs.details_json must be jsonb, not text."]


def test_postgres_readiness_requires_terminal_job_identifier_nullability():
    from app.db.readiness import _postgres_column_nullability_issues

    assert _postgres_column_nullability_issues(
        "audio_storage_jobs",
        [{"name": "user_id", "nullable": False}, {"name": "session_id", "nullable": True}],
    ) == ["Column audio_storage_jobs.user_id must be nullable."]
    assert _postgres_column_nullability_issues(
        "audio_storage_jobs",
        [{"name": "user_id", "nullable": True}, {"name": "session_id", "nullable": True}],
    ) == []

    assert _postgres_column_nullability_issues(
        "account_deletion_jobs",
        [{"name": "user_id", "nullable": False}],
    ) == ["Column account_deletion_jobs.user_id must be nullable."]


def test_postgres_readiness_tracks_account_deletion_expand_and_contract_phases():
    from app.db.readiness import _account_deletion_constraint_phase_issues

    assert _account_deletion_constraint_phase_issues("expand", []) == []
    assert _account_deletion_constraint_phase_issues("expand", [False]) == [
        "Expand-phase account deletion privacy must not install the terminal constraint."
    ]
    assert _account_deletion_constraint_phase_issues("contract", [True]) == []
    assert _account_deletion_constraint_phase_issues("contract", []) == [
        "Contract-phase account deletion privacy requires one validated terminal constraint."
    ]
    assert _account_deletion_constraint_phase_issues("contract", [False]) == [
        "Contract-phase account deletion privacy requires one validated terminal constraint."
    ]
    assert _account_deletion_constraint_phase_issues(None, []) == [
        "Account deletion privacy rollout phase is missing or invalid."
    ]


def test_deployed_readiness_requires_dedicated_stable_deletion_tombstone_key(monkeypatch):
    from app.db.readiness import maintenance_readiness_issues

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET", "configured")
    monkeypatch.delenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", raising=False)
    assert "BRASSTUNE_DELETION_TOMBSTONE_SECRET" in " ".join(maintenance_readiness_issues())
    monkeypatch.setenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", "too-short")
    assert "at least 32 bytes" in " ".join(maintenance_readiness_issues())
    monkeypatch.setenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", "production-deletion-tombstone-key-32-bytes")
    assert maintenance_readiness_issues() == []


def test_deployed_release_readiness_requires_one_matching_full_revision(monkeypatch):
    from app.db.readiness import release_readiness_issues, version_payload

    monkeypatch.setenv("APP_ENV", "production")
    for name in ("RENDER_GIT_COMMIT", "VERCEL_GIT_COMMIT_SHA", "GITHUB_SHA", "BRASSTUNE_RELEASE_SHA"):
        monkeypatch.delenv(name, raising=False)
    assert release_readiness_issues() == ["Missing exact release revision identity."]

    monkeypatch.setenv("BRASSTUNE_RELEASE_SHA", "abc123")
    assert release_readiness_issues() == ["Release revision identity must be a full Git object id."]

    revision = "a" * 40
    monkeypatch.setenv("BRASSTUNE_RELEASE_SHA", revision)
    monkeypatch.setenv("RENDER_GIT_COMMIT", revision.upper())
    assert release_readiness_issues() == []
    assert version_payload()["commit_sha"] == revision.upper()
    assert version_payload()["revision_source"] == "RENDER_GIT_COMMIT"

    monkeypatch.setenv("RENDER_GIT_COMMIT", "b" * 40)
    assert release_readiness_issues() == ["Configured release revision identities do not match."]


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


def test_start_session_fails_closed_when_owner_is_missing():
    db = _test_db()
    try:
        with pytest.raises(HTTPException) as missing_owner:
            start_session(db, "trumpet", "No owner", 440.0, user_id=999_999)
        assert missing_owner.value.status_code == 404
        assert db.query(User).count() == 0
        assert db.query(PracticeSession).count() == 0
    finally:
        db.close()


def test_start_session_finalizes_previous_active_session_for_owner():
    db = _test_db()
    try:
        user = User(id=901, username="session-owner-901", name="Session Owner", primary_instrument_id="trumpet")
        db.add(user)
        db.commit()

        first = start_session(db, "trumpet", "First", 440.0, user_id=user.id)
        second = start_session(db, "trumpet", "Second", 440.0, user_id=user.id)
        db.refresh(first)

        assert first.ended_at is not None
        assert second.ended_at is None
        assert (
            db.query(PracticeSession)
            .filter(
                PracticeSession.user_id == user.id,
                PracticeSession.ended_at.is_(None),
            )
            .count()
            == 1
        )
    finally:
        db.close()


def test_stopped_session_rejects_new_pitch_samples():
    with TestClient(app) as client:
        session = client.post(
            "/api/sessions/start",
            json={"instrument_id": "trumpet", "reference_pitch_hz": 440},
        ).json()
        stopped = client.post(f"/api/sessions/{session['id']}/stop")
        frame = frequency_to_pitch_frame(
            midi_to_frequency(60),
            MIN_RECORDING_CONFIDENCE,
            0.1,
            0,
            "trumpet",
            440.0,
        ).to_dict()
        response = client.post(f"/api/sessions/{session['id']}/samples", json=frame)

    assert stopped.status_code == 200
    assert response.status_code == 409
    assert response.json()["code"] == "conflict"
    assert "ended" in response.json()["detail"].lower()


def test_repeated_stop_preserves_original_end_timestamp():
    with TestClient(app) as client:
        session = client.post(
            "/api/sessions/start",
            json={"instrument_id": "trumpet", "reference_pitch_hz": 440},
        ).json()
        first = client.post(f"/api/sessions/{session['id']}/stop")
        second = client.post(f"/api/sessions/{session['id']}/stop")

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["ended_at"] == first.json()["ended_at"]
    db = SessionLocal()
    try:
        completion_events = [
            event
            for event in db.query(UsageEvent).filter(UsageEvent.event_name == "session_completed").all()
            if event.properties.get("session_id") == session["id"]
        ]
        assert len(completion_events) == 1
    finally:
        db.close()


def test_websocket_disconnect_finalizes_socket_created_session():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json(
                {
                    "type": "start_session",
                    "instrument_id": "trumpet",
                    "name": "Disconnected practice",
                    "reference_pitch_hz": 440,
                }
            )
            started = websocket.receive_json()
            assert started["type"] == "session_started"
            session_id = started["session"]["id"]

        session = client.get(f"/api/sessions/{session_id}")

    assert session.status_code == 200
    assert session.json()["ended_at"] is not None


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


@pytest.mark.skipif(database_backend(DATABASE_URL) != "postgresql", reason="PostgreSQL identity regression")
def test_demo_seed_repairs_identities_without_rewinding_them():
    db = SessionLocal()
    original_states = {}
    try:
        seed_demo_data(db)
        sequence_names = {}
        maximum_ids = {}
        for table_name in ("users", "groups"):
            sequence_names[table_name] = db.execute(
                text(f"SELECT pg_get_serial_sequence('public.{table_name}', 'id')")
            ).scalar_one()
            maximum_ids[table_name] = db.execute(
                text(f"SELECT MAX(id) FROM public.{table_name}")
            ).scalar_one()
            last_value = db.execute(
                text("SELECT pg_sequence_last_value(CAST(:sequence_name AS regclass))"),
                {"sequence_name": sequence_names[table_name]},
            ).scalar_one_or_none()
            start_value = db.execute(
                text("SELECT seqstart FROM pg_sequence WHERE seqrelid = CAST(:sequence_name AS regclass)"),
                {"sequence_name": sequence_names[table_name]},
            ).scalar_one()
            original_states[table_name] = {
                "value": last_value if last_value is not None else start_value,
                "is_called": last_value is not None,
            }
            db.execute(
                text("SELECT setval(CAST(:sequence_name AS regclass), 1, false)"),
                {"sequence_name": sequence_names[table_name]},
            )

        _sync_explicit_identity_sequences(db)
        repaired_next_values = {
            table_name: db.execute(
                text("SELECT nextval(CAST(:sequence_name AS regclass))"),
                {"sequence_name": sequence_name},
            ).scalar_one()
            for table_name, sequence_name in sequence_names.items()
        }
        assert all(repaired_next_values[name] == maximum_ids[name] + 1 for name in sequence_names)

        high_water_marks = {name: value + 50 for name, value in repaired_next_values.items()}
        for table_name, sequence_name in sequence_names.items():
            db.execute(
                text("SELECT setval(CAST(:sequence_name AS regclass), :value, true)"),
                {"sequence_name": sequence_name, "value": high_water_marks[table_name]},
            )

        _sync_explicit_identity_sequences(db)
        assert all(
            db.execute(
                text("SELECT nextval(CAST(:sequence_name AS regclass))"),
                {"sequence_name": sequence_names[table_name]},
            ).scalar_one()
            == high_water_marks[table_name] + 1
            for table_name in sequence_names
        )
    finally:
        for table_name, state in original_states.items():
            db.execute(
                text("SELECT setval(CAST(:sequence_name AS regclass), :value, :is_called)"),
                {
                    "sequence_name": sequence_names[table_name],
                    "value": state["value"],
                    "is_called": state["is_called"],
                },
            )
        db.commit()
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


def test_supabase_auth_rejects_credentialed_or_pathful_base_urls(monkeypatch):
    from app.api.auth import _supabase_endpoint

    for value in (
        "https://user:password@example.supabase.co",
        "https://example.supabase.co/project",
        "https://example.supabase.co?token=value",
    ):
        monkeypatch.setenv("SUPABASE_URL", value)
        with pytest.raises(HTTPException) as blocked:
            _supabase_endpoint("/auth/v1/user")
        assert blocked.value.status_code == 503

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SUPABASE_URL", "http://localhost:54321")
    with pytest.raises(HTTPException) as deployed_localhost:
        _supabase_endpoint("/auth/v1/user")
    assert deployed_localhost.value.status_code == 503


def test_bearer_token_length_is_bounded():
    from app.api.auth import _bearer_token

    with pytest.raises(HTTPException) as blocked:
        _bearer_token("Bearer " + ("x" * 16_385))
    assert blocked.value.status_code == 413


def test_supabase_storage_rejects_unsafe_bucket_and_cross_origin_signed_url(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://project.supabase.co")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "test-service-key-placeholder")
    monkeypatch.setenv("SUPABASE_STORAGE_BUCKET", "../private")
    with pytest.raises(HTTPException) as unsafe_bucket:
        audio_storage_module._supabase_bucket()
    assert unsafe_bucket.value.status_code == 503

    monkeypatch.setenv("SUPABASE_STORAGE_BUCKET", "session-audio")

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self):
            return json.dumps({"signedURL": "https://evil.example/recording.webm"}).encode("utf-8")

    monkeypatch.setattr("urllib.request.urlopen", lambda *_args, **_kwargs: FakeResponse())
    with pytest.raises(HTTPException) as invalid_signed_url:
        audio_storage_module.create_supabase_signed_url("1/1/recording.webm")
    assert invalid_signed_url.value.status_code == 502
    assert "invalid" in invalid_signed_url.value.detail.lower()


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


@pytest.mark.parametrize("duration", ["nan", "inf", "-1", "86401"])
def test_audio_upload_rejects_invalid_duration_metadata(duration):
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        response = client.post(
            f"/api/sessions/{session['id']}/audio",
            content=WEBM_AUDIO_BYTES,
            headers={"Content-Type": "audio/webm", "X-Audio-Duration-Seconds": duration},
        )
    assert response.status_code == 400
    assert "duration" in response.json()["detail"].lower()


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
        assert message["code"] == "permission_denied"
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
    assert message["code"] == "payload_too_large"
    assert "too large" in message["message"].lower()


def test_websocket_rejects_query_token_auth():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch?token=dev-user-1") as websocket:
            message = websocket.receive_json()
    assert message["type"] == "error"
    assert message["code"] == "query_auth_disabled"
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
    assert message["code"] == "origin_not_allowed"
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
    assert message["code"] == "payload_too_large"
    assert "too large" in message["message"].lower()


def test_websocket_binary_frames_close_with_stable_unsupported_data_error():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_bytes(b"not-json")
            message = websocket.receive_json()
            assert message == {
                "type": "error",
                "code": "binary_message_not_supported",
                "message": "Binary WebSocket messages are not supported.",
            }
            with pytest.raises(WebSocketDisconnect) as disconnected:
                websocket.receive_json()
    assert disconnected.value.code == 1003


def test_websocket_invalid_stop_session_is_recoverable_and_stable():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json({"type": "stop_session", "session_id": True})
            message = websocket.receive_json()
            assert message["code"] == "request_validation_failed"
            websocket.send_json({"type": "ping"})
            assert websocket.receive_json() == {"type": "pong"}


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


def test_audio_upload_limit_can_only_be_lowered_not_disabled_or_raised(monkeypatch):
    absolute_limit = audio_storage_module.MAX_AUDIO_UPLOAD_BYTES
    monkeypatch.setenv("SESSION_AUDIO_MAX_BYTES", "8")
    assert audio_storage_module.audio_upload_limit_bytes() == 8
    monkeypatch.setenv("SESSION_AUDIO_MAX_BYTES", "0")
    assert audio_storage_module.audio_upload_limit_bytes() == absolute_limit
    monkeypatch.setenv("SESSION_AUDIO_MAX_BYTES", str(absolute_limit * 10))
    assert audio_storage_module.audio_upload_limit_bytes() == absolute_limit


def test_unsupported_audio_storage_backend_is_rejected_before_reservation(monkeypatch):
    db = _test_db()
    try:
        session = _session(db, 49, "trumpet", dt.datetime(2026, 6, 15))
        monkeypatch.setenv("SESSION_AUDIO_STORAGE_BACKEND", "misspelled-provider")
        with pytest.raises(HTTPException) as blocked:
            prepare_audio_upload(session, b"RIFF....WAVE", "audio/wav", 4.0)
        assert blocked.value.status_code == 503
        assert db.query(AudioStorageJob).count() == 0
    finally:
        db.close()


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
        assert {"account.json", "sessions.json", "memberships.json", "owned_groups.json", "invitations.json", "recommendations.json", "usage_events.json"}.issubset(names)
        assert "account_deletion_jobs.json" not in names
        assert "deleted_identity_tombstones.json" not in names
        account = json.loads(archive.read("account.json"))
        sessions = json.loads(archive.read("sessions.json"))
        usage_events = json.loads(archive.read("usage_events.json"))
    assert account["id"] == 1
    assert account["role"] == "student"
    assert all("audio_object_key" not in row for row in sessions)
    assert all("audio_storage_provider" not in row for row in sessions)
    assert all("user_id" not in row for row in usage_events)


def test_account_export_applies_total_row_budget_to_lifecycle_data(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_EXPORT_MAX_TOTAL_ROWS", "1")
    with TestClient(app) as client:
        response = client.get("/api/users/me/export.zip", headers={"Authorization": "Bearer dev-user-1"})
    assert response.status_code == 413
    assert response.json()["code"] == "payload_too_large"


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


def test_cross_mime_audio_replacement_commits_metadata_before_old_cleanup(monkeypatch):
    db = _test_db()
    calls = []
    try:
        session = _session(db, 52, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "52/%s/recording.webm" % session.id
        session.audio_mime_type = "audio/webm"
        session.audio_size_bytes = 100
        db.commit()
        db.refresh(session)

        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage.secrets.token_hex", lambda _size: "replacement")
        monkeypatch.setattr(
            "app.services.audio_storage._upload_to_supabase",
            lambda key, data, mime: calls.append(("upload", key, mime, len(data))),
        )
        monkeypatch.setattr(
            "app.services.audio_storage._delete_supabase_object",
            lambda key: calls.append(("delete", key)),
        )
        real_commit = db.commit
        commit_count = 0

        def tracked_commit():
            nonlocal commit_count
            commit_count += 1
            calls.append(("commit", commit_count))
            real_commit()

        monkeypatch.setattr(db, "commit", tracked_commit)

        result = replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 2.5)
        replacement_key = "52/%s/versions/replacement/recording.wav" % session.id
        assert result.cleanup_pending is False
        assert result.reconciliation_pending is False
        assert session.audio_object_key == replacement_key
        assert session.audio_mime_type == "audio/wav"
        assert calls == [
            ("commit", 1),
            ("upload", replacement_key, "audio/wav", 12),
            ("commit", 2),
            ("commit", 3),
            ("delete", "52/%s/recording.webm" % session.id),
            ("commit", 4),
        ]
        jobs = db.query(AudioStorageJob).order_by(AudioStorageJob.id.asc()).all()
        assert [(job.action, job.status) for job in jobs] == [
            ("reconcile_metadata", "completed"),
            ("delete_object", "completed"),
        ]
        for job in jobs:
            assert job.user_id is None
            assert job.session_id is None
            assert job.idempotency_key == "terminal:%s" % job.id
            assert job.object_key == "[redacted]"
            assert job.size_bytes == 0
            assert job.details_json == {}
            assert job.completed_at is not None

        delete_audio_for_session(session)
        assert calls[-1] == ("delete", replacement_key)
        assert session.audio_object_key is None
    finally:
        db.close()


def test_cross_mime_audio_commit_failure_discards_only_new_object(monkeypatch):
    db = _test_db()
    calls = []
    try:
        session = _session(db, 53, "trumpet", dt.datetime(2026, 6, 15))
        previous_key = "53/%s/recording.webm" % session.id
        session.audio_storage_provider = "supabase"
        session.audio_object_key = previous_key
        session.audio_mime_type = "audio/webm"
        session.audio_size_bytes = 100
        db.commit()
        db.refresh(session)

        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage.secrets.token_hex", lambda _size: "replacement")
        monkeypatch.setattr(
            "app.services.audio_storage._upload_to_supabase",
            lambda key, data, mime: calls.append(("upload", key)),
        )
        real_commit = db.commit
        commit_count = 0

        def fail_metadata_commit_only():
            nonlocal commit_count
            commit_count += 1
            calls.append(("commit", commit_count))
            if commit_count == 2:
                raise RuntimeError("commit failed")
            real_commit()

        monkeypatch.setattr(db, "commit", fail_metadata_commit_only)
        monkeypatch.setattr(
            "app.services.audio_storage._delete_supabase_object",
            lambda key: calls.append(("delete", key)),
        )

        with pytest.raises(HTTPException) as blocked:
            replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 3.0)
        assert blocked.value.status_code == 503
        replacement_key = "53/%s/versions/replacement/recording.wav" % session.id
        assert "staged upload was removed" in blocked.value.detail.lower()
        assert calls == [
            ("commit", 1),
            ("upload", replacement_key),
            ("commit", 2),
            ("delete", replacement_key),
            ("commit", 3),
        ]
        db.refresh(session)
        assert session.audio_object_key == previous_key
        assert session.audio_mime_type == "audio/webm"
        assert session.audio_size_bytes == 100
        job = db.query(AudioStorageJob).one()
        assert job.action == "upload_reservation"
        assert job.status == "cancelled"
    finally:
        db.close()


def test_cross_mime_post_commit_cleanup_failure_keeps_new_recording_active(monkeypatch):
    db = _test_db()
    calls = []
    try:
        session = _session(db, 54, "trumpet", dt.datetime(2026, 6, 15))
        previous_key = "54/%s/recording.webm" % session.id
        replacement_key = "54/%s/versions/replacement/recording.wav" % session.id
        session.audio_storage_provider = "supabase"
        session.audio_object_key = previous_key
        session.audio_mime_type = "audio/webm"
        session.audio_size_bytes = 100
        db.commit()
        db.refresh(session)

        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage.secrets.token_hex", lambda _size: "replacement")
        monkeypatch.setattr(
            "app.services.audio_storage._upload_to_supabase",
            lambda key, data, mime: calls.append(("upload", key)),
        )

        def fail_old_cleanup(key):
            calls.append(("delete", key))
            raise HTTPException(status_code=502, detail="old cleanup failed")

        monkeypatch.setattr("app.services.audio_storage._delete_supabase_object", fail_old_cleanup)

        result = replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 3.0)
        assert result.cleanup_pending is True
        assert result.reconciliation_pending is False
        assert calls == [("upload", replacement_key), ("delete", previous_key)]
        db.refresh(session)
        assert session.audio_object_key == replacement_key
        assert session.audio_mime_type == "audio/wav"
        assert session.audio_size_bytes == 12
        jobs = db.query(AudioStorageJob).order_by(AudioStorageJob.id.asc()).all()
        assert [(job.action, job.status) for job in jobs] == [
            ("reconcile_metadata", "completed"),
            ("delete_object", "retryable_failure"),
        ]
    finally:
        db.close()


def test_audio_upload_truthfully_reports_post_commit_cleanup_pending(monkeypatch):
    def fake_replace(db, session, _data, mime_type, duration_seconds):
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "%s/%s/versions/new/recording.wav" % (session.user_id, session.id)
        session.audio_mime_type = mime_type
        session.audio_duration_seconds = duration_seconds
        session.audio_size_bytes = 12
        db.add(session)
        db.commit()
        db.refresh(session)
        return AudioReplaceResult(audio_snapshot=session_to_dict(session), cleanup_pending=True)

    monkeypatch.setattr("app.api.routes.replace_audio_for_session", fake_replace)
    with TestClient(app) as client:
        session = client.post("/api/sessions/start", json={"instrument_id": "trumpet", "reference_pitch_hz": 440}).json()
        response = client.post(
            f"/api/sessions/{session['id']}/audio",
            content=b"RIFF....WAVE",
            headers={"Content-Type": "audio/wav", "X-Audio-Duration-Seconds": "3"},
        )
    assert response.status_code == 202
    assert response.json()["uploaded"] is True
    assert response.json()["cleanup_pending"] is True
    assert "new recording is active" in response.json()["message"].lower()


def test_audio_refresh_failure_returns_snapshot_and_leaves_durable_reconciliation(monkeypatch):
    db = _test_db()
    try:
        session = _session(db, 55, "trumpet", dt.datetime(2026, 6, 15))
        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage.secrets.token_hex", lambda _size: "refresh-failure")
        monkeypatch.setattr("app.services.audio_storage._upload_to_supabase", lambda *_args: None)
        monkeypatch.setattr(db, "refresh", lambda _row: (_ for _ in ()).throw(RuntimeError("refresh failed")))

        result = replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 4.0)

        assert result.activation_pending is False
        assert result.reconciliation_pending is True
        assert result.audio_snapshot["audio_mime_type"] == "audio/wav"
        assert result.audio_snapshot["audio_size_bytes"] == 12
        job = db.query(AudioStorageJob).one()
        assert job.action == "reconcile_metadata"
        assert job.status == "pending"
        assert job.details_json["audio_snapshot"] == result.audio_snapshot
    finally:
        db.close()


def test_failed_staged_cleanup_is_durable_and_operator_retry_is_idempotent(monkeypatch):
    db = _test_db()
    try:
        session = _session(db, 56, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "56/%s/recording.webm" % session.id
        session.audio_mime_type = "audio/webm"
        session.audio_size_bytes = 100
        db.commit()
        db.refresh(session)
        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage.secrets.token_hex", lambda _size: "cleanup-retry")
        monkeypatch.setattr("app.services.audio_storage._upload_to_supabase", lambda *_args: None)
        real_commit = db.commit
        commit_count = 0

        def fail_metadata_commit_only():
            nonlocal commit_count
            commit_count += 1
            if commit_count == 2:
                raise RuntimeError("commit failed")
            real_commit()

        monkeypatch.setattr(db, "commit", fail_metadata_commit_only)
        monkeypatch.setattr(
            "app.services.audio_storage._delete_supabase_object",
            lambda _key: (_ for _ in ()).throw(HTTPException(status_code=502, detail="cleanup failed")),
        )

        with pytest.raises(HTTPException, match="queued for retry"):
            replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 4.0)

        job = db.query(AudioStorageJob).one()
        assert job.action == "delete_object"
        assert job.status == "retryable_failure"
        assert job.user_id == session.user_id
        assert job.session_id == session.id
        assert job.provider == "supabase"
        assert job.size_bytes == 12
        assert job.reason == "metadata_commit_failed_cleanup"
        job.next_retry_at = dt.datetime.utcnow() - dt.timedelta(seconds=1)
        original_object_key = job.object_key
        db.add(job)
        db.commit()
        deleted = []
        monkeypatch.setattr("app.services.audio_storage._delete_supabase_object", lambda key: deleted.append(key))

        first = retry_audio_storage_jobs(db)
        second = retry_audio_storage_jobs(db)

        assert first["completed"] == 1
        assert second["processed"] == 0
        assert deleted == [original_object_key]
        db.refresh(job)
        assert job.status == "completed"
        assert job.user_id is None
        assert job.session_id is None
        assert job.idempotency_key == "terminal:%s" % job.id
        assert job.object_key == "[redacted]"
        assert job.size_bytes == 0
        assert job.details_json == {}
    finally:
        db.close()


def test_terminal_audio_jobs_are_purged_after_bounded_short_ttl(monkeypatch):
    db = _test_db()
    try:
        jobs = []
        for suffix in ("expired", "recent"):
            job = AudioStorageJob(
                user_id=560,
                session_id=1,
                idempotency_key="ttl-%s" % suffix,
                action="delete_object",
                provider="supabase",
                object_key="560/%s/recording.webm" % suffix,
                size_bytes=10,
                reason="ttl_test",
                status="pending",
                details_json={"private": suffix},
            )
            db.add(job)
            db.flush()
            jobs.append(job.id)
        db.commit()
        assert all(audio_storage_module._mark_audio_job_completed(db, job_id) for job_id in jobs)
        expired = db.query(AudioStorageJob).filter(AudioStorageJob.id == jobs[0]).one()
        recent = db.query(AudioStorageJob).filter(AudioStorageJob.id == jobs[1]).one()
        expired.completed_at = dt.datetime.utcnow() - dt.timedelta(days=8)
        recent.completed_at = dt.datetime.utcnow() - dt.timedelta(days=6)
        db.commit()

        monkeypatch.setenv("BRASSTUNE_AUDIO_JOB_TERMINAL_RETENTION_DAYS", "7")
        result = audio_storage_module.purge_terminal_audio_storage_jobs(db)

        assert result == {"retention_days": 7, "purged": 1, "failed": False}
        assert db.query(AudioStorageJob).filter(AudioStorageJob.id == jobs[0]).first() is None
        remaining = db.query(AudioStorageJob).filter(AudioStorageJob.id == jobs[1]).one()
        assert remaining.user_id is None
        assert remaining.session_id is None
        assert remaining.object_key == "[redacted]"

        monkeypatch.setenv("BRASSTUNE_AUDIO_JOB_TERMINAL_RETENTION_DAYS", "9999")
        assert audio_storage_module._audio_job_terminal_retention_days() == 30
        monkeypatch.setenv("BRASSTUNE_AUDIO_JOB_TERMINAL_RETENTION_DAYS", "0")
        assert audio_storage_module._audio_job_terminal_retention_days() == 7
    finally:
        db.close()


def test_known_over_quota_upload_never_writes_storage(monkeypatch):
    db = _test_db()
    writes = []
    try:
        session = _session(db, 57, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_storage_provider = "supabase"
        session.audio_object_key = "57/%s/recording.webm" % session.id
        session.audio_size_bytes = 100
        db.commit()
        db.refresh(session)
        monkeypatch.setenv("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", "105")
        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage._upload_to_supabase", lambda *_args: writes.append("upload"))

        with pytest.raises(HTTPException) as blocked:
            replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 4.0)

        assert blocked.value.status_code == 413
        assert writes == []
        assert db.query(AudioStorageJob).count() == 0
    finally:
        db.close()


def test_pending_cleanup_bytes_remain_in_quota_until_retry_completes(monkeypatch):
    db = _test_db()
    writes = []
    try:
        session = _session(db, 58, "trumpet", dt.datetime(2026, 6, 15))
        session.audio_size_bytes = 50
        db.add(
            AudioStorageJob(
                user_id=58,
                session_id=session.id,
                idempotency_key="pending-cleanup-58",
                action="delete_object",
                provider="supabase",
                object_key="58/old/recording.webm",
                size_bytes=40,
                reason="test_pending_cleanup",
                status="pending",
                details_json={},
            )
        )
        db.commit()
        monkeypatch.setenv("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", "100")
        monkeypatch.setattr("app.services.audio_storage.storage_backend", lambda: "supabase")
        monkeypatch.setattr("app.services.audio_storage._upload_to_supabase", lambda *_args: writes.append("upload"))

        with pytest.raises(HTTPException) as blocked:
            replace_audio_for_session(db, session, b"RIFF....WAVE", "audio/wav", 4.0)

        assert blocked.value.status_code == 413
        assert writes == []
    finally:
        db.close()


def test_account_scoped_upload_budget_blocks_second_outstanding_reservation(monkeypatch):
    db = _test_db()
    try:
        first = _session(db, 59, "trumpet", dt.datetime(2026, 6, 15))
        second = _session(db, 59, "trumpet", dt.datetime(2026, 6, 16))
        monkeypatch.setenv("BRASSTUNE_MAX_PENDING_AUDIO_UPLOADS_PER_USER", "1")
        first_stage = prepare_audio_upload(first, b"RIFF....WAVE", "audio/wav", 4.0)
        reserve_audio_upload(db, first, first_stage)
        second_stage = prepare_audio_upload(second, b"RIFF....WAVE", "audio/wav", 4.0)

        with pytest.raises(HTTPException) as blocked:
            reserve_audio_upload(db, second, second_stage)

        assert blocked.value.status_code == 429
        assert db.query(AudioStorageJob).filter(AudioStorageJob.status == "reserved").count() == 1
    finally:
        db.close()


def test_concurrent_reservations_cannot_overcommit_account_bytes(monkeypatch):
    db = _test_db()
    try:
        first = _session(db, 60, "trumpet", dt.datetime(2026, 6, 15))
        second = _session(db, 60, "trumpet", dt.datetime(2026, 6, 16))
        monkeypatch.setenv("BRASSTUNE_MAX_PENDING_AUDIO_UPLOADS_PER_USER", "10")
        monkeypatch.setenv("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", "20")
        first_stage = prepare_audio_upload(first, b"RIFF....WAVE", "audio/wav", 4.0)
        reserve_audio_upload(db, first, first_stage)
        second_stage = prepare_audio_upload(second, b"RIFF....WAVE", "audio/wav", 4.0)

        with pytest.raises(HTTPException) as blocked:
            reserve_audio_upload(db, second, second_stage)

        assert blocked.value.status_code == 413
        assert db.query(AudioStorageJob).filter(AudioStorageJob.status == "reserved").count() == 1
    finally:
        db.close()


@pytest.mark.skipif(database_backend(DATABASE_URL) != "postgresql", reason="PostgreSQL row-lock regression")
def test_postgres_concurrent_reservations_serialize_account_quota(monkeypatch):
    """Two real transactions cannot both reserve the same account headroom."""
    user_id = 900060
    setup_db = SessionLocal()
    first_holds_account_lock = threading.Event()
    release_first_reservation = threading.Event()
    second_started = threading.Event()
    results = {}
    failures = []
    threads = []
    try:
        setup_db.query(AudioStorageJob).filter(AudioStorageJob.user_id == user_id).delete(synchronize_session=False)
        setup_db.query(PracticeSession).filter(PracticeSession.user_id == user_id).delete(synchronize_session=False)
        setup_db.query(User).filter(User.id == user_id).delete(synchronize_session=False)
        setup_db.add(User(id=user_id, name="Concurrent Audio User", role="student", primary_instrument_id="trumpet"))
        setup_db.flush()
        rows = [
            PracticeSession(
                user_id=user_id,
                instrument_id="trumpet",
                name="Concurrent reservation %s" % index,
                started_at=dt.datetime(2026, 7, 16, 12, index),
                created_at=dt.datetime(2026, 7, 16, 12, index),
                duration_seconds=8,
            )
            for index in (1, 2)
        ]
        setup_db.add_all(rows)
        setup_db.commit()
        session_ids = [row.id for row in rows]

        monkeypatch.setenv("BRASSTUNE_MAX_PENDING_AUDIO_UPLOADS_PER_USER", "10")
        monkeypatch.setenv("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", "20")
        real_pending_bytes = audio_storage_module._pending_audio_storage_bytes

        def pause_first_while_account_is_locked(db, locked_user_id):
            pending_bytes = real_pending_bytes(db, locked_user_id)
            if threading.current_thread().name == "first-audio-reservation":
                first_holds_account_lock.set()
                if not release_first_reservation.wait(timeout=10):
                    raise RuntimeError("Timed out waiting to release first reservation")
            return pending_bytes

        monkeypatch.setattr(audio_storage_module, "_pending_audio_storage_bytes", pause_first_while_account_is_locked)

        def reserve(name, session_id):
            db = SessionLocal()
            try:
                if name == "second":
                    second_started.set()
                row = db.query(PracticeSession).filter(PracticeSession.id == session_id).one()
                stage = prepare_audio_upload(row, b"RIFF....WAVE", "audio/wav", 4.0)
                reserve_audio_upload(db, row, stage)
                results[name] = "reserved"
            except HTTPException as exc:
                results[name] = exc.status_code
            except Exception as exc:  # pragma: no cover - surfaced by the assertion below
                failures.append(exc)
            finally:
                db.close()

        first = threading.Thread(
            target=reserve,
            args=("first", session_ids[0]),
            name="first-audio-reservation",
        )
        second = threading.Thread(
            target=reserve,
            args=("second", session_ids[1]),
            name="second-audio-reservation",
        )
        threads = [first, second]
        first.start()
        assert first_holds_account_lock.wait(timeout=10)
        second.start()
        assert second_started.wait(timeout=10)
        second.join(timeout=0.25)
        assert second.is_alive(), "The second transaction should wait on the account row lock."
        release_first_reservation.set()
        for thread in threads:
            thread.join(timeout=10)
            assert not thread.is_alive()

        assert failures == []
        assert results == {"first": "reserved", "second": 413}
        assert setup_db.query(AudioStorageJob).filter(
            AudioStorageJob.user_id == user_id,
            AudioStorageJob.status == "reserved",
        ).count() == 1
    finally:
        release_first_reservation.set()
        for thread in threads:
            thread.join(timeout=1)
        setup_db.rollback()
        setup_db.query(AudioStorageJob).filter(AudioStorageJob.user_id == user_id).delete(synchronize_session=False)
        setup_db.query(PracticeSession).filter(PracticeSession.user_id == user_id).delete(synchronize_session=False)
        setup_db.query(User).filter(User.id == user_id).delete(synchronize_session=False)
        setup_db.commit()
        setup_db.close()


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
        job = db.query(AccountDeletionJob).one()
        assert job.status == "completed"
        assert job.stage == "completed"
        assert job.user_id is None
        assert job.supabase_user_id is None
        assert job.idempotency_key == "terminal:%s" % job.id
        assert job.counts_json == {}
        tombstone = db.query(DeletedIdentityTombstone).one()
        assert len(tombstone.subject_digest) == 64
        assert "supabase-151" not in tombstone.subject_digest
        assert payload["counts"]["practice_sessions"] == 1
        assert "supabase-151" not in json.dumps(payload)

        with pytest.raises(HTTPException) as exc:
            _sync_supabase_user(
                db,
                {"id": "supabase-151", "email": "recreate@example.com", "user_metadata": {}, "app_metadata": {}},
            )
        assert exc.value.status_code == 410
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
        assert "audio_storage" in response.json()


def test_audio_storage_retry_endpoint_reuses_secure_maintenance_secret(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET", "retry-secret")
    with TestClient(app) as client:
        response = client.post("/api/maintenance/audio-storage/retry")
        assert response.status_code == 403
        response = client.post(
            "/api/maintenance/audio-storage/retry",
            headers={"X-BrassTune-Maintenance-Secret": "retry-secret"},
        )
        assert response.status_code == 200
        assert {"processed", "completed", "still_retryable", "results"}.issubset(response.json())


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
        assert job.user_id is None
        assert job.supabase_user_id is None
        assert job.counts_json == {}
        assert db.query(DeletedIdentityTombstone).count() == 1
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


def test_account_deletion_retry_executor_reports_local_retry_external_failure_as_retryable(monkeypatch):
    db = _test_db()
    try:
        user = User(id=156, username="delete156", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-156")
        job = AccountDeletionJob(
            user_id=user.id,
            supabase_user_id=user.supabase_user_id,
            idempotency_key="delete-user-156",
            stage="local_cleanup_failed",
            status="retryable_failure",
            next_retry_at=dt.datetime.utcnow() - dt.timedelta(minutes=1),
            counts_json="{}",
        )
        db.add_all([user, job])
        db.commit()
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda _user_id: False)

        result = retry_account_deletion_jobs(db)

        assert result["processed"] == 1
        assert result["completed"] == 0
        assert result["still_retryable"] == 1
        assert result["results"] == [
            {
                "job_id": job.id,
                "status": "retryable_failure",
                "stage": "external_cleanup_failed",
                "deletion_status": "external_cleanup_queued",
            }
        ]
        db.refresh(job)
        assert job.status == "retryable_failure"
        assert job.stage == "external_cleanup_failed"
    finally:
        db.close()


def test_deleted_identity_key_rotation_fails_closed(monkeypatch):
    db = _test_db()
    try:
        user = User(id=259, username="delete259", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-259")
        db.add(user)
        db.commit()
        monkeypatch.setattr("app.api.routes.supabase_global_sign_out", lambda _token: True)
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda _user_id: True)
        delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=False, access_token="access-token"),
        )
        monkeypatch.setenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", "different-production-tombstone-key-32-bytes")
        with pytest.raises(HTTPException) as exc:
            _sync_supabase_user(
                db,
                {"id": "supabase-259", "email": "recreate@example.com", "user_metadata": {}, "app_metadata": {}},
            )
        assert exc.value.status_code == 503
        assert db.query(User).filter(User.supabase_user_id == "supabase-259").first() is None
    finally:
        db.close()


def test_deletion_key_mismatch_is_rejected_before_local_or_external_cleanup(monkeypatch):
    db = _test_db()
    external_calls = []
    try:
        user = User(id=262, username="delete262", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-262")
        db.add(user)
        db.commit()
        monkeypatch.setenv("BRASSTUNE_DELETION_TOMBSTONE_SECRET", "different-production-tombstone-key-32-bytes")
        monkeypatch.setattr("app.api.routes.supabase_global_sign_out", lambda token: external_calls.append(("signout", token)))
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda subject: external_calls.append(("delete", subject)))

        with pytest.raises(HTTPException) as exc:
            delete_my_account(
                AccountDeletionRequest(confirmation="delete my account"),
                db,
                AuthContext(user=user, is_guest=False, access_token="access-token"),
            )

        assert exc.value.status_code == 503
        assert external_calls == []
        assert db.query(User).filter(User.id == user.id).one()
        assert db.query(AccountDeletionJob).count() == 0
    finally:
        db.close()


def test_terminal_account_deletion_jobs_are_purged_but_hmac_tombstones_remain(monkeypatch):
    db = _test_db()
    try:
        user = User(id=260, username="delete260", name="Delete Me", role="student", primary_instrument_id="trumpet", supabase_user_id="supabase-260")
        db.add(user)
        db.commit()
        monkeypatch.setattr("app.api.routes.supabase_global_sign_out", lambda _token: True)
        monkeypatch.setattr("app.api.routes.delete_supabase_identity", lambda _user_id: True)
        delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=False, access_token="access-token"),
        )
        job = db.query(AccountDeletionJob).one()
        job.completed_at = dt.datetime.utcnow() - dt.timedelta(days=8)
        db.commit()

        monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_JOB_RETENTION_DAYS", "7")
        result = account_deletion_module.purge_terminal_account_deletion_jobs(db)
        assert result == {"retention_days": 7, "purged": 1, "failed": False}
        assert db.query(AccountDeletionJob).count() == 0
        assert db.query(DeletedIdentityTombstone).count() == 1
        with pytest.raises(HTTPException) as exc:
            _sync_supabase_user(
                db,
                {"id": "supabase-260", "email": "recreate@example.com", "user_metadata": {}, "app_metadata": {}},
            )
        assert exc.value.status_code == 410

        monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_JOB_RETENTION_DAYS", "999")
        assert account_deletion_module._terminal_job_retention_days() == 30
        monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_JOB_RETENTION_DAYS", "0")
        assert account_deletion_module._terminal_job_retention_days() == 7
    finally:
        db.close()


def test_legacy_completed_deletion_job_is_hmac_backfilled_and_scrubbed_by_maintenance():
    db = _test_db()
    try:
        job = AccountDeletionJob(
            user_id=261,
            supabase_user_id="legacy-supabase-261",
            idempotency_key="delete-user-261",
            stage="completed",
            status="completed",
            retry_count=2,
            safe_error_category="legacy-detail",
            counts_json={"practice_sessions": 4, "usage_events": 9},
            completed_at=dt.datetime.utcnow(),
        )
        db.add(job)
        db.commit()

        result = account_deletion_module.maintain_terminal_account_deletion_jobs(db)

        assert result["scrubbed"] == 1
        assert result["failed"] == 0
        db.refresh(job)
        assert job.user_id is None
        assert job.supabase_user_id is None
        assert job.idempotency_key == "terminal:%s" % job.id
        assert job.counts_json == {}
        assert job.safe_error_category is None
        tombstone = db.query(DeletedIdentityTombstone).one()
        assert "legacy-supabase-261" not in tombstone.subject_digest
    finally:
        db.close()


@pytest.mark.skipif(database_backend(DATABASE_URL) != "postgresql", reason="PostgreSQL migration compatibility regression")
def test_postgres_expand_new_writer_scrubs_and_tombstones_terminal_job():
    """The privacy-aware writer finishes safely while the database is in expand."""
    db = SessionLocal()
    job_id = None
    subject = "expand-new-writer-subject-%s" % os.getpid()
    digest = account_deletion_module.deleted_identity_digest(subject)
    try:
        db.query(DeletedIdentityTombstone).filter(DeletedIdentityTombstone.subject_digest == digest).delete(
            synchronize_session=False
        )
        job = AccountDeletionJob(
            user_id=990261,
            supabase_user_id=subject,
            idempotency_key="expand-new-writer-job-%s" % os.getpid(),
            stage="external_cleanup_started",
            status="in_progress",
            counts_json={"practice_sessions": 2},
        )
        db.add(job)
        db.commit()
        job_id = job.id

        account_deletion_module.complete_and_scrub_account_deletion_job(db, job)
        db.commit()
        db.refresh(job)

        assert account_deletion_module.terminal_job_is_scrubbed(job)
        assert db.query(DeletedIdentityTombstone).filter(
            DeletedIdentityTombstone.subject_digest == digest
        ).one()
    finally:
        db.rollback()
        if job_id is not None:
            db.query(AccountDeletionJob).filter(AccountDeletionJob.id == job_id).delete(synchronize_session=False)
        db.query(DeletedIdentityTombstone).filter(DeletedIdentityTombstone.subject_digest == digest).delete(
            synchronize_session=False
        )
        db.commit()
        db.close()


@pytest.mark.skipif(database_backend(DATABASE_URL) != "postgresql", reason="PostgreSQL migration compatibility regression")
def test_postgres_expand_allows_old_writer_before_strict_contract():
    """Replay the expand migration and the b84dacc completion shape."""
    schema = "account_deletion_expand_%s" % os.getpid()
    migrations_dir = Path(__file__).resolve().parents[3] / "supabase" / "migrations"
    expand_sql = (migrations_dir / "20260723021828_account_deletion_privacy_tombstones.sql").read_text()
    expand_sql = expand_sql.replace("public.", "%s." % schema)

    raw_connection = engine.raw_connection()
    driver_connection = raw_connection.driver_connection
    original_autocommit = driver_connection.autocommit
    driver_connection.autocommit = True
    try:
        with driver_connection.cursor() as cursor:
            cursor.execute("drop schema if exists %s cascade" % schema)
            cursor.execute("create schema %s" % schema)
            cursor.execute(
                "create table %s.account_deletion_jobs ("
                "id bigserial primary key, user_id bigint not null, supabase_user_id text, "
                "idempotency_key text not null unique, stage text not null, status text not null, "
                "retry_count integer not null default 0, next_retry_at timestamptz, "
                "safe_error_category text, counts_json jsonb not null default '{}'::jsonb, "
                "completed_at timestamptz, created_at timestamptz not null default now(), "
                "updated_at timestamptz not null default now())" % schema
            )

            cursor.execute(expand_sql)
            cursor.execute(
                "insert into %s.account_deletion_jobs "
                "(user_id, supabase_user_id, idempotency_key, stage, status, counts_json) "
                "values (42, 'legacy-subject-42', 'delete-user-42', 'external_cleanup_started', "
                "'in_progress', '{\"practice_sessions\": 2}'::jsonb) returning id" % schema
            )
            legacy_job_id = cursor.fetchone()[0]

            # This is the b84dacc completion shape. It must succeed after expand.
            cursor.execute(
                "update %s.account_deletion_jobs set stage = 'completed', status = 'completed', "
                "completed_at = now(), next_retry_at = null where id = %%s" % schema,
                (legacy_job_id,),
            )
            cursor.execute(
                "select user_id, supabase_user_id, idempotency_key, counts_json "
                "from %s.account_deletion_jobs where id = %%s" % schema,
                (legacy_job_id,),
            )
            assert cursor.fetchone() == (42, "legacy-subject-42", "delete-user-42", {"practice_sessions": 2})
            cursor.execute(
                "select count(*) from pg_constraint where "
                "conrelid = %s::regclass and conname = 'account_deletion_jobs_terminal_privacy_check'",
                ("%s.account_deletion_jobs" % schema,),
            )
            assert cursor.fetchone()[0] == 0
    finally:
        try:
            with driver_connection.cursor() as cursor:
                cursor.execute("drop schema if exists %s cascade" % schema)
        finally:
            driver_connection.autocommit = original_autocommit
            raw_connection.close()


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


def test_account_deletion_cleanup_scrubs_surviving_audio_job_identifiers(monkeypatch):
    db = _test_db()
    deleted_objects = []
    try:
        user = User(id=621, username="delete621", name="Delete Audio Job", role="student", primary_instrument_id="trumpet")
        db.add(user)
        db.flush()
        job = AudioStorageJob(
            user_id=user.id,
            session_id=999,
            idempotency_key="account-delete-audio-621",
            action="delete_object",
            provider="supabase",
            object_key="621/999/recording.webm",
            size_bytes=123,
            reason="account_deletion_cleanup",
            status="pending",
            details_json={"former_session": 999},
        )
        db.add(job)
        db.commit()
        job_id = job.id

        payload = delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=True, access_token=None),
        )
        assert payload["deleted"] is True
        monkeypatch.setattr(
            "app.services.audio_storage._delete_audio_object",
            lambda provider, object_key: deleted_objects.append((provider, object_key)),
        )
        result = retry_audio_storage_jobs(db)

        assert result["completed"] == 1
        assert deleted_objects == [("supabase", "621/999/recording.webm")]
        terminal = db.query(AudioStorageJob).filter(AudioStorageJob.id == job_id).one()
        assert terminal.user_id is None
        assert terminal.session_id is None
        assert terminal.idempotency_key == "terminal:%s" % job_id
        assert terminal.object_key == "[redacted]"
        assert terminal.size_bytes == 0
        assert terminal.details_json == {}
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


def test_audio_storage_jobs_migration_is_private_idempotent_and_indexed():
    migration = (
        Path(__file__).resolve().parents[3]
        / "supabase"
        / "migrations"
        / "20260716201825_audio_storage_jobs_and_upload_reservations.sql"
    ).read_text().lower()
    assert "create table if not exists public.audio_storage_jobs" in migration
    assert "idempotency_key text not null unique" in migration
    assert "details_json jsonb" in migration
    assert "enable row level security" in migration
    assert "revoke all privileges on table public.audio_storage_jobs" in migration
    assert "revoke all privileges on sequence public.audio_storage_jobs_id_seq" in migration
    assert "('anon', 'authenticated', 'service_role')" in migration
    assert "audio_storage_jobs_terminal_privacy_check" in migration
    assert "idempotency_key = 'terminal:' || id::text" in migration
    assert "object_key = '[redacted]'" in migration
    assert "details_json = '{}'::jsonb" in migration
    assert "idx_audio_storage_jobs_account_state" in migration
    assert "idx_audio_storage_jobs_retry_queue" in migration
    assert "idx_audio_storage_jobs_terminal_purge" in migration
    assert "where status in ('reserved', 'pending', 'in_progress', 'retryable_failure')" in migration
    assert "default 7-day ttl" in migration
    assert "rollback notes" in migration


def test_account_deletion_privacy_expand_migration_is_private_and_old_writer_compatible():
    expand_migration = (
        Path(__file__).resolve().parents[3]
        / "supabase"
        / "migrations"
        / "20260723021828_account_deletion_privacy_tombstones.sql"
    ).read_text().lower()
    assert "create table if not exists public.deleted_identity_tombstones" in expand_migration
    assert "create table if not exists public.deleted_identity_tombstone_config" in expand_migration
    assert "subject_digest text not null unique" in expand_migration
    assert "account_deletion_jobs alter column user_id drop not null" in expand_migration
    assert "enforcement_phase text not null default 'expand'" in expand_migration
    assert "do not add the terminal privacy check here" in expand_migration
    assert "add constraint account_deletion_jobs_terminal_privacy_check" not in expand_migration
    assert "enable row level security" in expand_migration
    assert "('anon', 'authenticated', 'service_role')" in expand_migration
    assert "revoke all privileges on table public.deleted_identity_tombstones" in expand_migration
    assert "idx_account_deletion_jobs_retry_queue" in expand_migration
    assert "idx_account_deletion_jobs_terminal_purge" in expand_migration
    assert "default 7-day ttl bounded to 30 days" in expand_migration
    assert "b84dacc" in expand_migration


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
