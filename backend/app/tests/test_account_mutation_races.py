import datetime as dt
import threading

import pytest
from fastapi import HTTPException

import app.services.account_mutation as account_mutation_module
import app.services.session_service as session_service_module
from app.api.auth import AuthContext
from app.api.routes import delete_my_account
from app.db.database import Base, SessionLocal, engine
from app.models.db import AccountDeletionJob, PracticeSession, User
from app.schemas.schemas import AccountDeletionRequest
from app.services.audio_storage import replace_audio_for_session
from app.services.session_service import start_session

WAV_AUDIO_BYTES = (
    b"RIFF\x26\x00\x00\x00WAVE"
    b"fmt \x10\x00\x00\x00\x01\x00\x01\x00\x40\x1f\x00\x00\x40\x1f\x00\x00\x01\x00\x08\x00"
    b"data\x01\x00\x00\x00\x80\x00"
)


def _create_account_with_session(user_id: int) -> int:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        user = User(
            id=user_id,
            username="race%s" % user_id,
            name="Race Account",
            role="student",
            primary_instrument_id="trumpet",
        )
        session = PracticeSession(
            user_id=user_id,
            instrument_id="trumpet",
            name="Deletion race",
            reference_pitch_hz=440,
            started_at=dt.datetime.utcnow(),
        )
        db.add_all([user, session])
        db.commit()
        return int(session.id)
    finally:
        db.close()


def test_postgres_account_mutation_guard_never_checks_out_a_second_connection():
    class Bind:
        dialect = type("Dialect", (), {"name": "postgresql"})()

        def connect(self):
            raise AssertionError("guard must not consume another pooled connection")

    class DB:
        def get_bind(self):
            return Bind()

    with pytest.raises(RuntimeError, match="worker failed"):
        with account_mutation_module.account_mutation_guard(DB(), 42):
            raise RuntimeError("worker failed")

    assert account_mutation_module._PROCESS_LOCKS == {}


def _run_blocked_deletion(
    user_id: int,
    results: dict,
    finished: threading.Event | None = None,
) -> None:
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).one()
        results["deletion"] = delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=True, access_token=None),
        )
    except Exception as exc:  # test captures the worker result explicitly
        results["deletion_error"] = exc
    finally:
        db.close()
        if finished is not None:
            finished.set()


def test_account_deletion_serializes_concurrent_session_creation(
    monkeypatch,
):
    user_id = 920_001
    _create_account_with_session(user_id)
    cleanup_entered = threading.Event()
    release_cleanup = threading.Event()
    creation_finished = threading.Event()
    results = {}

    def blocked_cleanup(_session):
        cleanup_entered.set()
        assert release_cleanup.wait(timeout=5)

    def create_concurrently():
        db = SessionLocal()
        try:
            results["creation"] = start_session(
                db,
                "trumpet",
                "Racing create",
                440,
                user_id=user_id,
            )
        except Exception as exc:
            results["creation_error"] = exc
        finally:
            db.close()
            creation_finished.set()

    monkeypatch.setattr("app.api.routes.delete_audio_for_session", blocked_cleanup)
    deletion = threading.Thread(
        target=_run_blocked_deletion,
        args=(user_id, results),
    )
    creation = threading.Thread(target=create_concurrently)
    deletion.start()
    assert cleanup_entered.wait(timeout=5)
    creation.start()
    assert creation_finished.wait(timeout=0.2) is False
    release_cleanup.set()
    deletion.join(timeout=5)
    creation.join(timeout=5)

    assert not deletion.is_alive()
    assert not creation.is_alive()
    assert "deletion_error" not in results
    assert results["deletion"]["deleted"] is True
    assert isinstance(results.get("creation_error"), HTTPException)
    assert results["creation_error"].status_code == 404
    db = SessionLocal()
    try:
        assert db.query(User).filter(User.id == user_id).first() is None
        assert db.query(PracticeSession).filter(PracticeSession.user_id == user_id).count() == 0
    finally:
        db.close()


def test_account_deletion_serializes_concurrent_audio_upload(
    monkeypatch,
):
    user_id = 920_002
    session_id = _create_account_with_session(user_id)
    cleanup_entered = threading.Event()
    release_cleanup = threading.Event()
    upload_finished = threading.Event()
    results = {}
    storage_writes = []

    def blocked_cleanup(_session):
        cleanup_entered.set()
        assert release_cleanup.wait(timeout=5)

    def upload_concurrently():
        db = SessionLocal()
        try:
            session = db.query(PracticeSession).filter(PracticeSession.id == session_id).one()
            results["upload"] = replace_audio_for_session(
                db,
                session,
                WAV_AUDIO_BYTES,
                "audio/wav",
                1.0,
            )
        except Exception as exc:
            results["upload_error"] = exc
        finally:
            db.close()
            upload_finished.set()

    monkeypatch.setattr("app.api.routes.delete_audio_for_session", blocked_cleanup)
    monkeypatch.setattr(
        "app.services.audio_storage._write_audio_object",
        lambda *_args: storage_writes.append(True),
    )
    deletion = threading.Thread(
        target=_run_blocked_deletion,
        args=(user_id, results),
    )
    upload = threading.Thread(target=upload_concurrently)
    deletion.start()
    assert cleanup_entered.wait(timeout=5)
    upload.start()
    assert upload_finished.wait(timeout=0.2) is False
    release_cleanup.set()
    deletion.join(timeout=5)
    upload.join(timeout=5)

    assert not deletion.is_alive()
    assert not upload.is_alive()
    assert "deletion_error" not in results
    assert results["deletion"]["deleted"] is True
    assert isinstance(results.get("upload_error"), HTTPException)
    assert results["upload_error"].status_code == 404
    assert storage_writes == []


