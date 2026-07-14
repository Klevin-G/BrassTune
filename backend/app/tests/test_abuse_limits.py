import os
from collections import defaultdict
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import FastAPI, HTTPException, Request
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.websockets import WebSocketDisconnect


os.environ.setdefault("APP_ENV", "local")
os.environ.setdefault("BRASSTUNE_AUTH_MODE", "disabled")
os.environ.setdefault("CORS_ALLOWED_ORIGINS", "http://localhost:5173")

from app import main as main_module  # noqa: E402
from app.api import websocket as websocket_module  # noqa: E402
from app.api.routes import _positive_int_config as export_positive_int_config  # noqa: E402
from app.models.db import Base, PracticeSession, User  # noqa: E402
from app.services.audio_storage import _positive_int_env as audio_positive_int_env, enforce_audio_storage_quota  # noqa: E402
from app.services.session_service import _positive_int_env as session_positive_int_env, start_session  # noqa: E402


REPO_ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture(autouse=True)
def reset_abuse_state(monkeypatch):
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "disabled")
    monkeypatch.setenv("BRASSTUNE_GLOBAL_RATE_LIMIT_PER_MINUTE", "100")
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_PER_MINUTE", "100")
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_MAX_BUCKETS", "100")
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_MAX_CLIENTS", "100")
    monkeypatch.setenv("BRASSTUNE_CLASS_JOIN_RATE_LIMIT_PER_MINUTE", "10")
    monkeypatch.setenv("BRASSTUNE_EXPENSIVE_MUTATION_RATE_LIMIT_PER_MINUTE", "60")
    monkeypatch.setenv("BRASSTUNE_EXPENSIVE_READ_RATE_LIMIT_PER_MINUTE", "10")
    monkeypatch.delenv("BRASSTUNE_TRUST_PROXY", raising=False)
    main_module._RATE_LIMIT_BUCKETS.clear()
    main_module._GLOBAL_RATE_LIMIT_BUCKETS.clear()
    main_module._EXPENSIVE_RATE_LIMIT_BUCKETS.clear()
    websocket_module._reset_abuse_state_for_tests()
    yield
    main_module._RATE_LIMIT_BUCKETS.clear()
    main_module._GLOBAL_RATE_LIMIT_BUCKETS.clear()
    main_module._EXPENSIVE_RATE_LIMIT_BUCKETS.clear()
    websocket_module._reset_abuse_state_for_tests()


@pytest.fixture
def quota_db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    try:
        yield db
    finally:
        db.close()
        engine.dispose()


def _http_limit_app() -> FastAPI:
    app = FastAPI()
    app.middleware("http")(main_module.request_abuse_limits)

    @app.api_route("/{path:path}", methods=["GET", "POST", "PATCH", "DELETE"])
    async def ok(path: str):
        return {"path": path}

    return app


def test_rate_limit_canonicalizes_numeric_and_uuid_segments():
    assert main_module._canonical_rate_limit_path("/api/sessions/123/audio") == "/api/sessions/{id}/audio"
    assert (
        main_module._canonical_rate_limit_path("/api/items/123e4567-e89b-12d3-a456-426614174000")
        == "/api/items/{uuid}"
    )


