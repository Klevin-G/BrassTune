import io
import datetime as dt
import json
import threading
import zipfile

import pytest
from fastapi import HTTPException
from PIL import Image
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

import app.api.routes as routes
import app.services.audio_storage as audio_storage
import app.services.profile_avatar as profile_avatar
from app.api.auth import AuthContext
from app.db.database import Base, DATABASE_URL, SessionLocal, database_backend, engine as application_engine
from app.models.db import AudioStorageJob, User
from app.schemas.schemas import AccountDeletionRequest, UserProfileUpdate
from app.services.profile_avatar import normalize_avatar, remove_avatar, replace_avatar
from app.services.serializers import user_to_dict


def _image_bytes(format_name="PNG", size=(64, 48), exif=None):
    output = io.BytesIO()
    image = Image.new("RGB", size, (18, 84, 126))
    image.save(output, format=format_name, exif=exif or b"")
    return output.getvalue()


def _avatar_db(user_id=21, object_key=None):
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    user = User(
        id=user_id,
        username="player-%s" % user_id,
        name="Player %s" % user_id,
        display_name="Player %s" % user_id,
        primary_instrument_id="trumpet",
        avatar_object_key=object_key,
        avatar_mime_type="image/jpeg" if object_key else None,
        avatar_size_bytes=3 if object_key else None,
    )
    db.add(user)
    db.commit()
    return db, user


def test_avatar_reencoding_strips_exif_and_normalizes_to_jpeg():
    exif = Image.Exif()
    exif[0x010E] = "private profile metadata"
    normalized, mime_type = normalize_avatar(_image_bytes("JPEG", exif=exif), "image/jpeg")
    assert mime_type == "image/jpeg"
    with Image.open(io.BytesIO(normalized)) as result:
        assert result.format == "JPEG"
        assert result.getexif().get(0x010E) is None
        assert result.width <= 1024 and result.height <= 1024


@pytest.mark.parametrize(
    ("data", "mime", "status"),
    [(b"not an image", "image/jpeg", 415), (_image_bytes("PNG"), "image/jpeg", 415), (_image_bytes("PNG"), "image/gif", 415)],
)
def test_avatar_rejects_invalid_or_mismatched_media(data, mime, status):
    with pytest.raises(HTTPException) as failure:
        normalize_avatar(data, mime)
    assert failure.value.status_code == status


class _CommitRaceDB:
    def __init__(self):
        self.rolled_back = False

    class _Query:
        def filter(self, *_args): return self
        def first(self): return None

    def query(self, _model): return self._Query()
    def add(self, _value): pass
    def commit(self): raise IntegrityError("UPDATE users SET username=?", ("private-value",), Exception("unique"))
    def rollback(self): self.rolled_back = True


class _SuccessDB(_CommitRaceDB):
    def __init__(self):
        self.rolled_back = False

    def commit(self): pass
    def refresh(self, _value): pass


def test_profile_username_commit_race_is_sanitized_409():
    db = _CommitRaceDB()
    user = User(id=8, supabase_user_id="subject-8", username="before", name="Before", primary_instrument_id="trumpet")
    with pytest.raises(HTTPException) as failure:
        routes.update_user_profile(UserProfileUpdate(username="after-name"), db=db, auth=AuthContext(user=user))
    assert failure.value.status_code == 409
    assert failure.value.detail == "Username is already taken."
    assert failure.value.__cause__ is None
    assert db.rolled_back


def test_profile_rejects_blank_display_name_before_persisting():
    db = _CommitRaceDB()
    user = User(id=9, supabase_user_id="subject-9", username="player-nine", name="Before", primary_instrument_id="trumpet")
    with pytest.raises(HTTPException) as failure:
        routes.update_user_profile(UserProfileUpdate(display_name="   "), db=db, auth=AuthContext(user=user))
    assert failure.value.status_code == 422
    assert failure.value.detail == "Display name cannot be blank."
    assert user.name == "Before"