def test_session_creation_that_wins_race_is_included_in_account_deletion(
    monkeypatch,
):
    user_id = 920_003
    _create_account_with_session(user_id)
    creation_entered = threading.Event()
    release_creation = threading.Event()
    deletion_finished = threading.Event()
    results = {}
    original_require_instrument_profile = session_service_module.require_instrument_profile

    def blocked_require_instrument_profile(instrument_id):
        creation_entered.set()
        assert release_creation.wait(timeout=5)
        return original_require_instrument_profile(instrument_id)

    def create_first():
        db = SessionLocal()
        try:
            results["creation"] = start_session(
                db,
                "trumpet",
                "Creation wins",
                440,
                user_id=user_id,
            )
        except Exception as exc:
            results["creation_error"] = exc
        finally:
            db.close()

    monkeypatch.setattr(
        "app.services.session_service.require_instrument_profile",
        blocked_require_instrument_profile,
    )
    creation = threading.Thread(target=create_first)
    deletion = threading.Thread(
        target=_run_blocked_deletion,
        args=(user_id, results, deletion_finished),
    )
    creation.start()
    assert creation_entered.wait(timeout=5)
    deletion.start()
    assert deletion_finished.wait(timeout=0.2) is False
    release_creation.set()
    creation.join(timeout=5)
    deletion.join(timeout=5)

    assert not creation.is_alive()
    assert not deletion.is_alive()
    assert "creation_error" not in results
    assert "deletion_error" not in results
    assert results["deletion"]["deleted"] is True
    assert results["deletion"]["counts"]["practice_sessions"] == 2
    db = SessionLocal()
    try:
        assert db.query(User).filter(User.id == user_id).first() is None
        assert db.query(PracticeSession).filter(PracticeSession.user_id == user_id).count() == 0
    finally:
        db.close()


def test_audio_activation_that_wins_race_is_included_in_account_deletion(
    monkeypatch,
):
    user_id = 920_004
    session_id = _create_account_with_session(user_id)
    upload_entered = threading.Event()
    release_upload = threading.Event()
    deletion_finished = threading.Event()
    results = {}
    cleaned_audio = []
    uploaded_objects = []

    def blocked_write(provider, object_key, _data, _mime_type):
        uploaded_objects.append((provider, object_key))
        upload_entered.set()
        assert release_upload.wait(timeout=5)

    def capture_cleanup(session):
        cleaned_audio.append(
            (
                session.audio_storage_provider,
                session.audio_object_key,
                session.audio_size_bytes,
            )
        )

    def upload_first():
        db = SessionLocal()
        try:
            session = db.query(PracticeSession).filter(PracticeSession.id == session_id).one()
            results["upload"] = replace_audio_for_session(
                db,
                session,
                WAV_AUDIO_BYTES,
                "audio/wav",
                1.0,
            )
        except Exception as exc:
            results["upload_error"] = exc
        finally:
            db.close()

    monkeypatch.setattr("app.services.audio_storage._write_audio_object", blocked_write)
    monkeypatch.setattr("app.api.routes.delete_audio_for_session", capture_cleanup)
    upload = threading.Thread(target=upload_first)
    deletion = threading.Thread(
        target=_run_blocked_deletion,
        args=(user_id, results, deletion_finished),
    )
    upload.start()
    assert upload_entered.wait(timeout=5)
    deletion.start()
    assert deletion_finished.wait(timeout=0.2) is False
    release_upload.set()
    upload.join(timeout=5)
    deletion.join(timeout=5)

    assert not upload.is_alive()
    assert not deletion.is_alive()
    assert "upload_error" not in results
    assert "deletion_error" not in results
    assert results["upload"].audio_snapshot["audio_size_bytes"] == len(WAV_AUDIO_BYTES)
    assert results["deletion"]["deleted"] is True
    assert cleaned_audio == [
        (
            uploaded_objects[0][0],
            uploaded_objects[0][1],
            len(WAV_AUDIO_BYTES),
        )
    ]
    db = SessionLocal()
    try:
        assert db.query(User).filter(User.id == user_id).first() is None
        assert db.query(PracticeSession).filter(PracticeSession.user_id == user_id).count() == 0
    finally:
        db.close()


def test_account_mutations_are_rejected_after_durable_deletion_marker(
    monkeypatch,
):
    user_id = 920_005
    session_id = _create_account_with_session(user_id)
    storage_writes = []
    db = SessionLocal()
    try:
        db.add(
            AccountDeletionJob(
                user_id=user_id,
                idempotency_key="delete-user-%s" % user_id,
                stage="local_cleanup_started",
                status="in_progress",
                counts_json={},
            )
        )
        db.commit()

        with pytest.raises(HTTPException) as create_error:
            start_session(
                db,
                "trumpet",
                "Too late",
                440,
                user_id=user_id,
            )
        assert create_error.value.status_code == 423

        session = db.query(PracticeSession).filter(PracticeSession.id == session_id).one()
        monkeypatch.setattr(
            "app.services.audio_storage._write_audio_object",
            lambda *_args: storage_writes.append(True),
        )
        with pytest.raises(HTTPException) as upload_error:
            replace_audio_for_session(
                db,
                session,
                WAV_AUDIO_BYTES,
                "audio/wav",
                1.0,
            )
        assert upload_error.value.status_code == 423

        assert storage_writes == []
        assert db.query(PracticeSession).filter(PracticeSession.user_id == user_id).count() == 1
        db.refresh(session)
        assert session.audio_object_key is None
    finally:
        db.query(AccountDeletionJob).filter(AccountDeletionJob.user_id == user_id).delete()
        db.query(PracticeSession).filter(PracticeSession.user_id == user_id).delete()
        db.query(User).filter(User.id == user_id).delete()
        db.commit()
        db.close()
