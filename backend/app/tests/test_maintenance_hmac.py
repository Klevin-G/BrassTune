import base64
import datetime as dt
import hashlib
import hmac
import logging
import threading
import time
import uuid
from urllib.parse import parse_qsl, quote, urlencode

import pytest
from fastapi.testclient import TestClient

import app.api.routes as routes_module
from app.api.routes import (
    ACCOUNT_DELETION_RETRY_PURPOSE,
    AUDIO_STORAGE_RETRY_PURPOSE,
    MAINTENANCE_HMAC_VERSION,
    MAINTENANCE_RETRY_LIMIT,
    _maintenance_executor_guard,
    _maintenance_signature_payload,
)
from app.db.database import SessionLocal
from app.db.readiness import maintenance_readiness_issues
from app.main import app
from app.models.db import MaintenanceHeartbeat, MaintenanceRequestNonce


CURRENT_KEY_ID = "maintenance-2026-07"
CURRENT_KEY_BYTES = b"C" * 32
CURRENT_KEY_B64 = base64.b64encode(CURRENT_KEY_BYTES).decode("ascii")
PREVIOUS_KEY_ID = "maintenance-2026-06"
PREVIOUS_KEY_BYTES = b"P" * 32
PREVIOUS_KEY_B64 = base64.b64encode(PREVIOUS_KEY_BYTES).decode("ascii")
ACCOUNT_PATH = "/api/maintenance/account-deletions/retry"
AUDIO_PATH = "/api/maintenance/audio-storage/retry"


@pytest.fixture
def maintenance_hmac_env(monkeypatch):
    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_KEY_ID", CURRENT_KEY_ID)
    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_KEY", CURRENT_KEY_B64)
    monkeypatch.delenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY_ID", raising=False)
    monkeypatch.delenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY", raising=False)
    monkeypatch.delenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET", raising=False)


def _canonical_query(query: str) -> str:
    pairs = sorted(parse_qsl(query, keep_blank_values=True), key=lambda pair: (pair[0], pair[1]))
    return urlencode(pairs, doseq=True, quote_via=quote, safe="~")


def _signed_headers(
    *,
    path: str = ACCOUNT_PATH,
    purpose: str = ACCOUNT_DELETION_RETRY_PURPOSE,
    query: str = "",
    body: bytes = b"",
    timestamp: int | None = None,
    nonce: str | None = None,
    key_id: str = CURRENT_KEY_ID,
    key: bytes = CURRENT_KEY_BYTES,
) -> dict[str, str]:
    timestamp_value = str(int(time.time()) if timestamp is None else timestamp)
    nonce_value = nonce or str(uuid.uuid4())
    payload = _maintenance_signature_payload(
        version=MAINTENANCE_HMAC_VERSION,
        method="POST",
        path=path,
        canonical_query=_canonical_query(query),
        body_sha256=hashlib.sha256(body).hexdigest(),
        timestamp=timestamp_value,
        nonce=nonce_value,
        purpose=purpose,
    )
    signature = base64.urlsafe_b64encode(
        hmac.new(key, payload, hashlib.sha256).digest()
    ).rstrip(b"=").decode("ascii")
    return {
        "X-BrassTune-Maintenance-Version": MAINTENANCE_HMAC_VERSION,
        "X-BrassTune-Maintenance-Key-Id": key_id,
        "X-BrassTune-Maintenance-Timestamp": timestamp_value,
        "X-BrassTune-Maintenance-Nonce": nonce_value,
        "X-BrassTune-Maintenance-Purpose": purpose,
        "X-BrassTune-Maintenance-Signature": signature,
    }


def _empty_retry_result() -> dict:
    return {"processed": 0, "completed": 0, "still_retryable": 0, "results": []}


def test_maintenance_hmac_rejects_missing_and_malformed_headers(maintenance_hmac_env):
    malformed_cases = (
        ("X-BrassTune-Maintenance-Version", "v2"),
        ("X-BrassTune-Maintenance-Timestamp", "not-an-epoch"),
        ("X-BrassTune-Maintenance-Nonce", "short"),
        ("X-BrassTune-Maintenance-Signature", "not-a-sha256-signature"),
    )
    with TestClient(app) as client:
        assert client.post(ACCOUNT_PATH).status_code == 403
        for header_name, bad_value in malformed_cases:
            headers = _signed_headers()
            headers[header_name] = bad_value
            response = client.post(ACCOUNT_PATH, headers=headers)
            assert response.status_code == 403
            assert "signature" not in response.text.lower()


@pytest.mark.parametrize("offset_seconds", (-301, 301))
def test_maintenance_hmac_rejects_expired_and_future_requests(
    maintenance_hmac_env,
    offset_seconds,
):
    headers = _signed_headers(timestamp=int(time.time()) + offset_seconds)
    with TestClient(app) as client:
        response = client.post(ACCOUNT_PATH, headers=headers)
    assert response.status_code == 403