def test_profile_accepts_display_name_at_80_character_boundary_without_truncation():
    db = _SuccessDB()
    user = User(id=9, supabase_user_id="subject-9", username="player-nine", name="Before", primary_instrument_id="trumpet")
    display_name = "x" * 80

    routes.update_user_profile(UserProfileUpdate(display_name=display_name), db=db, auth=AuthContext(user=user))

    assert user.display_name == display_name
    assert user.name == display_name


@pytest.mark.parametrize(
    ("submitted", "normalized"),
    [
        (("e\u0301" * 80), ("é" * 80)),
        (("😀" * 80), ("😀" * 80)),
    ],
)
def test_profile_normalizes_unicode_before_accepting_80_code_point_boundary(submitted, normalized):
    db = _SuccessDB()
    user = User(id=91, supabase_user_id="subject-91", username="player-91", name="Before", primary_instrument_id="trumpet")

    payload = UserProfileUpdate(display_name="  %s  " % submitted)
    routes.update_user_profile(payload, db=db, auth=AuthContext(user=user))

    assert payload.display_name == normalized
    assert user.display_name == normalized
    assert user.name == normalized


@pytest.mark.parametrize("display_name", ["x" * 81, "e\u0301" * 81, "😀" * 81])
def test_profile_rejects_display_name_over_80_normalized_code_points(display_name):
    with pytest.raises(ValidationError) as failure:
        UserProfileUpdate(display_name=display_name)

    assert failure.value.errors()[0]["loc"] == ("display_name",)
    assert failure.value.errors()[0]["type"] == "string_too_long"


def test_provider_seeded_identity_is_not_profile_complete_until_authenticated_confirmation():
    user = User(
        id=10,
        supabase_user_id="subject-10",
        username="provider-seeded",
        name="Provider Name",
        display_name="Provider Name",
        primary_instrument_id="trumpet",
    )
    assert user_to_dict(user)["profile_complete"] is False

    result = routes.update_user_profile(
        UserProfileUpdate(username="confirmed-player", display_name="Confirmed Player"),
        db=_SuccessDB(),
        auth=AuthContext(user=user, is_guest=False),
    )

    assert user.profile_setup_completed_at is not None
    assert result["profile_complete"] is True


def test_guest_profile_patch_cannot_mark_profile_setup_complete():
    user = User(id=11, username="guest-player", name="Guest", display_name="Guest", primary_instrument_id="trumpet")
    routes.update_user_profile(
        UserProfileUpdate(username="guest-player", display_name="Guest Player"),
        db=_SuccessDB(),
        auth=AuthContext(user=user, is_guest=True),
    )
    assert user.profile_setup_completed_at is None


def test_avatar_timestamp_is_canonical_utc_for_swift_iso8601_decoder_contract():
    naive = User(id=12, name="Naive", primary_instrument_id="trumpet", avatar_updated_at=dt.datetime(2026, 8, 23, 14, 5, 6, 987654))
    aware = User(
        id=13,
        name="Aware",
        primary_instrument_id="trumpet",
        avatar_updated_at=dt.datetime(2026, 8, 23, 9, 5, 6, tzinfo=dt.timezone(dt.timedelta(hours=-5))),
    )

    assert user_to_dict(naive)["avatar_updated_at"] == "2026-08-23T14:05:06Z"
    assert user_to_dict(aware)["avatar_updated_at"] == "2026-08-23T14:05:06Z"
    assert user_to_dict(User(id=14, name="None", primary_instrument_id="trumpet"))["avatar_updated_at"] is None


