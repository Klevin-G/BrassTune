import datetime as dt
import hashlib
import io
import os
import secrets
import urllib.error
import urllib.parse
import urllib.request

from fastapi import HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy.orm import Session

from app.core.security import LOCAL_ENVIRONMENTS, app_environment
from app.models.db import AudioStorageJob, User
from app.services.account_mutation import account_mutation_guard, assert_account_accepts_mutation


AVATAR_BUCKET = "profile-avatars"
AVATAR_STORAGE_PROVIDER = "supabase-avatar"
MAX_UPLOAD_BYTES = 5 * 1024 * 1024
MAX_SOURCE_DIMENSION = 4096
MAX_SOURCE_PIXELS = 16_000_000
OUTPUT_DIMENSION = 1024
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png"}


def normalize_avatar(data: bytes, declared_mime_type: str) -> tuple[bytes, str]:
    """Decode untrusted media and re-encode it without metadata before storage."""
    mime_type = (declared_mime_type or "").split(";", 1)[0].strip().lower()
    if mime_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(status_code=415, detail="Choose a JPEG or PNG profile photo.")
    if not data or len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Profile photo must be 5 MB or smaller.")
    if mime_type == "image/jpeg" and not data.startswith(b"\xff\xd8\xff"):
        raise HTTPException(status_code=415, detail="The profile photo does not match its file type.")
    if mime_type == "image/png" and not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise HTTPException(status_code=415, detail="The profile photo does not match its file type.")
    try:
        with Image.open(io.BytesIO(data)) as source:
            if source.format not in {"JPEG", "PNG"} or getattr(source, "is_animated", False):
                raise HTTPException(status_code=415, detail="Choose a still JPEG or PNG profile photo.")
            width, height = source.size
            if width <= 0 or height <= 0 or width > MAX_SOURCE_DIMENSION or height > MAX_SOURCE_DIMENSION or width * height > MAX_SOURCE_PIXELS:
                raise HTTPException(status_code=413, detail="Profile photo dimensions are too large.")
            source.load()
            oriented = ImageOps.exif_transpose(source)
            converted = oriented.convert("RGB")
            converted.thumbnail((OUTPUT_DIMENSION, OUTPUT_DIMENSION), Image.Resampling.LANCZOS)
            output = io.BytesIO()
            # A fresh image encoding strips EXIF, GPS, ICC, comments, and PNG text chunks.
            converted.save(output, format="JPEG", quality=88, optimize=True)
            return output.getvalue(), "image/jpeg"
    except HTTPException:
        raise
    except (Image.DecompressionBombError, UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(status_code=415, detail="The profile photo could not be decoded safely.") from None


def new_avatar_object_key(user_id: int) -> str:
    return "%s/%s.jpg" % (int(user_id), secrets.token_hex(16))


def replace_avatar(db: Session, user_id: int, data: bytes, mime_type: str) -> User:
    """Durably reserve, upload, and activate one private profile avatar.

    The reservation is committed before remote I/O, so every possible remote
    object has a database-owned cleanup/reconciliation path even when a later
    commit fails. The user row is re-locked immediately before the previous
    key is captured, which makes concurrent replacements form a complete
    cleanup chain instead of losing the earlier writer's object.
    """
    account_id = int(user_id)
    object_key = new_avatar_object_key(account_id)
    with account_mutation_guard(db, account_id):
        reservation_id = _reserve_avatar_upload(
            db,
            account_id,
            object_key,
            len(data),
            mime_type,
        )
        try:
            upload_avatar(object_key, data, mime_type)
        except Exception as upload_error:
            deleted, durable = _settle_unactivated_avatar(
                db,
                reservation_id,
                object_key,
                reason="avatar_upload_failed",
            )
            if not deleted:
                raise HTTPException(
                    status_code=503,
                    detail="Profile photo upload failed and cleanup is queued for retry.",
                ) from upload_error
            if not durable:
                # The original pre-upload reservation is still durable. This
                # response stays conservative because terminal bookkeeping
                # could not be confirmed.
                raise HTTPException(
                    status_code=503,
                    detail="Profile photo upload failed; cleanup reconciliation is pending.",
                ) from upload_error
            if isinstance(upload_error, HTTPException):
                raise upload_error
            raise HTTPException(status_code=502, detail="Profile photo storage is temporarily unavailable.") from upload_error

        try:
            user, cleanup_job_id = _activate_avatar_upload(
                db,
                account_id,
                reservation_id,
                object_key,
                len(data),
                mime_type,
            )
        except Exception as activation_error:
            db.rollback()
            activation_state, committed_user = _avatar_activation_state(
                db,
                account_id,
                object_key,
                len(data),
                mime_type,
            )
            if activation_state is True and committed_user is not None:
                # A commit can succeed even when the connection fails before
                # acknowledgement. Keep the active object and let maintenance
                # reconcile the already-durable reservation.
                return committed_user
            if activation_state is None:
                # Confirmation failed. Deleting here could destroy a newly
                # active avatar after a lost commit acknowledgement. The
                # pre-upload reservation remains durable and maintenance will
                # later reconcile it against the user row.
                raise HTTPException(
                    status_code=503,
                    detail="Profile photo activation confirmation is pending; retry shortly.",
                ) from activation_error
            deleted, durable = _settle_unactivated_avatar(
                db,
                reservation_id,
                object_key,
                reason="avatar_metadata_commit_failed",
            )
            if not deleted:
                raise HTTPException(
                    status_code=503,
                    detail="Profile photo was not activated and cleanup is queued for retry.",
                ) from activation_error
            if not durable:
                raise HTTPException(
                    status_code=503,
                    detail="Profile photo was not activated; cleanup reconciliation is pending.",
                ) from activation_error
            if isinstance(activation_error, HTTPException):
                raise activation_error
            raise HTTPException(
                status_code=503,
                detail="Profile photo could not be saved. The staged upload was removed; retry later.",
            ) from activation_error

        from app.services.audio_storage import complete_storage_job, process_audio_delete_jobs

        # Failure to record the terminal transition is non-destructive: the
        # reservation remains pending and maintenance will prove that this key
        # is active before completing it.
        complete_storage_job(db, reservation_id)
        if cleanup_job_id is not None:
            process_audio_delete_jobs(db, [cleanup_job_id])
        return user


def remove_avatar(db: Session, user_id: int) -> None:
    """Clear avatar metadata and create its cleanup tombstone atomically."""
    account_id = int(user_id)
    with account_mutation_guard(db, account_id):
        try:
            user = _lock_avatar_user(db, account_id)
            object_key = user.avatar_object_key
            cleanup_job_id = (
                queue_avatar_cleanup(db, account_id, object_key, "removed")
                if object_key
                else None
            )
            user.avatar_object_key = None
            user.avatar_mime_type = None
            user.avatar_size_bytes = None
            user.avatar_updated_at = None
            user.updated_at = dt.datetime.utcnow()
            db.add(user)
            db.commit()
        except Exception:
            db.rollback()
            raise

        if cleanup_job_id is not None:
            from app.services.audio_storage import process_audio_delete_jobs

            process_audio_delete_jobs(db, [cleanup_job_id])


def _lock_avatar_user(db: Session, user_id: int) -> User:
    user = (
        db.query(User)
        .filter(User.id == int(user_id))
        .populate_existing()
        .with_for_update()
        .first()
    )
    if user is None:
        raise HTTPException(status_code=404, detail="Account not found.")
    assert_account_accepts_mutation(db, int(user_id))
    return user


def _avatar_job_key(prefix: str, object_key: str) -> str:
    digest = hashlib.sha256((AVATAR_STORAGE_PROVIDER + "\0" + object_key).encode("utf-8")).hexdigest()
    return "%s:%s" % (prefix, digest)


def _reserve_avatar_upload(
    db: Session,
    user_id: int,
    object_key: str,
    size_bytes: int,
    mime_type: str,
) -> int:
    try:
        _lock_avatar_user(db, user_id)
        job = AudioStorageJob(
            user_id=user_id,
            session_id=None,
            idempotency_key=_avatar_job_key("avatar-reservation", object_key),
            action="avatar_upload_reservation",
            provider=AVATAR_STORAGE_PROVIDER,
            object_key=object_key,
            size_bytes=max(0, int(size_bytes)),
            reason="avatar_upload_reserved",
            status="reserved",
            details_json={"mime_type": mime_type},
        )
        db.add(job)
        db.flush()
        job_id = int(job.id)
        db.commit()
        return job_id
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=503, detail="Profile photo upload could not be reserved; retry later.") from exc