def test_maintenance_hmac_binds_path_purpose_key_and_signature(maintenance_hmac_env):
    cases = [
        _signed_headers(path=AUDIO_PATH),
        _signed_headers(purpose="different-maintenance-purpose"),
        _signed_headers(key_id="unknown-key"),
        _signed_headers(key=b"W" * 32),
    ]
    bad_signature = _signed_headers()
    bad_signature["X-BrassTune-Maintenance-Signature"] = (
        "A" if bad_signature["X-BrassTune-Maintenance-Signature"][0] != "A" else "B"
    ) + bad_signature["X-BrassTune-Maintenance-Signature"][1:]
    cases.append(bad_signature)

    with TestClient(app) as client:
        for headers in cases:
            response = client.post(ACCOUNT_PATH, headers=headers)
            assert response.status_code == 403
            assert response.json()["detail"] == "Maintenance request is not authorized."


def test_maintenance_hmac_binds_canonical_query_and_uses_fixed_limit(
    maintenance_hmac_env,
    monkeypatch,
):
    observed_limits = []
    monkeypatch.setattr(
        routes_module,
        "retry_account_deletion_jobs",
        lambda _db, limit: observed_limits.append(limit) or _empty_retry_result(),
    )
    monkeypatch.setattr(
        routes_module,
        "retry_audio_storage_jobs",
        lambda _db, limit: observed_limits.append(limit) or _empty_retry_result(),
    )
    query = "z=last&limit=50&a=hello%20world"
    headers = _signed_headers(query=query)
    with TestClient(app) as client:
        response = client.post(f"{ACCOUNT_PATH}?{query}", headers=headers)
    assert response.status_code == 204
    assert response.content == b""
    assert observed_limits == [MAINTENANCE_RETRY_LIMIT, MAINTENANCE_RETRY_LIMIT]


def test_successful_account_maintenance_records_backend_heartbeat(
    maintenance_hmac_env,
):
    before = dt.datetime.now(dt.timezone.utc)
    with TestClient(app) as client:
        db = SessionLocal()
        try:
            db.query(MaintenanceHeartbeat).filter(
                MaintenanceHeartbeat.purpose == ACCOUNT_DELETION_RETRY_PURPOSE
            ).delete(synchronize_session=False)
            db.commit()
        finally:
            db.close()
        response = client.post(ACCOUNT_PATH, headers=_signed_headers())
    after = dt.datetime.now(dt.timezone.utc)

    assert response.status_code == 204
    db = SessionLocal()
    try:
        heartbeat = db.get(
            MaintenanceHeartbeat,
            ACCOUNT_DELETION_RETRY_PURPOSE,
        )
        assert heartbeat is not None
        succeeded_at = heartbeat.last_succeeded_at
        if succeeded_at.tzinfo is None:
            succeeded_at = succeeded_at.replace(tzinfo=dt.timezone.utc)
        assert before <= succeeded_at <= after
    finally:
        db.close()


def test_failed_account_maintenance_does_not_advance_backend_heartbeat(
    maintenance_hmac_env,
    monkeypatch,
):
    previous_success = dt.datetime(2026, 7, 24, 1, 2, 3)
    with TestClient(app, raise_server_exceptions=False) as client:
        db = SessionLocal()
        try:
            heartbeat = db.get(
                MaintenanceHeartbeat,
                ACCOUNT_DELETION_RETRY_PURPOSE,
            )
            if heartbeat is None:
                heartbeat = MaintenanceHeartbeat(
                    purpose=ACCOUNT_DELETION_RETRY_PURPOSE,
                    last_succeeded_at=previous_success,
                )
            else:
                heartbeat.last_succeeded_at = previous_success
            db.add(heartbeat)
            db.commit()
        finally:
            db.close()

        monkeypatch.setattr(
            routes_module,
            "retry_account_deletion_jobs",
            lambda *_args, **_kwargs: (_ for _ in ()).throw(
                RuntimeError("maintenance failed")
            ),
        )
        response = client.post(ACCOUNT_PATH, headers=_signed_headers())

    assert response.status_code == 500
    db = SessionLocal()
    try:
        heartbeat = db.get(
            MaintenanceHeartbeat,
            ACCOUNT_DELETION_RETRY_PURPOSE,
        )
        assert heartbeat is not None
        assert heartbeat.last_succeeded_at == previous_success
    finally:
        db.close()