def test_avatar_replacement_delete_failure_is_durable_and_retry_is_idempotent(monkeypatch):
    db, _user = _avatar_db(object_key="21/old.jpg")
    deleted = []
    try:
        monkeypatch.setattr(profile_avatar, "new_avatar_object_key", lambda _user_id: "21/new.jpg")
        monkeypatch.setattr(profile_avatar, "upload_avatar", lambda *_args: None)

        def initially_unavailable(object_key):
            deleted.append(object_key)
            if object_key == "21/old.jpg":
                raise HTTPException(status_code=502, detail="temporarily unavailable")

        monkeypatch.setattr(profile_avatar, "delete_avatar", initially_unavailable)
        active = replace_avatar(db, 21, b"new", "image/jpeg")

        assert active.avatar_object_key == "21/new.jpg"
        cleanup = db.query(AudioStorageJob).filter(AudioStorageJob.object_key == "21/old.jpg").one()
        assert cleanup.provider == profile_avatar.AVATAR_STORAGE_PROVIDER
        assert cleanup.status == "retryable_failure"
        assert "21/old.jpg" not in cleanup.idempotency_key

        cleanup.next_retry_at = dt.datetime.utcnow() - dt.timedelta(seconds=1)
        db.add(cleanup)
        db.commit()
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda object_key: deleted.append(object_key))
        first = audio_storage.retry_audio_storage_jobs(db)
        second = audio_storage.retry_audio_storage_jobs(db)

        assert first["completed"] == 1
        assert second["processed"] == 0
        assert deleted.count("21/old.jpg") == 2
        terminal = db.query(AudioStorageJob).filter(AudioStorageJob.id == cleanup.id).one()
        assert terminal.user_id is None
        assert terminal.object_key == "[redacted]"
    finally:
        db.close()


def test_duplicate_avatar_cleanup_queue_preserves_existing_retry_state():
    db, user = _avatar_db(user_id=211)
    try:
        first_id = profile_avatar.queue_avatar_cleanup(db, user.id, "211/old.jpg", "replaced")
        db.commit()
        job = db.query(AudioStorageJob).filter(AudioStorageJob.id == first_id).one()
        retry_at = dt.datetime.utcnow() + dt.timedelta(minutes=30)
        job.status = "retryable_failure"
        job.retry_count = 4
        job.next_retry_at = retry_at
        job.safe_error_category = "private_object_cleanup_failed"
        db.add(job)
        db.commit()

        second_id = profile_avatar.queue_avatar_cleanup(db, user.id, "211/old.jpg", "removed")
        db.commit()

        refreshed = db.query(AudioStorageJob).filter(AudioStorageJob.id == first_id).one()
        assert second_id == first_id
        assert refreshed.status == "retryable_failure"
        assert refreshed.retry_count == 4
        assert refreshed.next_retry_at == retry_at
        assert refreshed.safe_error_category == "private_object_cleanup_failed"
        assert refreshed.reason == "avatar_replaced"
    finally:
        db.close()


def test_failed_avatar_activation_deletes_staged_object_and_keeps_old_reference(monkeypatch):
    db, _user = _avatar_db(user_id=22, object_key="22/old.jpg")
    deleted = []
    real_commit = db.commit
    commits = 0

    def fail_activation_commit():
        nonlocal commits
        commits += 1
        if commits == 2:
            raise RuntimeError("simulated activation commit failure")
        return real_commit()

    try:
        monkeypatch.setattr(profile_avatar, "new_avatar_object_key", lambda _user_id: "22/new.jpg")
        monkeypatch.setattr(profile_avatar, "upload_avatar", lambda *_args: None)
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: deleted.append(key))
        monkeypatch.setattr(db, "commit", fail_activation_commit)

        with pytest.raises(HTTPException) as failure:
            replace_avatar(db, 22, b"new", "image/jpeg")

        assert failure.value.status_code == 503
        db.expire_all()
        user = db.query(User).filter(User.id == 22).one()
        assert user.avatar_object_key == "22/old.jpg"
        assert deleted == ["22/new.jpg"]
        assert db.query(AudioStorageJob).filter(AudioStorageJob.object_key == "22/old.jpg").count() == 0
    finally:
        db.close()