def _activate_avatar_upload(
    db: Session,
    user_id: int,
    reservation_id: int,
    object_key: str,
    size_bytes: int,
    mime_type: str,
) -> tuple[User, int | None]:
    user = _lock_avatar_user(db, user_id)
    reservation = (
        db.query(AudioStorageJob)
        .filter(AudioStorageJob.id == int(reservation_id))
        .with_for_update()
        .first()
    )
    if (
        reservation is None
        or reservation.action != "avatar_upload_reservation"
        or reservation.provider != AVATAR_STORAGE_PROVIDER
        or reservation.object_key != object_key
        or reservation.status != "reserved"
    ):
        raise HTTPException(status_code=409, detail="Profile photo upload reservation is no longer active.")

    # Capture the displaced key only after the account row is locked. A second
    # PUT therefore sees this activation and tombstones this object in turn.
    previous_key = user.avatar_object_key
    cleanup_job_id = (
        queue_avatar_cleanup(db, user_id, previous_key, "replaced")
        if previous_key and previous_key != object_key
        else None
    )
    user.avatar_object_key = object_key
    user.avatar_mime_type = mime_type
    user.avatar_size_bytes = int(size_bytes)
    user.avatar_updated_at = dt.datetime.utcnow()
    user.updated_at = dt.datetime.utcnow()
    reservation.action = "avatar_metadata_reconciliation"
    reservation.reason = "avatar_metadata_confirmation"
    reservation.status = "pending"
    reservation.next_retry_at = None
    reservation.safe_error_category = None
    reservation.updated_at = dt.datetime.utcnow()
    db.add_all([user, reservation])
    db.commit()
    db.refresh(user)
    return user, cleanup_job_id