def test_maintenance_hmac_binds_actual_body_and_invalid_hmac_does_not_reserve_nonce(
    maintenance_hmac_env,
):
    nonce = str(uuid.uuid4())
    signed_body = b'{"operation":"retry"}'
    actual_body = b'{"operation":"different"}'
    headers = _signed_headers(body=signed_body, nonce=nonce)
    nonce_digest = hashlib.sha256(nonce.encode("utf-8")).hexdigest()

    with TestClient(app) as client:
        response = client.post(ACCOUNT_PATH, headers=headers, content=actual_body)
        assert response.status_code == 403
        db = SessionLocal()
        try:
            assert (
                db.query(MaintenanceRequestNonce)
                .filter(MaintenanceRequestNonce.nonce_digest == nonce_digest)
                .count()
                == 0
            )
        finally:
            db.close()

        response = client.post(ACCOUNT_PATH, headers=headers, content=signed_body)
    assert response.status_code == 204


def test_maintenance_hmac_rejects_replay_and_stores_only_nonce_digest(
    maintenance_hmac_env,
):
    nonce = str(uuid.uuid4())
    headers = _signed_headers(nonce=nonce)
    with TestClient(app) as client:
        first = client.post(ACCOUNT_PATH, headers=headers)
        second = client.post(ACCOUNT_PATH, headers=headers)
    assert first.status_code == 204
    assert first.content == b""
    assert second.status_code == 403

    db = SessionLocal()
    try:
        row = (
            db.query(MaintenanceRequestNonce)
            .filter(
                MaintenanceRequestNonce.nonce_digest
                == hashlib.sha256(nonce.encode("utf-8")).hexdigest()
            )
            .one()
        )
        assert row.nonce_digest != nonce
        assert row.key_id == CURRENT_KEY_ID
        assert row.purpose == ACCOUNT_DELETION_RETRY_PURPOSE
        assert not hasattr(row, "nonce")
        assert not hasattr(row, "signature")
    finally:
        db.close()


def test_replay_nonce_survives_the_inclusive_clock_skew_boundary(
    maintenance_hmac_env,
    monkeypatch,
):
    fixed_now = int(time.time())
    monkeypatch.setattr(routes_module.time, "time", lambda: fixed_now)
    nonce = str(uuid.uuid4())
    headers = _signed_headers(
        nonce=nonce,
        timestamp=fixed_now - routes_module.MAINTENANCE_MAX_CLOCK_SKEW_SECONDS,
    )

    with TestClient(app) as client:
        first = client.post(ACCOUNT_PATH, headers=headers)
        replay = client.post(ACCOUNT_PATH, headers=headers)

    assert first.status_code == 204
    assert replay.status_code == 403
    db = SessionLocal()
    try:
        row = (
            db.query(MaintenanceRequestNonce)
            .filter(
                MaintenanceRequestNonce.nonce_digest
                == hashlib.sha256(nonce.encode("utf-8")).hexdigest()
            )
            .one()
        )
        assert row.expires_at > dt.datetime.utcnow() + dt.timedelta(
            seconds=routes_module.MAINTENANCE_MAX_CLOCK_SKEW_SECONDS - 2
        )
    finally:
        db.close()


def test_current_and_previous_hmac_keys_are_accepted_during_rotation(
    maintenance_hmac_env,
    monkeypatch,
):
    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY_ID", PREVIOUS_KEY_ID)
    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY", PREVIOUS_KEY_B64)
    previous_headers = _signed_headers(key_id=PREVIOUS_KEY_ID, key=PREVIOUS_KEY_BYTES)
    current_headers = _signed_headers()

    with TestClient(app) as client:
        previous_response = client.post(ACCOUNT_PATH, headers=previous_headers)
        current_response = client.post(ACCOUNT_PATH, headers=current_headers)
    assert previous_response.status_code == 204
    assert current_response.status_code == 204


def test_deployed_maintenance_rejects_legacy_bearer_and_static_secret(
    maintenance_hmac_env,
    monkeypatch,
):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET", "legacy-secret")
    monkeypatch.setenv("BRASSTUNE_AUTH_MODE", "supabase")
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_PUBLISHABLE_KEY", "test-publishable-key")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "test-secret-key")
    # This endpoint-level check does not need lifespan startup, whose deployed
    # database guard intentionally refuses the isolated SQLite test database.
    client = TestClient(app)
    bearer = client.post(
        ACCOUNT_PATH,
        headers={"Authorization": "Bearer legacy-secret"},
    )
    static = client.post(
        ACCOUNT_PATH,
        headers={"X-BrassTune-Maintenance-Secret": "legacy-secret"},
    )
    assert bearer.status_code == 403
    assert static.status_code == 403