def test_preupload_reservation_survives_cleanup_bookkeeping_failure_and_maintenance_deletes(monkeypatch):
    db, _user = _avatar_db(user_id=23, object_key="23/old.jpg")
    objects = {"23/new.jpg"}
    real_commit = db.commit
    commits = 0

    def fail_activation_and_conversion_commits():
        nonlocal commits
        commits += 1
        if commits in {2, 3}:
            raise RuntimeError("simulated database outage")
        return real_commit()

    def unavailable_delete(_key):
        raise HTTPException(status_code=502, detail="storage unavailable")

    try:
        monkeypatch.setattr(profile_avatar, "new_avatar_object_key", lambda _user_id: "23/new.jpg")
        monkeypatch.setattr(profile_avatar, "upload_avatar", lambda *_args: None)
        monkeypatch.setattr(profile_avatar, "delete_avatar", unavailable_delete)
        monkeypatch.setattr(db, "commit", fail_activation_and_conversion_commits)

        with pytest.raises(HTTPException) as failure:
            replace_avatar(db, 23, b"new", "image/jpeg")
        assert failure.value.status_code == 503

        monkeypatch.setattr(db, "commit", real_commit)
        reservation = db.query(AudioStorageJob).filter(AudioStorageJob.object_key == "23/new.jpg").one()
        assert reservation.action == "avatar_upload_reservation"
        assert reservation.status == "reserved"
        reservation.updated_at = dt.datetime.utcnow() - dt.timedelta(hours=1)
        db.add(reservation)
        db.commit()
        monkeypatch.setenv("BRASSTUNE_AUDIO_RESERVATION_STALE_SECONDS", "1")
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: objects.discard(key))

        result = audio_storage.retry_audio_storage_jobs(db)

        assert result["completed"] == 1
        assert objects == set()
        assert db.query(User).filter(User.id == 23).one().avatar_object_key == "23/old.jpg"
    finally:
        db.close()


def test_ambiguous_avatar_commit_never_deletes_possibly_active_object_and_later_reconciles(monkeypatch):
    db, _user = _avatar_db(user_id=231, object_key="231/old.jpg")
    deleted = []
    real_commit = db.commit
    commits = 0

    def commit_then_lose_ack():
        nonlocal commits
        commits += 1
        result = real_commit()
        if commits == 2:
            raise RuntimeError("simulated lost commit acknowledgement")
        return result

    try:
        monkeypatch.setattr(profile_avatar, "new_avatar_object_key", lambda _user_id: "231/new.jpg")
        monkeypatch.setattr(profile_avatar, "upload_avatar", lambda *_args: None)
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: deleted.append(key))
        monkeypatch.setattr(profile_avatar, "_avatar_activation_state", lambda *_args: (None, None))
        monkeypatch.setattr(db, "commit", commit_then_lose_ack)

        with pytest.raises(HTTPException) as pending:
            replace_avatar(db, 231, b"new", "image/jpeg")

        assert pending.value.status_code == 503
        assert "confirmation is pending" in pending.value.detail
        assert deleted == []
        monkeypatch.setattr(db, "commit", real_commit)
        db.expire_all()
        user = db.query(User).filter(User.id == 231).one()
        assert user.avatar_object_key == "231/new.jpg"
        reservation = db.query(AudioStorageJob).filter(AudioStorageJob.object_key == "231/new.jpg").one()
        assert reservation.action == "avatar_metadata_reconciliation"
        assert reservation.status == "pending"

        result = audio_storage.retry_audio_storage_jobs(db)

        assert result["completed"] >= 1
        assert deleted == ["231/old.jpg"]
        assert db.query(User).filter(User.id == 231).one().avatar_object_key == "231/new.jpg"
    finally:
        db.close()