def _avatar_activation_state(
    db: Session,
    user_id: int,
    object_key: str,
    size_bytes: int,
    mime_type: str,
) -> tuple[bool | None, User | None]:
    try:
        user = db.query(User).filter(User.id == int(user_id)).populate_existing().first()
        if (
            user is not None
            and user.avatar_object_key == object_key
            and user.avatar_mime_type == mime_type
            and int(user.avatar_size_bytes or 0) == int(size_bytes)
        ):
            return True, user
        return False, None
    except Exception:
        db.rollback()
        return None, None


def _settle_unactivated_avatar(
    db: Session,
    reservation_id: int,
    object_key: str,
    *,
    reason: str,
) -> tuple[bool, bool]:
    """Return (object_deleted, durable_state_updated).

    The pre-upload reservation remains a valid cleanup record even if every
    bookkeeping attempt below fails.
    """
    from app.services.audio_storage import complete_storage_job

    try:
        delete_avatar(object_key)
    except Exception:
        return False, _convert_avatar_reservation_to_cleanup(db, reservation_id, reason)
    return True, complete_storage_job(db, reservation_id, status="cancelled")


def _convert_avatar_reservation_to_cleanup(db: Session, reservation_id: int, reason: str) -> bool:
    try:
        job = (
            db.query(AudioStorageJob)
            .filter(AudioStorageJob.id == int(reservation_id))
            .with_for_update()
            .first()
        )
        if job is None:
            db.rollback()
            return False
        if job.provider != AVATAR_STORAGE_PROVIDER:
            db.rollback()
            return False
        job.action = "delete_object"
        job.reason = reason
        job.status = "retryable_failure"
        job.retry_count = int(job.retry_count or 0) + 1
        job.safe_error_category = "private_object_cleanup_failed"
        job.next_retry_at = dt.datetime.utcnow() + dt.timedelta(minutes=min(60, 2 ** min(job.retry_count, 6)))
        job.updated_at = dt.datetime.utcnow()
        db.add(job)
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


def reconcile_avatar_storage_job(db: Session, payload: dict) -> bool | None:
    """Return True for an active avatar, False for an inactive key, None on DB failure."""
    try:
        user = None
        if payload.get("user_id") is not None:
            user = (
                db.query(User)
                .filter(User.id == int(payload["user_id"]))
                .populate_existing()
                .with_for_update()
                .first()
            )
        if user is not None and user.avatar_object_key == payload.get("object_key"):
            db.rollback()
            return True
        job = (
            db.query(AudioStorageJob)
            .filter(AudioStorageJob.id == int(payload["id"]))
            .with_for_update()
            .first()
        )
        if job is None or job.provider != AVATAR_STORAGE_PROVIDER:
            db.rollback()
            return None
        job.action = "delete_object"
        job.reason = "avatar_inactive_reservation"
        job.status = "in_progress"
        job.updated_at = dt.datetime.utcnow()
        db.add(job)
        db.commit()
        return False
    except Exception:
        db.rollback()
        return None


