import datetime as dt
import hashlib
import json
import math
import os
import secrets
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Optional, Tuple

from fastapi import HTTPException
from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from app.core.security import LOCAL_ENVIRONMENTS, app_environment
from app.db.database import DATA_DIR
from app.models.db import AudioStorageJob, PracticeSession, User
from app.services.serializers import session_to_dict

ALLOWED_AUDIO_MIME_TYPES = {
    "audio/webm": ".webm",
    "audio/mp4": ".m4a",
    "audio/mpeg": ".mp3",
    "audio/wav": ".wav",
    "audio/ogg": ".ogg",
}
MAGIC_BYTES = {
    "audio/webm": (b"\x1a\x45\xdf\xa3",),
    "audio/mp4": (b"ftyp",),
    "audio/mpeg": (b"ID3", b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"),
    "audio/wav": (b"RIFF",),
    "audio/ogg": (b"OggS",),
}
MAX_AUDIO_UPLOAD_BYTES = 50 * 1024 * 1024
MAX_AUDIO_DURATION_SECONDS = 24 * 60 * 60
LOCAL_AUDIO_DIR = DATA_DIR / "audio"
AUDIO_JOB_ACTIVE_STATUSES = ("reserved", "pending", "in_progress", "retryable_failure")
AUDIO_DELETE_ACTIVE_STATUSES = ("pending", "in_progress", "retryable_failure")
AUDIO_JOB_TERMINAL_STATUSES = ("completed", "cancelled")
DEFAULT_AUDIO_JOB_TERMINAL_RETENTION_DAYS = 7
MAX_AUDIO_JOB_TERMINAL_RETENTION_DAYS = 30
MAX_AUDIO_JOB_PURGE_BATCH = 1000


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if value >= 0 else default


def audio_upload_limit_bytes() -> int:
    """A deployment may lower, but never disable or raise, the 50 MiB cap."""
    configured = _positive_int_env("SESSION_AUDIO_MAX_BYTES", MAX_AUDIO_UPLOAD_BYTES)
    if configured <= 0:
        return MAX_AUDIO_UPLOAD_BYTES
    return min(configured, MAX_AUDIO_UPLOAD_BYTES)


def _lock_audio_account_and_session(db: Session, session: PracticeSession) -> PracticeSession:
    # All reservation/metadata writers take locks in account -> session order.
    # Remote storage calls happen outside this window.
    account_exists = db.query(User.id).filter(User.id == session.user_id).with_for_update().first()
    if account_exists is None:
        raise HTTPException(status_code=404, detail="Account not found.")
    current_session = (
        db.query(PracticeSession)
        .filter(PracticeSession.id == session.id, PracticeSession.user_id == session.user_id)
        .populate_existing()
        .with_for_update()
        .first()
    )
    if current_session is None:
        raise HTTPException(status_code=404, detail="Session not found.")
    return current_session


def _pending_audio_storage_bytes(db: Session, user_id: int) -> int:
    return int(
        db.query(func.coalesce(func.sum(AudioStorageJob.size_bytes), 0))
        .filter(AudioStorageJob.user_id == user_id)
        .filter(
            or_(
                and_(
                    AudioStorageJob.action == "upload_reservation",
                    AudioStorageJob.status.in_(("reserved", "in_progress")),
                ),
                and_(
                    AudioStorageJob.action == "delete_object",
                    AudioStorageJob.status.in_(AUDIO_DELETE_ACTIVE_STATUSES),
                ),
            )
        )
        .scalar()
        or 0
    )


def _active_audio_storage_bytes(db: Session, user_id: int) -> int:
    return int(
        db.query(func.coalesce(func.sum(PracticeSession.audio_size_bytes), 0))
        .filter(PracticeSession.user_id == user_id)
        .scalar()
        or 0
    )


def enforce_audio_storage_quota(db: Session, session: PracticeSession, incoming_size: int) -> None:
    """Validate physical storage headroom while holding the account lock.

    Active recordings, outstanding upload reservations, and undeleted cleanup
    tombstones all consume quota. A replacement therefore needs temporary room
    for both the old and staged objects until cleanup completes.
    """
    _lock_audio_account_and_session(db, session)
    max_bytes = _positive_int_env("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", 500 * 1024 * 1024)
    if not max_bytes:
        return
    projected_bytes = (
        _active_audio_storage_bytes(db, session.user_id)
        + _pending_audio_storage_bytes(db, session.user_id)
        + max(0, int(incoming_size))
    )
    if projected_bytes > max_bytes:
        raise HTTPException(
            status_code=413,
            detail="Audio storage limit reached. Delete old cloud recordings before uploading another.",
        )


def storage_backend() -> str:
    return os.getenv("SESSION_AUDIO_STORAGE_BACKEND", "local").strip().lower() or "local"


def _validated_storage_backend() -> str:
    provider = storage_backend()
    if provider not in {"local", "supabase"}:
        raise HTTPException(status_code=503, detail="Unsupported SESSION_AUDIO_STORAGE_BACKEND.")
    return provider


def audio_extension(mime_type: str) -> str:
    if mime_type not in ALLOWED_AUDIO_MIME_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported audio MIME type.")
    return ALLOWED_AUDIO_MIME_TYPES[mime_type]


def read_audio_bytes(data: bytes, mime_type: str) -> Tuple[bytes, str]:
    mime_type = (mime_type or "application/octet-stream").split(";", 1)[0].strip().lower()
    audio_extension(mime_type)
    if not data:
        raise HTTPException(status_code=400, detail="Audio upload was empty.")
    if len(data) > audio_upload_limit_bytes():
        raise HTTPException(status_code=413, detail="Audio upload is too large.")
    signatures = MAGIC_BYTES.get(mime_type, ())
    if mime_type == "audio/mp4":
        if len(data) < 12 or data[4:8] not in signatures:
            raise HTTPException(status_code=400, detail="Audio upload does not match its declared format.")
    elif mime_type == "audio/wav":
        if len(data) < 12 or not data.startswith(b"RIFF") or data[8:12] != b"WAVE":
            raise HTTPException(status_code=400, detail="Audio upload does not match its declared format.")
    elif signatures and not any(data.startswith(signature) for signature in signatures):
        raise HTTPException(status_code=400, detail="Audio upload does not match its declared format.")
    return data, mime_type


def validate_audio_duration_seconds(duration_seconds: Optional[float]) -> Optional[float]:
    if duration_seconds is None:
        return None
    value = float(duration_seconds)
    if not math.isfinite(value) or value < 0 or value > MAX_AUDIO_DURATION_SECONDS:
        raise HTTPException(
            status_code=400,
            detail="Audio duration must be a finite value between 0 and 86400 seconds.",
        )
    return value


def object_key_for(session: PracticeSession, mime_type: str) -> str:
    extension = audio_extension(mime_type)
    return "%s/%s/recording%s" % (session.user_id, session.id, extension)


def staged_object_key_for(session: PracticeSession, mime_type: str) -> str:
    extension = audio_extension(mime_type)
    # Every upload gets its own object. This prevents concurrent first uploads
    # or replacements from overwriting an active/staged object before metadata
    # commits and makes compensating cleanup safe after a failed commit.
    return "%s/%s/versions/%s/recording%s" % (
        session.user_id,
        session.id,
        secrets.token_hex(12),
        extension,
    )


def local_audio_path(object_key: str) -> Path:
    safe_parts = [part for part in object_key.split("/") if part not in {"", ".", ".."}]
    root = LOCAL_AUDIO_DIR.resolve()
    path = root.joinpath(*safe_parts).resolve()
    if not path.is_relative_to(root):
        raise HTTPException(status_code=400, detail="Invalid audio object key.")
    return path


def _supabase_headers(mime_type: Optional[str] = None) -> dict:
    key = os.getenv("SUPABASE_SECRET_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    headers = {"apikey": key, "Authorization": "Bearer %s" % key}
    if mime_type:
        headers["Content-Type"] = mime_type
    return headers


def _supabase_url(path: str) -> str:
    base = (os.getenv("SUPABASE_URL") or "").strip().rstrip("/")
    if not base:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    parsed = urllib.parse.urlparse(base)
    is_local_http = (
        app_environment() in LOCAL_ENVIRONMENTS
        and parsed.scheme == "http"
        and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    )
    if parsed.scheme != "https" and not is_local_http:
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    if (
        not parsed.netloc
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.path not in {"", "/"}
        or parsed.params
        or parsed.query
        or parsed.fragment
    ):
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    return "%s/%s" % (base.rstrip("/"), path.lstrip("/"))


def _supabase_bucket() -> str:
    bucket = (os.getenv("SUPABASE_STORAGE_BUCKET") or "session-audio").strip()
    if not bucket or len(bucket) > 100 or any(char in bucket for char in "/\\?#\x00\r\n"):
        raise HTTPException(status_code=503, detail="Audio storage is unavailable.")
    return urllib.parse.quote(bucket, safe="")


def _upload_to_supabase(object_key: str, data: bytes, mime_type: str) -> None:
    bucket = _supabase_bucket()
    encoded_key = urllib.parse.quote(object_key, safe="/")
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/%s/%s" % (bucket, encoded_key)),
        data=data,
        method="POST",
        headers={**_supabase_headers(mime_type), "x-upsert": "true"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20):  # nosec B310
            return
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase audio upload failed.") from exc


def _read_supabase_object(object_key: str) -> bytes:
    bucket = _supabase_bucket()
    encoded_key = urllib.parse.quote(object_key, safe="/")
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/%s/%s" % (bucket, encoded_key)),
        headers=_supabase_headers(),
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # nosec B310
            return response.read()
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase audio download failed.") from exc


def _delete_supabase_object(object_key: str) -> None:
    bucket = _supabase_bucket()
    encoded_key = urllib.parse.quote(object_key, safe="/")
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/%s/%s" % (bucket, encoded_key)),
        method="DELETE",
        headers=_supabase_headers(),
    )
    try:
        with urllib.request.urlopen(request, timeout=20):  # nosec B310
            return
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return
        raise HTTPException(status_code=502, detail="Supabase audio deletion failed.") from exc


def create_supabase_signed_url(object_key: str, expires_in: int = 900) -> str:
    bucket = _supabase_bucket()
    encoded_key = urllib.parse.quote(object_key, safe="/")
    request = urllib.request.Request(
        _supabase_url("/storage/v1/object/sign/%s/%s" % (bucket, encoded_key)),
        data=json.dumps({"expiresIn": expires_in}).encode("utf-8"),
        method="POST",
        headers={**_supabase_headers("application/json")},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # nosec B310
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Supabase signed URL failed.") from exc
    signed = payload.get("signedURL") or payload.get("signedUrl") or payload.get("signed_url")
    if not isinstance(signed, str) or not signed or len(signed) > 8192 or any(char in signed for char in "\x00\r\n"):
        raise HTTPException(status_code=502, detail="Supabase did not return a signed playback URL.")
    base = _supabase_url("/").rstrip("/")
    resolved = urllib.parse.urljoin(base + "/", str(signed))
    parsed_base = urllib.parse.urlparse(base)
    parsed_signed = urllib.parse.urlparse(resolved)
    if (
        parsed_signed.scheme != parsed_base.scheme
        or parsed_signed.netloc != parsed_base.netloc
        or parsed_signed.username
        or parsed_signed.password
        or parsed_signed.fragment
    ):
        raise HTTPException(status_code=502, detail="Supabase returned an invalid signed playback URL.")
    return resolved


def _write_audio_object(provider: str, object_key: str, data: bytes, mime_type: str) -> None:
    if provider == "supabase":
        _upload_to_supabase(object_key, data, mime_type)
        return
    if provider == "local":
        path = local_audio_path(object_key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return
    raise HTTPException(status_code=503, detail="Unsupported SESSION_AUDIO_STORAGE_BACKEND.")


def _delete_audio_object(provider: Optional[str], object_key: str) -> None:
    if provider == "local":
        path = local_audio_path(object_key)
        if path.exists():
            path.unlink()
        return
    if provider == "supabase":
        _delete_supabase_object(object_key)
        return
    raise HTTPException(status_code=503, detail="Audio storage cleanup is unavailable for this recording.")


@dataclass(frozen=True)
class StagedAudioUpload:
    user_id: int
    session_id: int
    provider: str
    object_key: str
    mime_type: str
    duration_seconds: Optional[float]
    size_bytes: int
    uploaded_at: dt.datetime
    previous_provider: Optional[str]
    previous_object_key: Optional[str]
    previous_size_bytes: int


@dataclass(frozen=True)
class AudioReplaceResult:
    audio_snapshot: dict
    cleanup_pending: bool = False
    reconciliation_pending: bool = False
    activation_pending: bool = False


def prepare_audio_upload(
    session: PracticeSession,
    data: bytes,
    mime_type: str,
    duration_seconds: Optional[float],
) -> StagedAudioUpload:
    # Validate before creating a durable reservation. Otherwise a misspelled
    # provider can produce a job that neither upload nor cleanup can process.
    provider = _validated_storage_backend()
    stage = StagedAudioUpload(
        user_id=session.user_id,
        session_id=session.id,
        provider=provider,
        object_key=staged_object_key_for(session, mime_type),
        mime_type=mime_type,
        duration_seconds=validate_audio_duration_seconds(duration_seconds),
        size_bytes=len(data),
        uploaded_at=dt.datetime.utcnow(),
        previous_provider=session.audio_storage_provider,
        previous_object_key=session.audio_object_key,
        previous_size_bytes=max(0, int(session.audio_size_bytes or 0)),
    )
    return stage


def apply_staged_audio_metadata(session: PracticeSession, stage: StagedAudioUpload) -> PracticeSession:
    session.audio_storage_provider = stage.provider
    session.audio_object_key = stage.object_key
    session.audio_mime_type = stage.mime_type
    session.audio_duration_seconds = stage.duration_seconds
    session.audio_size_bytes = stage.size_bytes
    session.audio_uploaded_at = stage.uploaded_at
    return session


def discard_staged_audio(stage: StagedAudioUpload) -> None:
    if (stage.provider, stage.object_key) == (stage.previous_provider, stage.previous_object_key):
        raise HTTPException(status_code=503, detail="Refusing to delete the active audio object during rollback.")
    _delete_audio_object(stage.provider, stage.object_key)


def cleanup_previous_audio(stage: StagedAudioUpload) -> None:
    if not stage.previous_object_key:
        return
    if (stage.previous_provider, stage.previous_object_key) == (stage.provider, stage.object_key):
        return
    _delete_audio_object(stage.previous_provider, stage.previous_object_key)


def _audio_job_key(prefix: str, provider: str, object_key: str) -> str:
    digest = hashlib.sha256((provider + "\0" + object_key).encode("utf-8")).hexdigest()
    return "%s:%s" % (prefix, digest)


def _audio_job_details(stage: StagedAudioUpload, audio_snapshot: Optional[dict] = None) -> dict:
    details = {
        "mime_type": stage.mime_type,
        "duration_seconds": stage.duration_seconds,
        "uploaded_at": stage.uploaded_at.isoformat(),
    }
    if audio_snapshot is not None:
        details["audio_snapshot"] = audio_snapshot
    return details


def reserve_audio_upload(db: Session, session: PracticeSession, stage: StagedAudioUpload) -> tuple[StagedAudioUpload, int]:
    """Commit an account-scoped byte/concurrency reservation before upload."""
    try:
        current = _lock_audio_account_and_session(db, session)
        stage = replace(
            stage,
            previous_provider=current.audio_storage_provider,
            previous_object_key=current.audio_object_key,
            previous_size_bytes=max(0, int(current.audio_size_bytes or 0)),
        )
        pending_limit = _positive_int_env("BRASSTUNE_MAX_PENDING_AUDIO_UPLOADS_PER_USER", 2)
        pending_uploads = (
            db.query(AudioStorageJob.id)
            .filter(
                AudioStorageJob.user_id == session.user_id,
                AudioStorageJob.action == "upload_reservation",
                AudioStorageJob.status.in_(("reserved", "in_progress")),
            )
            .count()
        )
        if pending_limit and pending_uploads >= pending_limit:
            raise HTTPException(
                status_code=429,
                detail="Another audio upload is already pending for this account. Wait for it to finish.",
            )
        max_bytes = _positive_int_env("BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER", 500 * 1024 * 1024)
        projected_bytes = (
            _active_audio_storage_bytes(db, session.user_id)
            + _pending_audio_storage_bytes(db, session.user_id)
            + stage.size_bytes
        )
        if max_bytes and projected_bytes > max_bytes:
            raise HTTPException(
                status_code=413,
                detail="Audio storage limit reached. Delete old cloud recordings before uploading another.",
            )
        reservation = AudioStorageJob(
            user_id=session.user_id,
            session_id=session.id,
            idempotency_key=_audio_job_key("reservation", stage.provider, stage.object_key),
            action="upload_reservation",
            provider=stage.provider,
            object_key=stage.object_key,
            size_bytes=stage.size_bytes,
            reason="pre_upload_byte_reservation",
            status="reserved",
            details_json=_audio_job_details(stage),
        )
        db.add(reservation)
        db.flush()
        reservation_id = int(reservation.id)
        db.commit()
        return stage, reservation_id
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=503, detail="Audio upload capacity could not be reserved; retry later.") from exc


def _mark_audio_job_completed(db: Session, job_id: int, status: str = "completed") -> bool:
    if status not in AUDIO_JOB_TERMINAL_STATUSES:
        return False
    try:
        job = db.query(AudioStorageJob).filter(AudioStorageJob.id == job_id).with_for_update().first()
        if job is None:
            db.rollback()
            return False
        job.status = status
        job.next_retry_at = None
        job.safe_error_category = None
        job.completed_at = job.completed_at or dt.datetime.utcnow()
        job.updated_at = dt.datetime.utcnow()
        # Operational fields are required only while work is pending. Scrub
        # account/session/object metadata immediately at terminal transition so
        # account deletion never leaves identifiable job history after cleanup.
        job.user_id = None
        job.session_id = None
        job.idempotency_key = "terminal:%s" % job.id
        job.object_key = "[redacted]"
        job.size_bytes = 0
        job.details_json = {}
        db.add(job)
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


def _mark_audio_job_retryable(db: Session, job_id: int, error_category: str) -> bool:
    try:
        job = db.query(AudioStorageJob).filter(AudioStorageJob.id == job_id).with_for_update().first()
        if job is None:
            db.rollback()
            return False
        job.status = "retryable_failure"
        job.retry_count = int(job.retry_count or 0) + 1
        job.safe_error_category = error_category
        job.next_retry_at = dt.datetime.utcnow() + dt.timedelta(minutes=min(60, 2 ** min(job.retry_count, 6)))
        job.updated_at = dt.datetime.utcnow()
        db.add(job)
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


def _convert_reservation_to_cleanup(db: Session, reservation_id: int, reason: str, error_category: str) -> bool:
    try:
        job = db.query(AudioStorageJob).filter(AudioStorageJob.id == reservation_id).with_for_update().first()
        if job is None:
            db.rollback()
            return False
        job.action = "delete_object"
        job.reason = reason
        job.status = "retryable_failure"
        job.retry_count = int(job.retry_count or 0) + 1
        job.safe_error_category = error_category
        job.next_retry_at = dt.datetime.utcnow() + dt.timedelta(minutes=min(60, 2 ** min(job.retry_count, 6)))
        job.updated_at = dt.datetime.utcnow()
        db.add(job)
        db.commit()
        return True
    except Exception:
        db.rollback()
        # The pre-upload reservation remains durable and continues to consume
        # quota. The stale-reservation executor will reconcile it later.
        return False


def _settle_failed_staged_upload(
    db: Session,
    stage: StagedAudioUpload,
    reservation_id: int,
    reason: str,
) -> tuple[bool, bool]:
    """Return (object_deleted, durable_state_updated)."""
    try:
        discard_staged_audio(stage)
    except Exception:
        queued = _convert_reservation_to_cleanup(
            db,
            reservation_id,
            reason,
            "staged_object_cleanup_failed",
        )
        return False, queued
    return True, _mark_audio_job_completed(db, reservation_id, status="cancelled")


def _ensure_old_object_cleanup_job(db: Session, stage: StagedAudioUpload) -> Optional[AudioStorageJob]:
    if not stage.previous_object_key:
        return None
    if (stage.previous_provider, stage.previous_object_key) == (stage.provider, stage.object_key):
        return None
    provider = stage.previous_provider or "unknown"
    key = _audio_job_key("cleanup", provider, stage.previous_object_key)
    job = db.query(AudioStorageJob).filter(AudioStorageJob.idempotency_key == key).with_for_update().first()
    if job is None:
        job = AudioStorageJob(
            user_id=stage.user_id,
            session_id=stage.session_id,
            idempotency_key=key,
            action="delete_object",
            provider=provider,
            object_key=stage.previous_object_key,
            size_bytes=stage.previous_size_bytes,
            reason="replaced_audio_object",
            status="pending",
            details_json={"replacement_object_key": stage.object_key},
        )
    else:
        # Idempotently reactivate a tombstone if metadata still points at an
        # object whose earlier cleanup record had already completed.
        job.action = "delete_object"
        job.provider = provider
        job.object_key = stage.previous_object_key
        job.size_bytes = stage.previous_size_bytes
        job.reason = "replaced_audio_object"
        job.status = "pending"
        job.next_retry_at = None
        job.safe_error_category = None
        job.completed_at = None
        job.updated_at = dt.datetime.utcnow()
    db.add(job)
    db.flush()
    return job


def _metadata_points_to_stage(db: Session, session_id: int, stage: StagedAudioUpload) -> Optional[bool]:
    try:
        row = db.query(PracticeSession).filter(PracticeSession.id == session_id).populate_existing().first()
        if row is None:
            return False
        return (
            row.audio_storage_provider == stage.provider
            and row.audio_object_key == stage.object_key
            and int(row.audio_size_bytes or 0) == stage.size_bytes
        )
    except Exception:
        db.rollback()
        return None


def _finish_post_commit_audio_work(
    db: Session,
    session: PracticeSession,
    stage: StagedAudioUpload,
    reconciliation_job_id: int,
    cleanup_job_id: Optional[int],
    audio_snapshot: dict,
) -> AudioReplaceResult:
    reconciliation_pending = False
    try:
        db.refresh(session)
        if not (
            session.audio_storage_provider == stage.provider
            and session.audio_object_key == stage.object_key
            and int(session.audio_size_bytes or 0) == stage.size_bytes
        ):
            reconciliation_pending = True
    except Exception:
        db.rollback()
        reconciliation_pending = True

    if not reconciliation_pending and not _mark_audio_job_completed(db, reconciliation_job_id):
        reconciliation_pending = True

    cleanup_pending = False
    if cleanup_job_id is not None:
        try:
            cleanup_previous_audio(stage)
        except Exception:
            _mark_audio_job_retryable(db, cleanup_job_id, "old_object_cleanup_failed")
            cleanup_pending = True
        else:
            if not _mark_audio_job_completed(db, cleanup_job_id):
                # The object is gone, but retain conservative quota accounting
                # until an idempotent retry records that fact durably.
                cleanup_pending = True

    return AudioReplaceResult(
        audio_snapshot=audio_snapshot,
        cleanup_pending=cleanup_pending,
        reconciliation_pending=reconciliation_pending,
    )


def replace_audio_for_session(
    db: Session,
    session: PracticeSession,
    data: bytes,
    mime_type: str,
    duration_seconds: Optional[float],
) -> AudioReplaceResult:
    """Reserve, upload, activate, and reconcile audio without long DB locks."""
    stage = prepare_audio_upload(session, data, mime_type, duration_seconds)
    stage, reservation_id = reserve_audio_upload(db, session, stage)
    try:
        _write_audio_object(stage.provider, stage.object_key, data, stage.mime_type)
    except Exception as upload_error:
        deleted, state_updated = _settle_failed_staged_upload(
            db,
            stage,
            reservation_id,
            "failed_upload_object_cleanup",
        )
        if not deleted:
            raise HTTPException(
                status_code=503,
                detail="Audio upload failed and staged-object cleanup is queued for retry.",
            ) from upload_error
        if not state_updated:
            raise HTTPException(
                status_code=503,
                detail="Audio upload failed; its durable reservation is queued for reconciliation.",
            ) from upload_error
        if isinstance(upload_error, HTTPException):
            raise upload_error
        raise HTTPException(status_code=502, detail="Audio upload failed.") from upload_error

    cleanup_job_id = None
    audio_snapshot = None
    try:
        current = _lock_audio_account_and_session(db, session)
        reservation = (
            db.query(AudioStorageJob)
            .filter(AudioStorageJob.id == reservation_id)
            .with_for_update()
            .first()
        )
        if reservation is None or reservation.action != "upload_reservation" or reservation.status != "reserved":
            raise HTTPException(status_code=409, detail="Audio upload reservation is no longer active.")
        stage = replace(
            stage,
            previous_provider=current.audio_storage_provider,
            previous_object_key=current.audio_object_key,
            previous_size_bytes=max(0, int(current.audio_size_bytes or 0)),
        )
        cleanup_job = _ensure_old_object_cleanup_job(db, stage)
        cleanup_job_id = int(cleanup_job.id) if cleanup_job is not None else None
        apply_staged_audio_metadata(current, stage)
        audio_snapshot = session_to_dict(current)
        reservation.action = "reconcile_metadata"
        reservation.reason = "metadata_commit_confirmation"
        reservation.status = "pending"
        reservation.next_retry_at = None
        reservation.safe_error_category = None
        reservation.details_json = _audio_job_details(stage, audio_snapshot)
        reservation.updated_at = dt.datetime.utcnow()
        db.add_all([current, reservation])
        db.commit()
    except Exception as commit_error:
        db.rollback()
        committed = _metadata_points_to_stage(db, session.id, stage)
        if committed is True and audio_snapshot is not None:
            return _finish_post_commit_audio_work(
                db,
                session,
                stage,
                reservation_id,
                cleanup_job_id,
                audio_snapshot,
            )
        if committed is None:
            # The pre-upload reservation is already durable. Do not risk
            # deleting an object that may have become active in an ambiguous
            # commit; the retry executor will reconcile it after the stale gate.
            return AudioReplaceResult(
                audio_snapshot=audio_snapshot or session_to_dict(session),
                cleanup_pending=bool(stage.previous_object_key),
                reconciliation_pending=True,
                activation_pending=True,
            )
        deleted, state_updated = _settle_failed_staged_upload(
            db,
            stage,
            reservation_id,
            "metadata_commit_failed_cleanup",
        )
        if not deleted:
            raise HTTPException(
                status_code=503,
                detail="Audio metadata was not saved and staged-object cleanup is queued for retry.",
            ) from commit_error
        if not state_updated:
            raise HTTPException(
                status_code=503,
                detail="Audio metadata was not saved; its durable reservation is queued for reconciliation.",
            ) from commit_error
        if isinstance(commit_error, HTTPException):
            raise commit_error
        raise HTTPException(
            status_code=503,
            detail="Audio metadata could not be saved. The staged upload was removed; retry later.",
        ) from commit_error

    return _finish_post_commit_audio_work(
        db,
        session,
        stage,
        reservation_id,
        cleanup_job_id,
        audio_snapshot,
    )


def _audio_retry_candidates(db: Session, limit: int):
    now = dt.datetime.utcnow()
    stale_cutoff = now - dt.timedelta(
        seconds=_positive_int_env("BRASSTUNE_AUDIO_RESERVATION_STALE_SECONDS", 15 * 60)
    )
    return (
        db.query(AudioStorageJob)
        .filter(
            or_(
                AudioStorageJob.status == "pending",
                and_(
                    AudioStorageJob.status == "retryable_failure",
                    or_(AudioStorageJob.next_retry_at.is_(None), AudioStorageJob.next_retry_at <= now),
                ),
                and_(
                    AudioStorageJob.status.in_(("reserved", "in_progress")),
                    AudioStorageJob.updated_at <= stale_cutoff,
                ),
            )
        )
        .order_by(AudioStorageJob.updated_at.asc(), AudioStorageJob.id.asc())
        .limit(max(1, min(limit, 50)))
        .all()
    )


def _audio_job_terminal_retention_days() -> int:
    configured = _positive_int_env(
        "BRASSTUNE_AUDIO_JOB_TERMINAL_RETENTION_DAYS",
        DEFAULT_AUDIO_JOB_TERMINAL_RETENTION_DAYS,
    )
    if configured <= 0:
        return DEFAULT_AUDIO_JOB_TERMINAL_RETENTION_DAYS
    return min(configured, MAX_AUDIO_JOB_TERMINAL_RETENTION_DAYS)


def purge_terminal_audio_storage_jobs(db: Session) -> dict:
    """Purge already-redacted terminal audit rows after a short bounded TTL."""
    retention_days = _audio_job_terminal_retention_days()
    cutoff = dt.datetime.utcnow() - dt.timedelta(days=retention_days)
    try:
        candidate_ids = [
            row.id
            for row in (
                db.query(AudioStorageJob.id)
                .filter(
                    AudioStorageJob.status.in_(AUDIO_JOB_TERMINAL_STATUSES),
                    AudioStorageJob.completed_at.is_not(None),
                    AudioStorageJob.completed_at <= cutoff,
                )
                .order_by(AudioStorageJob.completed_at.asc(), AudioStorageJob.id.asc())
                .limit(MAX_AUDIO_JOB_PURGE_BATCH)
                .all()
            )
        ]
        purged = 0
        if candidate_ids:
            purged = (
                db.query(AudioStorageJob)
                .filter(AudioStorageJob.id.in_(candidate_ids))
                .delete(synchronize_session=False)
            )
        db.commit()
        return {"retention_days": retention_days, "purged": int(purged or 0), "failed": False}
    except Exception:
        db.rollback()
        return {"retention_days": retention_days, "purged": 0, "failed": True}


def _claim_audio_job(db: Session, job_id: int) -> Optional[dict]:
    try:
        job = (
            db.query(AudioStorageJob)
            .filter(AudioStorageJob.id == job_id, AudioStorageJob.status.in_(AUDIO_JOB_ACTIVE_STATUSES))
            .with_for_update(skip_locked=True)
            .first()
        )
        if job is None:
            db.rollback()
            return None
        if job.action == "upload_reservation":
            job.action = "delete_object"
            job.reason = "stale_upload_reservation"
        job.status = "in_progress"
        job.updated_at = dt.datetime.utcnow()
        payload = {
            "id": job.id,
            "action": job.action,
            "provider": job.provider,
            "object_key": job.object_key,
            "size_bytes": int(job.size_bytes or 0),
            "user_id": job.user_id,
            "session_id": job.session_id,
        }
        db.add(job)
        db.commit()
        return payload
    except Exception:
        db.rollback()
        return None


def _reconcile_audio_metadata_job(db: Session, payload: dict) -> Optional[bool]:
    """Return True when reconciled, False when object is inactive, None on DB error."""
    try:
        db.query(User.id).filter(User.id == payload["user_id"]).with_for_update().first()
        session = (
            db.query(PracticeSession)
            .filter(PracticeSession.id == payload["session_id"])
            .populate_existing()
            .with_for_update()
            .first()
        )
        if session is None:
            db.rollback()
            return False
        if (
            session.audio_storage_provider != payload["provider"]
            or session.audio_object_key != payload["object_key"]
        ):
            db.rollback()
            return False
        if int(session.audio_size_bytes or 0) != payload["size_bytes"]:
            session.audio_size_bytes = payload["size_bytes"]
            db.add(session)
            db.commit()
        else:
            db.rollback()
        return True
    except Exception:
        db.rollback()
        return None


def _convert_reconciliation_to_cleanup(db: Session, job_id: int) -> bool:
    try:
        job = db.query(AudioStorageJob).filter(AudioStorageJob.id == job_id).with_for_update().first()
        if job is None:
            db.rollback()
            return False
        job.action = "delete_object"
        job.reason = "inactive_reconciliation_object"
        job.status = "in_progress"
        job.updated_at = dt.datetime.utcnow()
        db.add(job)
        db.commit()
        return True
    except Exception:
        db.rollback()
        return False


def retry_audio_storage_jobs(db: Session, limit: int = 10) -> dict:
    """Idempotently process durable cleanup/reconciliation work."""
    candidate_ids = [candidate.id for candidate in _audio_retry_candidates(db, limit)]
    results = []
    for job_id in candidate_ids:
        payload = _claim_audio_job(db, job_id)
        if payload is None:
            continue
        if payload["action"] == "reconcile_metadata":
            reconciled = _reconcile_audio_metadata_job(db, payload)
            if reconciled is True:
                completed = _mark_audio_job_completed(db, payload["id"])
                results.append({"job_id": payload["id"], "status": "completed" if completed else "pending"})
                continue
            if reconciled is None:
                _mark_audio_job_retryable(db, payload["id"], "metadata_reconciliation_failed")
                results.append({"job_id": payload["id"], "status": "retryable_failure"})
                continue
            if not _convert_reconciliation_to_cleanup(db, payload["id"]):
                _mark_audio_job_retryable(db, payload["id"], "cleanup_conversion_failed")
                results.append({"job_id": payload["id"], "status": "retryable_failure"})
                continue

        try:
            _delete_audio_object(payload["provider"], payload["object_key"])
        except Exception:
            _mark_audio_job_retryable(db, payload["id"], "audio_object_cleanup_failed")
            results.append({"job_id": payload["id"], "status": "retryable_failure"})
            continue
        completed = _mark_audio_job_completed(db, payload["id"])
        results.append({"job_id": payload["id"], "status": "completed" if completed else "pending"})

    return {
        "processed": len(results),
        "completed": sum(1 for row in results if row["status"] == "completed"),
        "still_retryable": sum(1 for row in results if row["status"] != "completed"),
        "results": results,
        "terminal_purge": purge_terminal_audio_storage_jobs(db),
    }


def delete_audio_for_session(session: PracticeSession) -> None:
    if not session.audio_object_key:
        return
    _delete_audio_object(session.audio_storage_provider, session.audio_object_key)
    session.audio_storage_provider = None
    session.audio_object_key = None
    session.audio_mime_type = None
    session.audio_duration_seconds = None
    session.audio_size_bytes = None
    session.audio_uploaded_at = None


def audio_bytes_for_export(session: PracticeSession) -> Optional[Tuple[str, bytes]]:
    if not session.audio_object_key:
        return None
    filename = Path(session.audio_object_key).name
    if session.audio_storage_provider == "local":
        path = local_audio_path(session.audio_object_key)
        if not path.exists():
            return None
        return filename, path.read_bytes()
    if session.audio_storage_provider == "supabase":
        return filename, _read_supabase_object(session.audio_object_key)
    return None