def test_failed_avatar_removal_delete_leaves_retry_tombstone(monkeypatch):
    db, _user = _avatar_db(user_id=24, object_key="24/current.jpg")
    deleted = []
    try:
        monkeypatch.setattr(
            profile_avatar,
            "delete_avatar",
            lambda _key: (_ for _ in ()).throw(HTTPException(status_code=502, detail="unavailable")),
        )
        remove_avatar(db, 24)

        db.expire_all()
        user = db.query(User).filter(User.id == 24).one()
        assert user.avatar_object_key is None
        cleanup = db.query(AudioStorageJob).filter(AudioStorageJob.object_key == "24/current.jpg").one()
        assert cleanup.status == "retryable_failure"

        cleanup.next_retry_at = dt.datetime.utcnow() - dt.timedelta(seconds=1)
        db.add(cleanup)
        db.commit()
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: deleted.append(key))
        assert audio_storage.retry_audio_storage_jobs(db)["completed"] == 1
        assert deleted == ["24/current.jpg"]
    finally:
        db.close()


def test_concurrent_avatar_puts_leave_only_the_final_referenced_object(monkeypatch, tmp_path):
    engine = create_engine(
        "sqlite:///%s" % (tmp_path / "avatar-concurrency.db"),
        connect_args={"check_same_thread": False, "timeout": 30},
    )
    Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    setup = sessions()
    setup.add(User(id=25, username="player-25", name="Player 25", primary_instrument_id="trumpet", avatar_object_key="25/original.jpg", avatar_mime_type="image/jpeg", avatar_size_bytes=3))
    setup.commit()
    setup.close()
    objects = {"25/original.jpg"}
    object_lock = threading.Lock()
    start = threading.Barrier(3)
    failures = []

    def key_for_thread(_user_id):
        return "25/%s.jpg" % threading.current_thread().name

    def upload(key, _data, _mime):
        with object_lock:
            objects.add(key)

    def delete(key):
        with object_lock:
            objects.discard(key)

    monkeypatch.setattr(profile_avatar, "new_avatar_object_key", key_for_thread)
    monkeypatch.setattr(profile_avatar, "upload_avatar", upload)
    monkeypatch.setattr(profile_avatar, "delete_avatar", delete)

    def worker():
        db = sessions()
        try:
            start.wait(timeout=5)
            replace_avatar(db, 25, b"new", "image/jpeg")
        except Exception as exc:  # pragma: no cover - surfaced below
            failures.append(exc)
        finally:
            db.close()

    threads = [threading.Thread(target=worker, name=name) for name in ("first", "second")]
    for thread in threads:
        thread.start()
    start.wait(timeout=5)
    for thread in threads:
        thread.join(timeout=10)
        assert not thread.is_alive()

    verify = sessions()
    try:
        active_key = verify.query(User).filter(User.id == 25).one().avatar_object_key
        assert failures == []
        assert active_key in {"25/first.jpg", "25/second.jpg"}
        assert objects == {active_key}
        assert verify.query(AudioStorageJob).filter(AudioStorageJob.status.in_(("reserved", "pending", "in_progress", "retryable_failure"))).count() == 0
    finally:
        verify.close()
        engine.dispose()