def test_audio_retry_returns_minimal_204_and_sanitized_aggregate_log(
    maintenance_hmac_env,
    monkeypatch,
    caplog,
):
    sensitive_marker = "private-object-key/user-123"
    monkeypatch.setattr(
        routes_module,
        "retry_audio_storage_jobs",
        lambda _db, limit: {
            "processed": 1,
            "completed": 0,
            "still_retryable": 1,
            "results": [{"object_key": sensitive_marker, "signature": "do-not-log"}],
        },
    )
    headers = _signed_headers(
        path=AUDIO_PATH,
        purpose=AUDIO_STORAGE_RETRY_PURPOSE,
    )
    with caplog.at_level(logging.INFO, logger="brasstune.maintenance"):
        with TestClient(app) as client:
            response = client.post(AUDIO_PATH, headers=headers)
    assert response.status_code == 204
    assert response.content == b""
    assert "processed=1" in caplog.text
    assert sensitive_marker not in caplog.text
    assert "do-not-log" not in caplog.text
    assert "signature" not in response.text.lower()


def test_process_executor_guard_rejects_simultaneous_valid_request_before_processing(
    maintenance_hmac_env,
    monkeypatch,
):
    processing_started = threading.Event()
    allow_completion = threading.Event()
    call_count = 0

    def slow_account_retry(_db, limit):
        nonlocal call_count
        call_count += 1
        processing_started.set()
        assert allow_completion.wait(timeout=5)
        return _empty_retry_result()

    monkeypatch.setattr(routes_module, "retry_account_deletion_jobs", slow_account_retry)
    monkeypatch.setattr(
        routes_module,
        "retry_audio_storage_jobs",
        lambda _db, limit: _empty_retry_result(),
    )
    first_result = {}
    with TestClient(app) as first_client, TestClient(app) as second_client:
        def first_request():
            first_result["response"] = first_client.post(
                ACCOUNT_PATH,
                headers=_signed_headers(),
            )

        worker = threading.Thread(target=first_request)
        worker.start()
        assert processing_started.wait(timeout=5)
        second = second_client.post(ACCOUNT_PATH, headers=_signed_headers())
        assert second.status_code == 409
        assert call_count == 1
        allow_completion.set()
        worker.join(timeout=5)
    assert not worker.is_alive()
    assert first_result["response"].status_code == 204
    assert call_count == 1


def test_postgres_executor_guard_uses_one_dedicated_connection_and_unlocks():
    class Result:
        def __init__(self, value):
            self.value = value

        def scalar(self):
            return self.value

    class Connection:
        def __init__(self):
            self.statements = []
            self.closed = False

        def execute(self, statement, values):
            self.statements.append((str(statement), values))
            return Result(True)

        def close(self):
            self.closed = True

    connection = Connection()

    class Bind:
        dialect = type("Dialect", (), {"name": "postgresql"})()

        def connect(self):
            return connection

    class DB:
        def get_bind(self):
            return Bind()

    with pytest.raises(RuntimeError, match="job failed"):
        with _maintenance_executor_guard(DB()):
            raise RuntimeError("job failed")

    assert connection.closed is True
    assert len(connection.statements) == 2
    assert "pg_try_advisory_lock" in connection.statements[0][0]
    assert "pg_advisory_unlock" in connection.statements[1][0]
    assert connection.statements[0][1] == connection.statements[1][1]


def test_deployed_readiness_rejects_short_key_and_accepts_rotation(
    maintenance_hmac_env,
    monkeypatch,
):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv(
        "BRASSTUNE_DELETION_TOMBSTONE_SECRET",
        "production-deletion-tombstone-key-32-bytes",
    )
    monkeypatch.setenv(
        "BRASSTUNE_MAINTENANCE_HMAC_KEY",
        base64.b64encode(b"short").decode("ascii"),
    )
    assert "at least 32 bytes" in " ".join(maintenance_readiness_issues())

    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_KEY", CURRENT_KEY_B64)
    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY_ID", PREVIOUS_KEY_ID)
    monkeypatch.setenv("BRASSTUNE_MAINTENANCE_HMAC_PREVIOUS_KEY", PREVIOUS_KEY_B64)
    assert maintenance_readiness_issues() == []


def test_expired_replay_rows_are_purged_before_reservation(maintenance_hmac_env):
    db = SessionLocal()
    try:
        db.add(
            MaintenanceRequestNonce(
                nonce_digest=hashlib.sha256(b"expired-nonce").hexdigest(),
                key_id=CURRENT_KEY_ID,
                purpose=ACCOUNT_DELETION_RETRY_PURPOSE,
                created_at=dt.datetime.utcnow() - dt.timedelta(hours=1),
                expires_at=dt.datetime.utcnow() - dt.timedelta(minutes=1),
            )
        )
        db.commit()
    finally:
        db.close()

    with TestClient(app) as client:
        response = client.post(ACCOUNT_PATH, headers=_signed_headers())
    assert response.status_code == 204

    db = SessionLocal()
    try:
        assert (
            db.query(MaintenanceRequestNonce)
            .filter(
                MaintenanceRequestNonce.nonce_digest
                == hashlib.sha256(b"expired-nonce").hexdigest()
            )
            .count()
            == 0
        )
    finally:
        db.close()