def upload_avatar(object_key: str, data: bytes, mime_type: str) -> None:
    request = urllib.request.Request(
        _storage_url(object_key), data=data, method="POST",
        headers={**_storage_headers(), "Content-Type": mime_type, "x-upsert": "false"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20):  # nosec B310
            return
    except (urllib.error.HTTPError, urllib.error.URLError, OSError) as exc:
        raise HTTPException(status_code=502, detail="Profile photo storage is temporarily unavailable.") from exc


def read_avatar(object_key: str, expected_size: int) -> bytes:
    if expected_size <= 0 or expected_size > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=404, detail="Profile photo is unavailable.")
    request = urllib.request.Request(_storage_url(object_key), headers=_storage_headers())
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # nosec B310
            data = response.read(expected_size + 1)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            raise HTTPException(status_code=404, detail="Profile photo is unavailable.") from None
        raise HTTPException(status_code=502, detail="Profile photo storage is temporarily unavailable.") from exc
    except (urllib.error.URLError, OSError) as exc:
        raise HTTPException(status_code=502, detail="Profile photo storage is temporarily unavailable.") from exc
    if len(data) != expected_size:
        raise HTTPException(status_code=502, detail="Profile photo storage returned an invalid response.")
    return data


def delete_avatar(object_key: str | None) -> None:
    if not object_key:
        return
    request = urllib.request.Request(_storage_url(object_key), method="DELETE", headers=_storage_headers())
    try:
        with urllib.request.urlopen(request, timeout=20):  # nosec B310
            return
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return
        raise HTTPException(status_code=502, detail="Profile photo storage is temporarily unavailable.") from exc
    except (urllib.error.URLError, OSError) as exc:
        raise HTTPException(status_code=502, detail="Profile photo storage is temporarily unavailable.") from exc


def queue_avatar_cleanup(db: Session, user_id: int | None, object_key: str, reason: str) -> int:
    """Durably retain an inaccessible avatar key until remote deletion succeeds."""
    key = _avatar_job_key("avatar-cleanup", object_key)
    job = (
        db.query(AudioStorageJob)
        .filter(AudioStorageJob.idempotency_key == key)
        .with_for_update()
        .first()
    )
    if job is None:
        job = AudioStorageJob(
            user_id=user_id,
            session_id=None,
            idempotency_key=key,
            action="delete_object",
            provider=AVATAR_STORAGE_PROVIDER,
            object_key=object_key,
            size_bytes=0,
            reason="avatar_%s" % reason,
            status="pending",
            details_json={},
        )
    else:
        if (
            job.action != "delete_object"
            or job.provider != AVATAR_STORAGE_PROVIDER
            or job.object_key != object_key
        ):
            raise HTTPException(status_code=503, detail="Profile photo cleanup state is unavailable.")
        # Preserve retry/backoff or an in-progress claim. Re-queuing the same
        # immutable object key must not reset maintenance state.
        if user_id is not None:
            job.user_id = user_id
    db.add(job)
    db.flush()
    return int(job.id)


def _storage_headers() -> dict[str, str]:
    key = (os.getenv("SUPABASE_SECRET_KEY") or "").strip()
    if not key:
        raise HTTPException(status_code=503, detail="Profile photo storage is unavailable.")
    return {"apikey": key}


def _storage_url(object_key: str) -> str:
    base = (os.getenv("SUPABASE_URL") or "").strip().rstrip("/")
    parsed = urllib.parse.urlparse(base)
    is_local = app_environment() in LOCAL_ENVIRONMENTS and parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    if (parsed.scheme != "https" and not is_local) or not parsed.netloc or parsed.username or parsed.password or parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise HTTPException(status_code=503, detail="Profile photo storage is unavailable.")
    encoded_key = urllib.parse.quote(object_key, safe="/")
    return "%s/storage/v1/object/%s/%s" % (base, AVATAR_BUCKET, encoded_key)