@pytest.mark.skipif(database_backend(DATABASE_URL) != "postgresql", reason="PostgreSQL avatar row-lock regression")
def test_postgres_concurrent_avatar_replacements_form_complete_cleanup_chain(monkeypatch):
    Base.metadata.create_all(application_engine)
    user_id = 900025
    setup = SessionLocal()
    setup.query(AudioStorageJob).filter(
        AudioStorageJob.provider == profile_avatar.AVATAR_STORAGE_PROVIDER,
        AudioStorageJob.user_id == user_id,
    ).delete(synchronize_session=False)
    setup.query(User).filter(User.id == user_id).delete(synchronize_session=False)
    setup.add(User(
        id=user_id,
        username="postgres-avatar-900025",
        name="Postgres Avatar",
        primary_instrument_id="trumpet",
        avatar_object_key="900025/original.jpg",
        avatar_mime_type="image/jpeg",
        avatar_size_bytes=3,
    ))
    setup.commit()
    baseline_job_id = setup.query(AudioStorageJob.id).order_by(AudioStorageJob.id.desc()).limit(1).scalar() or 0
    setup.close()

    objects = {"900025/original.jpg"}
    object_lock = threading.Lock()
    uploads_ready = threading.Barrier(2)
    failures = []

    monkeypatch.setattr(
        profile_avatar,
        "new_avatar_object_key",
        lambda _user_id: "900025/%s.jpg" % threading.current_thread().name,
    )

    def upload(key, _data, _mime):
        with object_lock:
            objects.add(key)
        uploads_ready.wait(timeout=10)

    def delete(key):
        with object_lock:
            objects.discard(key)

    monkeypatch.setattr(profile_avatar, "upload_avatar", upload)
    monkeypatch.setattr(profile_avatar, "delete_avatar", delete)

    def worker():
        db = SessionLocal()
        try:
            replace_avatar(db, user_id, b"new", "image/jpeg")
        except Exception as exc:  # pragma: no cover - surfaced below
            failures.append(exc)
        finally:
            db.close()

    threads = [threading.Thread(target=worker, name=name) for name in ("first", "second")]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=20)
        assert not thread.is_alive()

    verify = SessionLocal()
    try:
        active_key = verify.query(User).filter(User.id == user_id).one().avatar_object_key
        assert failures == []
        assert active_key in {"900025/first.jpg", "900025/second.jpg"}
        assert objects == {active_key}
        assert verify.query(AudioStorageJob).filter(
            AudioStorageJob.provider == profile_avatar.AVATAR_STORAGE_PROVIDER,
            AudioStorageJob.user_id == user_id,
            AudioStorageJob.status.in_(("reserved", "pending", "in_progress", "retryable_failure")),
        ).count() == 0
    finally:
        verify.query(AudioStorageJob).filter(
            AudioStorageJob.provider == profile_avatar.AVATAR_STORAGE_PROVIDER,
            AudioStorageJob.id > baseline_job_id,
        ).delete(synchronize_session=False)
        verify.query(User).filter(User.id == user_id).delete(synchronize_session=False)
        verify.commit()
        verify.close()


def test_maintenance_reconciles_active_avatar_reservation_without_deleting_it(monkeypatch):
    db, user = _avatar_db(user_id=26, object_key="26/current.jpg")
    deleted = []
    try:
        job = AudioStorageJob(
            user_id=user.id,
            session_id=None,
            idempotency_key="avatar-active-reservation",
            action="avatar_metadata_reconciliation",
            provider=profile_avatar.AVATAR_STORAGE_PROVIDER,
            object_key="26/current.jpg",
            size_bytes=3,
            reason="avatar_metadata_confirmation",
            status="pending",
            details_json={},
        )
        db.add(job)
        db.commit()
        job_id = job.id
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: deleted.append(key))

        result = audio_storage.retry_audio_storage_jobs(db)

        assert result["completed"] == 1
        assert deleted == []
        terminal = db.query(AudioStorageJob).filter(AudioStorageJob.id == job_id).one()
        assert terminal.object_key == "[redacted]"
    finally:
        db.close()


def test_storage_cleanup_dispatch_uses_provider_not_reason(monkeypatch):
    db, user = _avatar_db(user_id=27)
    audio_deleted = []
    avatar_deleted = []
    try:
        db.add_all([
            AudioStorageJob(
                user_id=user.id,
                idempotency_key="generic-audio-avatar-reason",
                action="delete_object",
                provider="supabase",
                object_key="27/recording.webm",
                size_bytes=3,
                reason="avatar_forged_reason",
                status="pending",
                details_json={},
            ),
            AudioStorageJob(
                user_id=user.id,
                idempotency_key="avatar-generic-reason",
                action="delete_object",
                provider=profile_avatar.AVATAR_STORAGE_PROVIDER,
                object_key="27/photo.jpg",
                size_bytes=3,
                reason="generic_cleanup",
                status="pending",
                details_json={},
            ),
        ])
        db.commit()
        monkeypatch.setattr(audio_storage, "_delete_audio_object", lambda provider, key: audio_deleted.append((provider, key)))
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: avatar_deleted.append(key))

        result = audio_storage.retry_audio_storage_jobs(db)

        assert result["completed"] == 2
        assert audio_deleted == [("supabase", "27/recording.webm")]
        assert avatar_deleted == ["27/photo.jpg"]
    finally:
        db.close()