def test_route_limit_cannot_be_bypassed_by_rotating_numeric_ids(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_PER_MINUTE", "1")
    with TestClient(_http_limit_app()) as client:
        first = client.get("/api/sessions/100")
        rotated = client.get("/api/sessions/101")
    assert first.status_code == 200
    assert rotated.status_code == 429


def test_global_limit_is_independent_of_route_family(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_GLOBAL_RATE_LIMIT_PER_MINUTE", "2")
    with TestClient(_http_limit_app()) as client:
        assert client.get("/api/one").status_code == 200
        assert client.get("/api/two").status_code == 200
        assert client.get("/api/three").status_code == 429


def test_route_bucket_cardinality_evicts_instead_of_globally_denying(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_RATE_LIMIT_MAX_BUCKETS", "2")
    with TestClient(_http_limit_app()) as client:
        assert client.get("/random-a").status_code == 200
        assert client.get("/random-b").status_code == 200
        assert client.get("/unrelated-legitimate-route").status_code == 200
    assert len(main_module._RATE_LIMIT_BUCKETS) <= 2


def test_class_join_has_a_stricter_dedicated_budget(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_CLASS_JOIN_RATE_LIMIT_PER_MINUTE", "1")
    with TestClient(_http_limit_app()) as client:
        assert client.post("/api/ensemble/join").status_code == 200
        response = client.post("/api/ensemble/join")
    assert response.status_code == 429
    assert "this operation" in response.json()["detail"].lower()


def test_expensive_mutation_budget_spans_rotated_resource_ids(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_EXPENSIVE_MUTATION_RATE_LIMIT_PER_MINUTE", "1")
    with TestClient(_http_limit_app()) as client:
        first = client.post("/api/ensemble/groups/100/members/by-username")
        rotated = client.post("/api/ensemble/groups/101/members/by-username")
    assert first.status_code == 200
    assert rotated.status_code == 429


def _request_with_forwarded_for(value: str, socket_host: str = "192.0.2.10") -> Request:
    return Request({
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "https",
        "path": "/",
        "raw_path": b"/",
        "query_string": b"",
        "headers": [(b"x-forwarded-for", value.encode("latin1"))],
        "client": (socket_host, 1234),
        "server": ("testserver", 443),
    })


def _websocket_with_forwarded_for(value: str, socket_host: str = "192.0.2.10"):
    return SimpleNamespace(
        headers={"x-forwarded-for": value},
        client=SimpleNamespace(host=socket_host),
    )


def test_trusted_proxy_uses_render_first_forwarded_entry(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_TRUST_PROXY", "1")
    value = "198.51.100.99, 203.0.113.7"
    assert main_module._request_client_host(_request_with_forwarded_for(value)) == "198.51.100.99"
    assert websocket_module._websocket_client_host(_websocket_with_forwarded_for(value)) == "198.51.100.99"


@pytest.mark.parametrize("value", ["not-an-ip, 198.51.100.99", "198.51.100.99:1234, 203.0.113.7", "x" * 1025])
def test_trusted_proxy_malformed_first_entry_falls_back_without_scanning(monkeypatch, value):
    monkeypatch.setenv("BRASSTUNE_TRUST_PROXY", "1")
    assert main_module._request_client_host(_request_with_forwarded_for(value)) == "192.0.2.10"
    assert websocket_module._websocket_client_host(_websocket_with_forwarded_for(value)) == "192.0.2.10"


def test_trusted_proxy_normalizes_first_ipv6_entry(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_TRUST_PROXY", "1")
    value = "2001:0db8:0:0:0:0:0:1, 203.0.113.7"
    assert main_module._request_client_host(_request_with_forwarded_for(value)) == "2001:db8::1"
    assert websocket_module._websocket_client_host(_websocket_with_forwarded_for(value)) == "2001:db8::1"


def test_render_disables_uvicorn_proxy_rewriting_and_bounds_connections():
    render_config = (REPO_ROOT / "render.yaml").read_text(encoding="utf-8")
    start_command = next(line for line in render_config.splitlines() if "startCommand:" in line)

    assert "--no-proxy-headers" in start_command
    assert "--forwarded-allow-ips" not in start_command
    assert "--ws-max-size 262144" in start_command
    assert "--ws-max-queue 16" in start_command
    assert "--limit-concurrency 100" in start_command
    assert "--backlog 128" in start_command
    assert 'key: BRASSTUNE_TRUST_PROXY' in render_config
    assert 'BRASSTUNE_TRUSTED_PROXY_HOPS' not in render_config


@pytest.mark.parametrize(
    ("helper", "name", "default"),
    [
        (main_module._positive_int_env, "BRASSTUNE_GLOBAL_RATE_LIMIT_PER_MINUTE", 1800),
        (websocket_module._positive_int_env, "BRASSTUNE_WS_MAX_CONNECTIONS_PER_IP", 8),
        (audio_positive_int_env, "BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", 500 * 1024 * 1024),
        (session_positive_int_env, "BRASSTUNE_MAX_SESSIONS_PER_USER", 5000),
    ],
)
def test_negative_and_invalid_safety_limits_fall_back(monkeypatch, helper, name, default):
    monkeypatch.setenv(name, "-1")
    assert helper(name, default) == default
    monkeypatch.setenv(name, "not-an-integer")
    assert helper(name, default) == default


@pytest.mark.parametrize(
    ("helper", "name", "default"),
    [
        (main_module._positive_int_env, "BRASSTUNE_GLOBAL_RATE_LIMIT_PER_MINUTE", 1800),
        (websocket_module._positive_int_env, "BRASSTUNE_WS_MAX_CONNECTIONS_PER_IP", 8),
        (audio_positive_int_env, "BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", 500 * 1024 * 1024),
        (session_positive_int_env, "BRASSTUNE_MAX_SESSIONS_PER_USER", 5000),
    ],
)
def test_zero_safety_limits_remain_a_deliberate_disable(monkeypatch, helper, name, default):
    monkeypatch.setenv(name, "0")
    assert helper(name, default) == 0


@pytest.mark.parametrize("value", ["0", "-1", "not-an-integer"])
def test_export_limits_cannot_be_disabled_by_unsafe_config(monkeypatch, value):
    monkeypatch.setenv("BRASSTUNE_EXPORT_MAX_TOTAL_ROWS", value)
    assert export_positive_int_config("BRASSTUNE_EXPORT_MAX_TOTAL_ROWS", 250_000) == 250_000


class _FakeDB:
    def close(self):
        return None

    def rollback(self):
        return None


class _FakeDetectedFrame:
    def to_dict(self):
        return {"written_note_name": "C", "cents_deviation": 0.0}


class _FakeDetector:
    def estimate_frame(self, *_args):
        return _FakeDetectedFrame()


def _websocket_limit_app(monkeypatch) -> FastAPI:
    monkeypatch.setattr(websocket_module, "SessionLocal", _FakeDB)
    monkeypatch.setattr(websocket_module, "local_auth_enabled", lambda: True)
    monkeypatch.setattr(
        websocket_module,
        "auth_context_from_token",
        lambda _db, _token: SimpleNamespace(user=SimpleNamespace(id=42, role="student")),
    )
    monkeypatch.setattr(websocket_module, "PitchDetector", _FakeDetector)
    app = FastAPI()
    app.include_router(websocket_module.router)
    return app


def test_websocket_ip_connection_cap_and_release(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_WS_MAX_CONNECTIONS_PER_IP", "1")
    monkeypatch.setenv("BRASSTUNE_WS_MAX_CONNECTIONS_PER_ACCOUNT", "10")
    app = _websocket_limit_app(monkeypatch)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as first:
            first.send_json({"type": "ping"})
            assert first.receive_json()["type"] == "pong"
            with client.websocket_connect("/ws/pitch") as second:
                assert "too many" in second.receive_json()["message"].lower()
                with pytest.raises(WebSocketDisconnect) as closed:
                    second.receive_json()
                assert closed.value.code == 1013
        with client.websocket_connect("/ws/pitch") as after_release:
            after_release.send_json({"type": "ping"})
            assert after_release.receive_json()["type"] == "pong"


def test_websocket_account_connection_cap(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_WS_MAX_CONNECTIONS_PER_IP", "10")
    monkeypatch.setenv("BRASSTUNE_WS_MAX_CONNECTIONS_PER_ACCOUNT", "1")
    app = _websocket_limit_app(monkeypatch)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch"):
            with client.websocket_connect("/ws/pitch") as second:
                assert "account" in second.receive_json()["message"].lower()
                with pytest.raises(WebSocketDisconnect) as closed:
                    second.receive_json()
                assert closed.value.code == 1013


def test_websocket_audio_frame_burst_is_closed(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_WS_MAX_AUDIO_FRAMES_PER_SECOND", "1")
    monkeypatch.setenv("BRASSTUNE_WS_MAX_PCM_SAMPLES_PER_SECOND", "100")
    app = _websocket_limit_app(monkeypatch)
    frame = {"type": "audio_frame", "instrument_id": "trumpet", "sample_rate": 48_000, "pcm": [0.0]}
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json(frame)
            assert websocket.receive_json()["type"] == "pitch_frame"
            websocket.send_json(frame)
            assert "rate limit" in websocket.receive_json()["message"].lower()
            with pytest.raises(WebSocketDisconnect) as closed:
                websocket.receive_json()
            assert closed.value.code == 1008


def test_websocket_non_object_json_is_rejected_without_crashing(monkeypatch):
    app = _websocket_limit_app(monkeypatch)
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_text("[]")
            assert "json objects" in websocket.receive_json()["message"].lower()
            websocket.send_json({"type": "ping"})
            assert websocket.receive_json()["type"] == "pong"


def test_session_quota_is_enforced_at_shared_creation_boundary(monkeypatch, quota_db):
    monkeypatch.setenv("BRASSTUNE_MAX_SESSIONS_PER_USER", "1")
    quota_db.add(User(id=701, username="quota701", name="Quota User", primary_instrument_id="trumpet"))
    quota_db.commit()

    created = start_session(quota_db, "trumpet", "First", 440.0, user_id=701)
    assert created.user_id == 701
    with pytest.raises(HTTPException) as blocked:
        start_session(quota_db, "trumpet", "Second", 440.0, user_id=701)
    assert blocked.value.status_code == 409
    assert quota_db.query(PracticeSession).filter(PracticeSession.user_id == 701).count() == 1


def test_websocket_reports_shared_session_quota_without_disconnect(monkeypatch):
    app = _websocket_limit_app(monkeypatch)
    monkeypatch.setattr(
        websocket_module,
        "start_session",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            HTTPException(status_code=409, detail="Session storage limit reached.")
        ),
    )
    with TestClient(app) as client:
        with client.websocket_connect("/ws/pitch") as websocket:
            websocket.send_json({"type": "start_session", "instrument_id": "trumpet"})
            assert "storage limit" in websocket.receive_json()["message"].lower()
            websocket.send_json({"type": "ping"})
            assert websocket.receive_json()["type"] == "pong"


def test_audio_quota_subtracts_current_recording_on_replacement(monkeypatch, quota_db):
    monkeypatch.setenv("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", "350")
    quota_db.add(User(id=702, username="audio702", name="Audio User", primary_instrument_id="trumpet"))
    current = PracticeSession(
        user_id=702,
        instrument_id="trumpet",
        name="Current",
        audio_size_bytes=100,
    )
    other = PracticeSession(
        user_id=702,
        instrument_id="trumpet",
        name="Other",
        audio_size_bytes=200,
    )
    quota_db.add_all([current, other])
    quota_db.commit()
    quota_db.refresh(current)

    enforce_audio_storage_quota(quota_db, current, 150)
    with pytest.raises(HTTPException) as blocked:
        enforce_audio_storage_quota(quota_db, current, 151)
    assert blocked.value.status_code == 413


def test_websocket_compute_and_pending_session_bounds(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_WS_MAX_CONCURRENT_PITCH_COMPUTATIONS", "1")
    assert websocket_module._try_acquire_pitch_compute_slot() is True
    assert websocket_module._try_acquire_pitch_compute_slot() is False
    websocket_module._release_pitch_compute_slot()
    assert websocket_module._try_acquire_pitch_compute_slot() is True
    websocket_module._release_pitch_compute_slot()

    monkeypatch.setenv("BRASSTUNE_WS_MAX_PENDING_SESSIONS_PER_CONNECTION", "1")
    pending = defaultdict(list, {1: []})
    assert websocket_module._can_track_pending_session(pending, 1) is True
    assert websocket_module._can_track_pending_session(pending, 2) is False