def test_account_deletion_avatar_tombstone_survives_user_row_and_retries(monkeypatch):
    db, user = _avatar_db(user_id=28, object_key="28/current.jpg")
    try:
        monkeypatch.setattr(
            profile_avatar,
            "delete_avatar",
            lambda _key: (_ for _ in ()).throw(HTTPException(status_code=502, detail="unavailable")),
        )
        payload = routes.delete_my_account(
            AccountDeletionRequest(confirmation="delete my account"),
            db,
            AuthContext(user=user, is_guest=True),
        )

        assert payload["deleted"] is True
        assert db.query(User).filter(User.id == 28).first() is None
        cleanup = db.query(AudioStorageJob).filter(AudioStorageJob.object_key == "28/current.jpg").one()
        assert cleanup.user_id == 28
        assert cleanup.status == "retryable_failure"

        cleanup.next_retry_at = dt.datetime.utcnow() - dt.timedelta(seconds=1)
        db.add(cleanup)
        db.commit()
        deleted = []
        monkeypatch.setattr(profile_avatar, "delete_avatar", lambda key: deleted.append(key))
        assert audio_storage.retry_audio_storage_jobs(db)["completed"] == 1
        assert deleted == ["28/current.jpg"]
        terminal = db.query(AudioStorageJob).filter(AudioStorageJob.id == cleanup.id).one()
        assert terminal.user_id is None
        assert terminal.idempotency_key == "terminal:%s" % cleanup.id
        assert terminal.object_key == "[redacted]"
    finally:
        db.close()


def test_account_export_includes_current_avatar_under_fixed_safe_paths(monkeypatch):
    db, user = _avatar_db(user_id=29, object_key="29/private-random-name.jpg")
    user.avatar_size_bytes = 4
    user.avatar_updated_at = dt.datetime(2026, 8, 23, 12, 0, 0)
    db.add(user)
    db.commit()
    monkeypatch.setattr(routes, "read_avatar", lambda key, size: b"jpeg" if (key, size) == ("29/private-random-name.jpg", 4) else None)
    try:
        response = routes._account_export_zip(db, AuthContext(user=user))
        with zipfile.ZipFile(io.BytesIO(response.body)) as archive:
            names = set(archive.namelist())
            metadata = json.loads(archive.read("profile/avatar.json"))
            avatar = archive.read("profile/avatar.jpg")

        assert "29/private-random-name.jpg" not in names
        assert {"profile/avatar.json", "profile/avatar.jpg"} <= names
        assert all(not name.startswith("/") and ".." not in name.split("/") for name in names)
        assert metadata == {
            "filename": "avatar.jpg",
            "mime_type": "image/jpeg",
            "size_bytes": 4,
            "updated_at": "2026-08-23T12:00:00Z",
        }
        assert avatar == b"jpeg"
    finally:
        db.close()


def test_account_export_without_avatar_has_no_profile_photo_entries(monkeypatch):
    db, user = _avatar_db(user_id=30)
    monkeypatch.setattr(routes, "read_avatar", lambda *_args: pytest.fail("avatar storage should not be read"))
    try:
        response = routes._account_export_zip(db, AuthContext(user=user))
        with zipfile.ZipFile(io.BytesIO(response.body)) as archive:
            names = set(archive.namelist())
        assert "profile/avatar.json" not in names
        assert "profile/avatar.jpg" not in names
    finally:
        db.close()
