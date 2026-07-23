import csv
import datetime as dt
import hmac
import io
import json
import os
import zipfile
from typing import List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, Response
from sqlalchemy import and_, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.api.auth import AuthContext, delete_supabase_identity, get_auth_context, require_roles, supabase_global_sign_out
from app.core.analytics.stats import build_heatmap, build_instrument_heatmap, calculate_note_stats, calculate_period_bounds, calculate_progress_metrics
from app.core.ensemble.analytics import calculate_ensemble_summary, generate_rehearsal_report
from app.core.instruments.profiles import get_all_profiles, get_instrument_profile, is_valid_instrument_id, require_instrument_profile
from app.core.recommendations.rules import generate_practice_plan, generate_recommendations, generate_session_recommendations
from app.db.database import get_db
from app.db.readiness import public_readiness_report, readiness_report, version_payload
from app.db.maintenance import clear_practice_data, export_all_data, repair_demo_data, reset_demo_data
from app.models.db import AccountDeletionJob, Group, GroupMember, Invitation, NoteEvent, PitchSample, PracticeSession, Recommendation, UsageEvent, User
from app.schemas.schemas import MAX_BATCH_PITCH_FRAMES, AcceptInvitationRequest, AccountDeletionRequest, AddMemberByUsernameRequest, CreateGroupRequest, JoinByCodeRequest, PitchFrameIn, StartSessionRequest, UpdateGroupMemberRequest, UserProfileUpdate
from app.services.audio_storage import MAX_AUDIO_UPLOAD_BYTES, audio_bytes_for_export, create_supabase_signed_url, delete_audio_for_session, local_audio_path, read_audio_bytes, replace_audio_for_session, retry_audio_storage_jobs
from app.services.serializers import event_to_dict, group_member_to_dict, group_to_dict, iso, sample_to_dict, session_to_dict, user_to_dict
from app.services.session_service import save_pitch_frame, save_pitch_frames, start_session, stop_session
from app.services.usage import record_event

router = APIRouter(prefix="/api")

DEFAULT_EXPORT_MAX_SESSIONS = 200
DEFAULT_EXPORT_MAX_ROWS_PER_SESSION = 50_000
DEFAULT_EXPORT_MAX_TOTAL_ROWS = 250_000
DEFAULT_EXPORT_MAX_AUDIO_BYTES = 200 * 1024 * 1024
DEFAULT_EXPORT_MAX_ARCHIVE_BYTES = 250 * 1024 * 1024
STALE_DELETION_JOB_SECONDS = 15 * 60
DEFAULT_MAX_OWNED_CLASSES_PER_USER = 10
DEFAULT_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER = 20
DEFAULT_MAX_PENDING_CLASS_INVITATIONS_PER_USER = 20


def _bad_instrument(instrument_id: str) -> HTTPException:
    return HTTPException(status_code=400, detail="Unknown instrument_id: %s" % instrument_id)


def _validate_instrument(instrument_id: str) -> None:
    if not is_valid_instrument_id(instrument_id):
        raise _bad_instrument(instrument_id)


def _validate_optional_instrument(instrument_id: Optional[str]) -> None:
    if instrument_id:
        _validate_instrument(instrument_id)


# Unambiguous alphabet for class join codes (no 0/O/1/I/L confusion).
_JOIN_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_JOIN_CODE_LENGTH = 8


def _positive_env_limit(name: str, default: int) -> int:
    """Return a bounded positive quota without letting bad deployment config
    disable a safety limit or make every request fail."""
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if 1 <= value <= 10_000 else default


def _lock_class_quota_user(db: Session, user_id: int) -> None:
    """Serialize class quota decisions for one user on PostgreSQL.

    SQLite ignores FOR UPDATE, which is sufficient for local development; the
    production database prevents concurrent joins/invites from both observing
    the same pre-limit count.
    """
    db.query(User.id).filter(User.id == user_id).with_for_update().first()


def _generate_join_code(db: Session) -> str:
    import secrets

    for _ in range(12):
        code = "".join(secrets.choice(_JOIN_CODE_ALPHABET) for _ in range(_JOIN_CODE_LENGTH))
        if db.query(Group.id).filter(Group.join_code == code).first() is None:
            return code
    raise HTTPException(status_code=503, detail="A class code could not be created. Try again.")


def _parse_date_start(value: Optional[str], field_name: str) -> Optional[dt.datetime]:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value)
    except ValueError:
        try:
            return dt.datetime.combine(dt.date.fromisoformat(value), dt.time.min)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="%s must be ISO date or datetime" % field_name) from exc


def _parse_date_end(value: Optional[str], field_name: str) -> Optional[dt.datetime]:
    parsed = _parse_date_start(value, field_name)
    if parsed is None:
        return None
    if "T" not in value:
        return parsed + dt.timedelta(days=1)
    return parsed


def _session_or_404(db: Session, session_id: int) -> PracticeSession:
    session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


def _can_access_session(user: User, session: PracticeSession) -> bool:
    return user.role == "admin" or session.user_id == user.id


def _require_session_access(db: Session, session_id: int, auth: AuthContext) -> PracticeSession:
    session = _session_or_404(db, session_id)
    if not _can_access_session(auth.user, session):
        raise HTTPException(status_code=403, detail="You do not have access to this session.")
    return session


def _group_or_404(db: Session, group_id: int) -> Group:
    group = db.query(Group).filter(Group.id == group_id).first()
    if group is None:
        raise HTTPException(status_code=404, detail="Group not found")
    return group


def _can_manage_group(user: User, group: Group) -> bool:
    return user.role == "admin" or group.director_user_id == user.id


def _viewer_membership(db: Session, group_id: int, user_id: int) -> Optional[GroupMember]:
    return (
        db.query(GroupMember)
        .filter(GroupMember.group_id == group_id, GroupMember.user_id == user_id, GroupMember.status == "active")
        .first()
    )


def _can_view_full_roster(db: Session, group: Group, user: User) -> bool:
    if _can_manage_group(user, group):
        return True
    membership = _viewer_membership(db, group.id, user.id)
    return membership is not None and getattr(membership, "role_in_group", "student") in {"assistant", "director"}


def _require_group_manager(db: Session, group_id: int, auth: AuthContext) -> Group:
    group = _group_or_404(db, group_id)
    if not _can_manage_group(auth.user, group):
        raise HTTPException(status_code=403, detail="Only the group director or admin can modify this ensemble.")
    return group


def _analytics_user_id(auth: AuthContext, requested_user_id: Optional[int]) -> int:
    if auth.user.role == "admin" and requested_user_id:
        return requested_user_id
    return auth.user.id


def _require_local_demo_or_admin(auth: AuthContext) -> None:
    if auth.user.role == "admin" or auth.is_guest:
        return
    raise HTTPException(status_code=403, detail="This maintenance action is limited to local demo or admin users.")


def _samples_csv_text(samples) -> str:
    output = io.StringIO()
    writer = csv.DictWriter(
        output,
        fieldnames=[
            "timestamp_ms",
            "frequency_hz",
            "confidence",
            "rms",
            "concert_note",
            "concert_octave",
            "written_note",
            "written_octave",
            "cents_deviation",
            "tuning_status",
            "is_valid_for_recording",
        ],
    )
    writer.writeheader()
    for sample in samples:
        data = sample_to_dict(sample)
        writer.writerow({key: data[key] for key in writer.fieldnames})
    return output.getvalue()


def _note_events_csv_text(events) -> str:
    output = io.StringIO()
    writer = csv.DictWriter(
        output,
        fieldnames=[
            "note_label",
            "written_note",
            "written_octave",
            "duration_ms",
            "sample_count",
            "avg_signed_cents",
            "avg_abs_cents",
            "median_cents",
            "stddev_cents",
            "in_tune_percentage",
            "stability_score",
        ],
    )
    writer.writeheader()
    for event in events:
        data = event_to_dict(event)
        writer.writerow({key: data[key] for key in writer.fieldnames})
    return output.getvalue()


def _schema_dict(model):
    if hasattr(model, "model_dump"):
        return model.model_dump()
    return model.dict()


def _positive_int_config(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    # Export caps are mandatory resource-safety boundaries. Unlike explicitly
    # optional local/test quotas, zero must not disable them.
    return value if value > 0 else default


class ExportBudget:
    def __init__(self):
        self.max_sessions = _positive_int_config("BRASSTUNE_EXPORT_MAX_SESSIONS", DEFAULT_EXPORT_MAX_SESSIONS)
        self.max_rows_per_session = _positive_int_config("BRASSTUNE_EXPORT_MAX_ROWS_PER_SESSION", DEFAULT_EXPORT_MAX_ROWS_PER_SESSION)
        self.max_total_rows = _positive_int_config("BRASSTUNE_EXPORT_MAX_TOTAL_ROWS", DEFAULT_EXPORT_MAX_TOTAL_ROWS)
        self.max_audio_bytes = _positive_int_config("BRASSTUNE_EXPORT_MAX_AUDIO_BYTES", DEFAULT_EXPORT_MAX_AUDIO_BYTES)
        self.max_archive_bytes = _positive_int_config("BRASSTUNE_EXPORT_MAX_ARCHIVE_BYTES", DEFAULT_EXPORT_MAX_ARCHIVE_BYTES)
        self.audio_bytes = 0
        self.archive_bytes = 0

    def require_session_count(self, count: int) -> None:
        if self.max_sessions and count > self.max_sessions:
            raise HTTPException(status_code=413, detail="Export contains too many sessions. Narrow the export scope.")

    def require_session_rows(self, db: Session, session_id: int) -> None:
        samples = db.query(PitchSample.id).filter(PitchSample.session_id == session_id).count()
        events = db.query(NoteEvent.id).filter(NoteEvent.session_id == session_id).count()
        if self.max_rows_per_session and max(samples, events) > self.max_rows_per_session:
            raise HTTPException(status_code=413, detail="Export contains too many pitch rows. Narrow the export scope.")

    def require_total_rows(self, db: Session, session_ids: list[int] | None = None) -> None:
        samples = db.query(PitchSample.id)
        events = db.query(NoteEvent.id)
        if session_ids is not None:
            if not session_ids:
                return
            samples = samples.filter(PitchSample.session_id.in_(session_ids))
            events = events.filter(NoteEvent.session_id.in_(session_ids))
        total_rows = samples.count() + events.count()
        if self.max_total_rows and total_rows > self.max_total_rows:
            raise HTTPException(status_code=413, detail="Export contains too many rows. Narrow the export scope.")

    def require_response_text(self, text: str) -> None:
        if self.max_archive_bytes and len(text.encode("utf-8")) > self.max_archive_bytes:
            raise HTTPException(status_code=413, detail="Export response is too large. Narrow the export scope.")

    def write_text(self, archive: zipfile.ZipFile, path: str, text: str) -> None:
        self.write_bytes(archive, path, text.encode("utf-8"))

    def write_bytes(self, archive: zipfile.ZipFile, path: str, data: bytes, *, audio: bool = False) -> None:
        if audio:
            self.audio_bytes += len(data)
            if self.max_audio_bytes and self.audio_bytes > self.max_audio_bytes:
                raise HTTPException(status_code=413, detail="Export audio is too large. Export sessions individually or reduce recordings.")
        self.archive_bytes += len(data)
        if self.max_archive_bytes and self.archive_bytes > self.max_archive_bytes:
            raise HTTPException(status_code=413, detail="Export archive is too large. Export sessions individually or narrow the scope.")
        archive.writestr(path, data)


def _session_json_payload(db: Session, session: PracticeSession, budget: ExportBudget | None = None):
    if budget:
        budget.require_session_rows(db, session.id)
    return {
        "session": session_to_dict(session),
        "samples": [sample_to_dict(sample) for sample in db.query(PitchSample).filter(PitchSample.session_id == session.id).order_by(PitchSample.timestamp_ms.asc()).all()],
        "note_events": [event_to_dict(event) for event in db.query(NoteEvent).filter(NoteEvent.session_id == session.id).order_by(NoteEvent.started_at_ms.asc()).all()],
    }


def _write_session_audio_to_archive(archive: zipfile.ZipFile, session: PracticeSession, folder: str, budget: ExportBudget) -> None:
    if session.audio_size_bytes and budget.max_audio_bytes and budget.audio_bytes + session.audio_size_bytes > budget.max_audio_bytes:
        raise HTTPException(status_code=413, detail="Export audio is too large. Export sessions individually or reduce recordings.")
    audio = audio_bytes_for_export(session)
    if audio is None:
        return
    filename, data = audio
    archive_path = "audio/%s" % filename if folder in {"", "."} else "%s/audio/%s" % (folder, filename)
    budget.write_bytes(archive, archive_path, data, audio=True)


async def _read_limited_body(request: Request, max_bytes: int = MAX_AUDIO_UPLOAD_BYTES) -> bytes:
    chunks = []
    total = 0
    async for chunk in request.stream():
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(status_code=413, detail="Audio upload is too large.")
        chunks.append(chunk)
    return b"".join(chunks)


@router.get("/health")
def health():
    return {"ok": True, "service": "BrassTune Analytics API"}


@router.get("/live")
def live():
    return {"ok": True, "service": "BrassTune Analytics API"}


@router.get("/version")
def version():
    return version_payload()


@router.get("/ready")
def ready():
    report = readiness_report()
    public_report = public_readiness_report(report)
    if not report["ok"]:
        raise HTTPException(status_code=503, detail=public_report)
    return public_report


@router.get("/instruments")
def instruments():
    return [profile.to_dict() for profile in get_all_profiles()]


@router.get("/users/current")
def current_user(auth: AuthContext = Depends(get_auth_context)):
    return user_to_dict(auth.user)


@router.get("/users/me")
def users_me(auth: AuthContext = Depends(get_auth_context)):
    return user_to_dict(auth.user)


@router.patch("/users/me")
def update_user_profile(payload: UserProfileUpdate, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    user = auth.user
    if payload.primary_instrument_id:
        _validate_instrument(payload.primary_instrument_id)
        user.primary_instrument_id = payload.primary_instrument_id
    if payload.display_name:
        user.display_name = payload.display_name.strip()[:80]
        user.name = user.display_name
    if payload.username:
        existing = db.query(User).filter(User.username == payload.username, User.id != user.id).first()
        if existing:
            raise HTTPException(status_code=409, detail="Username is already taken.")
        user.username = payload.username
    if payload.onboarding_completed:
        user.onboarding_completed_at = user.onboarding_completed_at or dt.datetime.utcnow()
    user.updated_at = dt.datetime.utcnow()
    db.add(user)
    db.commit()
    db.refresh(user)
    return user_to_dict(user)


@router.post("/sessions/start")
def start_practice_session(payload: StartSessionRequest, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _validate_instrument(payload.instrument_id)
    session = start_session(db, payload.instrument_id, payload.name, payload.reference_pitch_hz, auth.user.id)
    result = session_to_dict(session)
    record_event(db, "session_started", auth.user.id, {"session_id": result["id"], "instrument_id": payload.instrument_id})
    return result


@router.post("/sessions/{session_id}/samples")
def add_session_sample(session_id: int, frame: PitchFrameIn, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    _validate_instrument(frame.instrument_id)
    if frame.instrument_id != session.instrument_id:
        raise HTTPException(status_code=400, detail="Pitch frame instrument must match the practice session instrument.")
    sample = save_pitch_frame(db, session_id, _schema_dict(frame))
    if sample is None:
        return {"saved": False, "reason": "Frame was invalid, silent, or session was not found."}
    return {"saved": True, "sample": sample_to_dict(sample)}


@router.post("/sessions/{session_id}/samples/batch")
def add_session_samples_batch(session_id: int, frames: List[PitchFrameIn], db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    # The 1 MB JSON body cap (main.py) bounds the raw payload; this explicit
    # 413 keeps a clear, tested contract for oversized batches.
    if len(frames) > MAX_BATCH_PITCH_FRAMES:
        raise HTTPException(status_code=413, detail="Too many pitch frames in one request.")
    for frame in frames:
        _validate_instrument(frame.instrument_id)
        if frame.instrument_id != session.instrument_id:
            raise HTTPException(status_code=400, detail="Pitch frame instrument must match the practice session instrument.")
    samples = save_pitch_frames(db, session_id, [_schema_dict(frame) for frame in frames])
    return {"saved": len(samples), "rejected": max(0, len(frames) - len(samples))}


@router.post("/sessions/{session_id}/stop")
def stop_practice_session(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_session_access(db, session_id, auth)
    session = stop_session(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    result = session_to_dict(session)
    record_event(db, "session_completed", auth.user.id, {"session_id": session_id, "duration_seconds": result["duration_seconds"], "notes_count": result["notes_count"]})
    return result


@router.get("/sessions")
def list_sessions(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    query = db.query(PracticeSession)
    if auth.user.role != "admin":
        query = query.filter(PracticeSession.user_id == auth.user.id)
    rows = query.order_by(PracticeSession.started_at.desc()).all()
    return [session_to_dict(row) for row in rows]


@router.get("/sessions/{session_id}")
def get_session(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    return {
        **session_to_dict(session),
        "samples_count": db.query(PitchSample).filter(PitchSample.session_id == session_id).count(),
        "note_events": [event_to_dict(event) for event in db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()],
    }


@router.get("/sessions/{session_id}/samples")
def get_samples(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_session_access(db, session_id, auth)
    samples = db.query(PitchSample).filter(PitchSample.session_id == session_id).order_by(PitchSample.timestamp_ms.asc()).all()
    return [sample_to_dict(sample) for sample in samples]


@router.get("/sessions/{session_id}/note-events")
def get_note_events(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_session_access(db, session_id, auth)
    events = db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()
    return [event_to_dict(event) for event in events]


@router.get("/sessions/{session_id}/analytics")
def get_session_analytics(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    events = db.query(NoteEvent).filter(NoteEvent.session_id == session_id).all()
    note_stats = calculate_note_stats([event_to_dict(event) for event in events])
    profile = get_instrument_profile(session.instrument_id)
    recommendations = generate_session_recommendations(session_to_dict(session), note_stats)
    return {"session": session_to_dict(session), "note_stats": note_stats, "heatmap": build_instrument_heatmap(note_stats, profile), "recommendations": recommendations, "instrument": profile.to_dict()}


@router.post("/sessions/{session_id}/audio")
async def upload_session_audio(
    session_id: int,
    request: Request,
    content_type: Optional[str] = Header(default=None),
    x_audio_duration_seconds: Optional[float] = Header(default=None),
    db: Session = Depends(get_db),
    auth: AuthContext = Depends(get_auth_context),
):
    session = _require_session_access(db, session_id, auth)
    data, mime_type = read_audio_bytes(await _read_limited_body(request), content_type or "")
    result = replace_audio_for_session(
        db,
        session,
        data,
        mime_type,
        x_audio_duration_seconds,
    )
    if result.cleanup_pending or result.reconciliation_pending or result.activation_pending:
        if result.activation_pending:
            message = "The recording was uploaded, but activation confirmation is pending durable reconciliation."
        elif result.cleanup_pending and result.reconciliation_pending:
            message = "The new recording is active. Metadata confirmation and previous-recording cleanup are queued."
        elif result.reconciliation_pending:
            message = "The new recording is active. Metadata confirmation is queued for retry."
        else:
            message = "The new recording is active. Cleanup of the previous recording is queued for retry."
        return JSONResponse(
            status_code=202,
            content={
                "uploaded": True,
                "cleanup_pending": result.cleanup_pending,
                "reconciliation_pending": result.reconciliation_pending,
                "activation_pending": result.activation_pending,
                "message": message,
                "audio": result.audio_snapshot,
            },
        )
    return {"uploaded": True, "audio": result.audio_snapshot}


@router.get("/sessions/{session_id}/audio")
def get_session_audio(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    if not session.audio_object_key:
        raise HTTPException(status_code=404, detail="No audio was saved for this session.")
    if session.audio_storage_provider == "supabase":
        return RedirectResponse(create_supabase_signed_url(session.audio_object_key))
    path = local_audio_path(session.audio_object_key)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Audio file is missing from local storage.")
    return FileResponse(path, media_type=session.audio_mime_type or "application/octet-stream", filename=path.name)


@router.delete("/sessions/{session_id}/audio")
def delete_session_audio(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    delete_audio_for_session(session)
    db.add(session)
    db.commit()
    return {"deleted": True}


def _filtered_sessions(
    db: Session,
    user_id: Optional[int],
    instrument_id: Optional[str],
    date_from: Optional[dt.datetime] = None,
    date_to: Optional[dt.datetime] = None,
):
    query = db.query(PracticeSession)
    if user_id:
        query = query.filter(PracticeSession.user_id == user_id)
    if instrument_id:
        query = query.filter(PracticeSession.instrument_id == instrument_id)
    if date_from:
        query = query.filter(PracticeSession.started_at >= date_from)
    if date_to:
        query = query.filter(PracticeSession.started_at < date_to)
    return query.order_by(PracticeSession.started_at.asc()).all()


def _filtered_events(
    db: Session,
    user_id: Optional[int],
    instrument_id: Optional[str],
    date_from: Optional[dt.datetime] = None,
    date_to: Optional[dt.datetime] = None,
):
    query = db.query(NoteEvent).join(PracticeSession, PracticeSession.id == NoteEvent.session_id)
    if user_id:
        query = query.filter(PracticeSession.user_id == user_id)
    if instrument_id:
        query = query.filter(NoteEvent.instrument_id == instrument_id)
    if date_from:
        query = query.filter(PracticeSession.started_at >= date_from)
    if date_to:
        query = query.filter(PracticeSession.started_at < date_to)
    return query.order_by(PracticeSession.started_at.asc(), NoteEvent.started_at_ms.asc()).all()


@router.get("/analytics/notes")
def analytics_notes(
    user_id: Optional[int] = Query(default=1),
    instrument_id: Optional[str] = Query(default=None),
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: Session = Depends(get_db),
    auth: AuthContext = Depends(get_auth_context),
):
    _validate_optional_instrument(instrument_id)
    scoped_user_id = _analytics_user_id(auth, user_id)
    parsed_from = _parse_date_start(date_from, "date_from")
    parsed_to = _parse_date_end(date_to, "date_to")
    events = _filtered_events(db, scoped_user_id, instrument_id, parsed_from, parsed_to)
    return calculate_note_stats([event_to_dict(event) for event in events])


@router.get("/analytics/progress")
def analytics_progress(
    user_id: Optional[int] = 1,
    instrument_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: Session = Depends(get_db),
    auth: AuthContext = Depends(get_auth_context),
):
    _validate_optional_instrument(instrument_id)
    scoped_user_id = _analytics_user_id(auth, user_id)
    parsed_from = _parse_date_start(date_from, "date_from")
    parsed_to = _parse_date_end(date_to, "date_to")
    sessions = _filtered_sessions(db, scoped_user_id, instrument_id, parsed_from, parsed_to)
    period = calculate_period_bounds(parsed_from, parsed_to)
    current_events = _filtered_events(db, scoped_user_id, instrument_id, period["current_start"], period["current_end"])
    previous_events = _filtered_events(db, scoped_user_id, instrument_id, period["previous_start"], period["previous_end"])
    current_stats = calculate_note_stats([event_to_dict(event) for event in current_events])
    previous_stats = calculate_note_stats([event_to_dict(event) for event in previous_events])
    payload = calculate_progress_metrics(scoped_user_id, sessions, current_stats, previous_stats)
    payload["period"] = {key: value.isoformat() for key, value in period.items()}
    return payload


@router.get("/analytics/heatmap")
def analytics_heatmap(
    user_id: Optional[int] = 1,
    instrument_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: Session = Depends(get_db),
    auth: AuthContext = Depends(get_auth_context),
):
    _validate_optional_instrument(instrument_id)
    scoped_user_id = _analytics_user_id(auth, user_id)
    parsed_from = _parse_date_start(date_from, "date_from")
    parsed_to = _parse_date_end(date_to, "date_to")
    events = _filtered_events(db, scoped_user_id, instrument_id, parsed_from, parsed_to)
    stats = calculate_note_stats([event_to_dict(event) for event in events])
    if instrument_id:
        return build_instrument_heatmap(stats, require_instrument_profile(instrument_id))
    return build_heatmap(stats)


@router.get("/recommendations")
def recommendations(user_id: Optional[int] = 1, instrument_id: str = "trumpet", db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _validate_instrument(instrument_id)
    events = _filtered_events(db, _analytics_user_id(auth, user_id), instrument_id)
    stats = calculate_note_stats([event_to_dict(event) for event in events])
    return generate_recommendations(stats, get_instrument_profile(instrument_id))


@router.get("/practice-plan")
def practice_plan(user_id: Optional[int] = 1, instrument_id: str = "trumpet", db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _validate_instrument(instrument_id)
    events = _filtered_events(db, _analytics_user_id(auth, user_id), instrument_id)
    stats = calculate_note_stats([event_to_dict(event) for event in events])
    problem_notes = sorted(stats, key=lambda row: float(row.get("problem_severity", 0)), reverse=True)
    return generate_practice_plan(problem_notes, get_instrument_profile(instrument_id))


@router.get("/export/session/{session_id}.csv")
def export_session_csv(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_session_access(db, session_id, auth)
    budget = ExportBudget()
    budget.require_session_rows(db, session_id)
    samples = db.query(PitchSample).filter(PitchSample.session_id == session_id).order_by(PitchSample.timestamp_ms.asc()).all()
    return Response(_samples_csv_text(samples), media_type="text/csv", headers={"Content-Disposition": "attachment; filename=session-%s-samples.csv" % session_id})


@router.get("/export/session/{session_id}.json")
def export_session_json(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    payload = _session_json_payload(db, session, ExportBudget())
    return Response(json.dumps(payload, indent=2), media_type="application/json", headers={"Content-Disposition": "attachment; filename=session-%s.json" % session_id})


@router.get("/export/note-events/{session_id}.csv")
def export_note_events_csv(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_session_access(db, session_id, auth)
    budget = ExportBudget()
    budget.require_session_rows(db, session_id)
    events = db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()
    return Response(_note_events_csv_text(events), media_type="text/csv", headers={"Content-Disposition": "attachment; filename=session-%s-note-events.csv" % session_id})


@router.get("/export/session/{session_id}/audio")
def export_session_audio(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    return get_session_audio(session_id, db, auth)


@router.get("/export/session/{session_id}.zip")
def export_session_zip(session_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    session = _require_session_access(db, session_id, auth)
    budget = ExportBudget()
    payload = _session_json_payload(db, session, budget)
    recommendations = generate_session_recommendations(session_to_dict(session), calculate_note_stats(payload["note_events"]))
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        budget.write_text(archive, "session.json", json.dumps(payload, indent=2))
        budget.write_text(archive, "pitch_samples.csv", _samples_csv_text(db.query(PitchSample).filter(PitchSample.session_id == session_id).order_by(PitchSample.timestamp_ms.asc()).all()))
        budget.write_text(archive, "note_events.csv", _note_events_csv_text(db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()))
        budget.write_text(archive, "recommendations.json", json.dumps(recommendations, indent=2))
        budget.write_text(
            archive,
            "README.txt",
            "BrassTune session export. pitch_samples.csv contains detector frames; note_events.csv contains segmented note statistics; recommendations.json contains generated practice guidance.",
        )
        _write_session_audio_to_archive(archive, session, ".", budget)
    buffer.seek(0)
    return Response(buffer.getvalue(), media_type="application/zip", headers={"Content-Disposition": "attachment; filename=session-%s-export.zip" % session_id})


@router.get("/export/all.json")
def export_all_json(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    if auth.user.role != "admin" and not auth.is_guest:
        raise HTTPException(status_code=403, detail="Full local export is limited to local demo/admin users.")
    budget = ExportBudget()
    budget.require_session_count(db.query(PracticeSession.id).count())
    budget.require_total_rows(db)
    payload = export_all_data(db)
    budget.require_response_text(payload)
    return Response(payload, media_type="application/json", headers={"Content-Disposition": "attachment; filename=brasstune-local-data.json"})


@router.get("/export/all.zip")
def export_all_zip(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    query = db.query(PracticeSession)
    if auth.user.role != "admin":
        query = query.filter(PracticeSession.user_id == auth.user.id)
    sessions = query.order_by(PracticeSession.started_at.asc()).all()
    budget = ExportBudget()
    budget.require_session_count(len(sessions))
    budget.require_total_rows(db, [session.id for session in sessions])
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        budget.write_text(archive, "README.txt", "BrassTune all-data export for the authenticated user/admin scope.")
        budget.write_text(archive, "sessions.json", json.dumps([session_to_dict(session) for session in sessions], indent=2))
        for session in sessions:
            folder = "sessions/%s" % session.id
            payload = _session_json_payload(db, session, budget)
            budget.write_text(archive, "%s/session.json" % folder, json.dumps(payload, indent=2))
            budget.write_text(archive, "%s/pitch_samples.csv" % folder, _samples_csv_text(db.query(PitchSample).filter(PitchSample.session_id == session.id).order_by(PitchSample.timestamp_ms.asc()).all()))
            budget.write_text(archive, "%s/note_events.csv" % folder, _note_events_csv_text(db.query(NoteEvent).filter(NoteEvent.session_id == session.id).order_by(NoteEvent.started_at_ms.asc()).all()))
            _write_session_audio_to_archive(archive, session, folder, budget)
    buffer.seek(0)
    return Response(buffer.getvalue(), media_type="application/zip", headers={"Content-Disposition": "attachment; filename=brasstune-export.zip"})


def _iso(value):
    return value.isoformat() if value else None


def _recommendation_to_dict(row: Recommendation):
    return {
        "id": row.id,
        "session_id": row.session_id,
        "note_event_id": row.note_event_id,
        "written_note": row.written_note,
        "written_octave": row.written_octave,
        "severity": row.severity,
        "title": row.title,
        "message": row.message,
        "suggestions": json.loads(row.suggestions_json or "[]"),
        "created_at": _iso(row.created_at),
    }


def _invitation_to_dict(row: Invitation):
    return {
        "id": row.id,
        "group_id": row.group_id,
        "invited_username": row.invited_username,
        "invited_user_id": row.invited_user_id,
        "invited_by_user_id": row.invited_by_user_id,
        "status": row.status,
        "created_at": _iso(row.created_at),
        "accepted_at": _iso(row.accepted_at),
    }


def _account_export_zip(db: Session, auth: AuthContext):
    user = auth.user
    sessions = db.query(PracticeSession).filter(PracticeSession.user_id == user.id).order_by(PracticeSession.started_at.asc()).all()
    memberships = db.query(GroupMember).filter(GroupMember.user_id == user.id).order_by(GroupMember.group_id.asc()).all()
    owned_groups = db.query(Group).filter(Group.director_user_id == user.id).order_by(Group.id.asc()).all()
    invitations = (
        db.query(Invitation)
        .filter((Invitation.invited_user_id == user.id) | (Invitation.invited_by_user_id == user.id))
        .order_by(Invitation.created_at.asc())
        .all()
    )
    recommendations = db.query(Recommendation).filter(Recommendation.user_id == user.id).order_by(Recommendation.created_at.asc()).all()
    account = user_to_dict(user)
    account["email"] = user.email
    account["supabase_user_id"] = user.supabase_user_id
    account["created_at"] = _iso(user.created_at)
    account["updated_at"] = _iso(user.updated_at)
    budget = ExportBudget()
    budget.require_session_count(len(sessions))
    budget.require_total_rows(db, [session.id for session in sessions])
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        budget.write_text(archive, "README.txt", "BrassTune account export for the authenticated user. Source recordings are included only for this user's sessions when available.")
        budget.write_text(archive, "account.json", json.dumps(account, indent=2))
        budget.write_text(archive, "sessions.json", json.dumps([session_to_dict(session) for session in sessions], indent=2))
        budget.write_text(archive, "memberships.json", json.dumps([group_member_to_dict(member) for member in memberships], indent=2))
        budget.write_text(archive, "owned_groups.json", json.dumps([group_to_dict(group) for group in owned_groups], indent=2))
        budget.write_text(archive, "invitations.json", json.dumps([_invitation_to_dict(row) for row in invitations], indent=2))
        budget.write_text(archive, "recommendations.json", json.dumps([_recommendation_to_dict(row) for row in recommendations], indent=2))
        for session in sessions:
            folder = "sessions/%s" % session.id
            payload = _session_json_payload(db, session, budget)
            budget.write_text(archive, "%s/session.json" % folder, json.dumps(payload, indent=2))
            budget.write_text(archive, "%s/pitch_samples.csv" % folder, _samples_csv_text(db.query(PitchSample).filter(PitchSample.session_id == session.id).order_by(PitchSample.timestamp_ms.asc()).all()))
            budget.write_text(archive, "%s/note_events.csv" % folder, _note_events_csv_text(db.query(NoteEvent).filter(NoteEvent.session_id == session.id).order_by(NoteEvent.started_at_ms.asc()).all()))
            _write_session_audio_to_archive(archive, session, folder, budget)
    buffer.seek(0)
    return Response(buffer.getvalue(), media_type="application/zip", headers={"Content-Disposition": "attachment; filename=brasstune-account-export.zip"})


@router.post("/admin/sessions/clear")
def clear_local_sessions(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_local_demo_or_admin(auth)
    return {"cleared": clear_practice_data(db)}


@router.post("/admin/demo-data/reset")
def reset_local_demo_data(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_local_demo_or_admin(auth)
    return reset_demo_data(db)


@router.post("/admin/demo-data/repair")
def repair_local_demo_data(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_local_demo_or_admin(auth)
    return repair_demo_data(db)


@router.post("/dev/repair-demo-data")
def repair_demo_data_dev(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_local_demo_or_admin(auth)
    return repair_demo_data(db)


@router.post("/users/me/clear-sessions")
def clear_my_sessions(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    sessions = db.query(PracticeSession).filter(PracticeSession.user_id == auth.user.id).all()
    deleted = len(sessions)
    for session in sessions:
        delete_audio_for_session(session)
        db.delete(session)
    db.commit()
    return {"cleared": {"practice_sessions": deleted}}


@router.get("/users/me/export.zip")
def export_me_zip(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    return _account_export_zip(db, auth)


def _mark_deletion_job(job: AccountDeletionJob, stage: str, status: str, error_category: Optional[str] = None) -> None:
    job.stage = stage
    job.status = status
    job.safe_error_category = error_category
    job.updated_at = dt.datetime.utcnow()
    if status == "completed":
        job.completed_at = job.completed_at or dt.datetime.utcnow()
        job.next_retry_at = None
    elif status == "retryable_failure":
        job.retry_count = int(job.retry_count or 0) + 1
        job.next_retry_at = dt.datetime.utcnow() + dt.timedelta(minutes=min(60, 2 ** min(job.retry_count, 6)))


def _deletion_job_payload(job: AccountDeletionJob):
    if isinstance(job.counts_json, dict):
        counts = job.counts_json
    elif isinstance(job.counts_json, str):
        try:
            counts = json.loads(job.counts_json or "{}")
        except (TypeError, json.JSONDecodeError):
            counts = {}
    else:
        counts = {}
    if job.status == "completed":
        deletion_status = "completed"
    elif job.stage == "external_cleanup_failed":
        deletion_status = "external_cleanup_queued"
    elif job.stage == "local_cleanup_failed":
        deletion_status = "local_cleanup_queued"
    else:
        deletion_status = job.status
    return {
        "deleted": job.status == "completed",
        "deletion_status": deletion_status,
        "deletion_stage": job.stage,
        "counts": counts,
        "supabase_sessions_revoked": job.status == "completed",
        "supabase_identity_deleted": job.status == "completed",
        "teacher_owned_group_policy": "Teacher-owned groups are deleted with their memberships and invitations. Students retain their own practice data.",
    }


def retry_account_deletion_jobs(db: Session, limit: int = 10) -> dict:
    now = dt.datetime.utcnow()
    stale_cutoff = now - dt.timedelta(seconds=STALE_DELETION_JOB_SECONDS)
    jobs = (
        db.query(AccountDeletionJob)
        .filter(
            or_(
                AccountDeletionJob.status == "retryable_failure",
                and_(
                    AccountDeletionJob.status == "in_progress",
                    AccountDeletionJob.stage.in_(["local_cleanup_started", "local_cleanup_completed", "external_cleanup_started"]),
                    AccountDeletionJob.updated_at <= stale_cutoff,
                ),
            )
        )
        .filter(
            or_(
                AccountDeletionJob.status == "in_progress",
                AccountDeletionJob.next_retry_at.is_(None),
                AccountDeletionJob.next_retry_at <= now,
            )
        )
        .order_by(AccountDeletionJob.updated_at.asc())
        .limit(max(1, min(limit, 50)))
        .all()
    )
    results = []
    for job in jobs:
        if job.stage in {"local_cleanup_started", "local_cleanup_failed"}:
            user = db.query(User).filter(User.id == job.user_id).first()
            if user is not None:
                try:
                    payload = delete_my_account(
                        AccountDeletionRequest(confirmation="delete my account"),
                        db,
                        AuthContext(user=user, is_guest=False, access_token=None),
                    )
                    results.append({"job_id": job.id, "status": payload.get("deletion_status", "unknown"), "stage": payload.get("deletion_stage")})
                    continue
                except HTTPException:
                    db.refresh(job)
                    results.append({"job_id": job.id, "status": job.status, "stage": job.stage})
                    continue

        if not job.supabase_user_id:
            _mark_deletion_job(job, "completed", "completed")
            db.add(job)
            db.commit()
            results.append({"job_id": job.id, "status": job.status, "stage": job.stage})
            continue

        _mark_deletion_job(job, "external_cleanup_started", "in_progress")
        db.add(job)
        db.commit()
        try:
            external_deleted = delete_supabase_identity(job.supabase_user_id)
        except Exception:
            external_deleted = False
        if external_deleted:
            _mark_deletion_job(job, "completed", "completed")
        else:
            _mark_deletion_job(job, "external_cleanup_failed", "retryable_failure", "external_identity_cleanup_failed")
        db.add(job)
        db.commit()
        results.append({"job_id": job.id, "status": job.status, "stage": job.stage})
    return {
        "processed": len(results),
        "completed": sum(1 for row in results if row["status"] == "completed"),
        "still_retryable": sum(1 for row in results if row["status"] == "retryable_failure"),
        "results": results,
    }


def _require_account_deletion_retry_secret(header_value: Optional[str]) -> None:
    expected = os.getenv("BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET")
    if not expected:
        raise HTTPException(status_code=503, detail="Account deletion retry executor is not configured.")
    if not header_value or not hmac.compare_digest(header_value, expected):
        raise HTTPException(status_code=403, detail="Account deletion retry executor is not authorized.")


@router.post("/maintenance/account-deletions/retry")
def retry_account_deletions(
    limit: int = Query(default=10, ge=1, le=50),
    x_brasstune_maintenance_secret: Optional[str] = Header(default=None, alias="X-BrassTune-Maintenance-Secret"),
    db: Session = Depends(get_db),
):
    _require_account_deletion_retry_secret(x_brasstune_maintenance_secret)
    account_result = retry_account_deletion_jobs(db, limit=limit)
    account_result["audio_storage"] = retry_audio_storage_jobs(db, limit=limit)
    return account_result


@router.post("/maintenance/audio-storage/retry")
def retry_audio_storage(
    limit: int = Query(default=10, ge=1, le=50),
    x_brasstune_maintenance_secret: Optional[str] = Header(default=None, alias="X-BrassTune-Maintenance-Secret"),
    db: Session = Depends(get_db),
):
    _require_account_deletion_retry_secret(x_brasstune_maintenance_secret)
    return retry_audio_storage_jobs(db, limit=limit)


@router.delete("/users/me")
def delete_my_account(payload: AccountDeletionRequest, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    confirmation = payload.confirmation.strip().lower()
    if confirmation != "delete my account":
        raise HTTPException(status_code=400, detail='Type "delete my account" to confirm account deletion.')
    user = auth.user
    user_id = user.id
    supabase_user_id = user.supabase_user_id
    job_key = "delete-user-%s" % user_id
    job = db.query(AccountDeletionJob).filter(AccountDeletionJob.idempotency_key == job_key).first()
    if job and job.status == "completed" and db.query(User).filter(User.id == user_id).first() is None:
        return _deletion_job_payload(job)
    sessions = db.query(PracticeSession).filter(PracticeSession.user_id == user_id).all()
    owned_groups = db.query(Group).filter(Group.director_user_id == user_id).all()
    group_ids = [group.id for group in owned_groups]
    deleted_counts = {
        "practice_sessions": len(sessions),
        "teacher_owned_groups": len(owned_groups),
        "group_memberships": db.query(GroupMember).filter(GroupMember.user_id == user_id).count(),
        "invitations": db.query(Invitation).filter((Invitation.invited_user_id == user_id) | (Invitation.invited_by_user_id == user_id)).count(),
        "recommendations": db.query(Recommendation).filter(Recommendation.user_id == user_id).count(),
        "usage_events": db.query(UsageEvent).filter(UsageEvent.user_id == user_id).count(),
    }
    if job is None:
        job = AccountDeletionJob(
            user_id=user_id,
            supabase_user_id=supabase_user_id,
            idempotency_key=job_key,
            counts_json=deleted_counts,
        )
    else:
        job.supabase_user_id = job.supabase_user_id or supabase_user_id
        job.counts_json = deleted_counts
    _mark_deletion_job(job, "local_cleanup_started", "in_progress")
    db.add(job)
    db.commit()

    try:
        for session in sessions:
            delete_audio_for_session(session)
    except Exception as exc:
        _mark_deletion_job(job, "local_cleanup_failed", "retryable_failure", "audio_cleanup_failed")
        db.add(job)
        db.commit()
        raise HTTPException(status_code=503, detail="Account deletion is queued for retry because local media cleanup is temporarily unavailable.") from exc

    for session in sessions:
        db.delete(session)
    if group_ids:
        db.query(Invitation).filter(Invitation.group_id.in_(group_ids)).delete(synchronize_session=False)
        db.query(GroupMember).filter(GroupMember.group_id.in_(group_ids)).delete(synchronize_session=False)
        db.query(Group).filter(Group.id.in_(group_ids)).delete(synchronize_session=False)
    db.query(Invitation).filter((Invitation.invited_user_id == user_id) | (Invitation.invited_by_user_id == user_id)).delete(synchronize_session=False)
    db.query(GroupMember).filter(GroupMember.user_id == user_id).delete(synchronize_session=False)
    db.query(Recommendation).filter(Recommendation.user_id == user_id).delete(synchronize_session=False)
    # Usage analytics are not retained under a deleted account identifier. This
    # intentionally removes those events rather than preserving linkable history.
    db.query(UsageEvent).filter(UsageEvent.user_id == user_id).delete(synchronize_session=False)
    db.delete(user)
    _mark_deletion_job(job, "local_cleanup_completed", "in_progress")
    db.add(job)
    db.commit()

    supabase_sessions_revoked = False
    supabase_identity_deleted = False
    if not auth.is_guest and supabase_user_id:
        try:
            _mark_deletion_job(job, "external_cleanup_started", "in_progress")
            db.add(job)
            db.commit()
            supabase_sessions_revoked = supabase_global_sign_out(auth.access_token)
            supabase_identity_deleted = delete_supabase_identity(supabase_user_id)
        except Exception:
            supabase_sessions_revoked = False
            supabase_identity_deleted = False
        if not supabase_identity_deleted:
            _mark_deletion_job(job, "external_cleanup_failed", "retryable_failure", "external_identity_cleanup_failed")
            db.add(job)
            db.commit()
            return _deletion_job_payload(job)
    _mark_deletion_job(job, "completed", "completed")
    db.add(job)
    db.commit()
    return _deletion_job_payload(job)


def _group_member_ids(db: Session, group_id: int):
    return [member.user_id for member in db.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.status == "active").all()]


def _member_active_since(member: GroupMember) -> dt.datetime:
    return member.active_since or member.created_at


def _group_scoped_sessions(db: Session, group_id: int) -> List[PracticeSession]:
    members = db.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.status == "active").all()
    sessions_by_id = {}
    for member in members:
        rows = (
            db.query(PracticeSession)
            .options(joinedload(PracticeSession.note_events))
            .filter(
                PracticeSession.user_id == member.user_id,
                PracticeSession.started_at >= _member_active_since(member),
            )
            .all()
        )
        for session in rows:
            sessions_by_id[session.id] = session
    return list(sessions_by_id.values())


def _can_view_group(user: User, group: Group, db: Session) -> bool:
    if _can_manage_group(user, group):
        return True
    return _viewer_membership(db, group.id, user.id) is not None


def _visible_group_members(db: Session, group: Group, user: User):
    if _can_manage_group(user, group):
        members = db.query(GroupMember).options(joinedload(GroupMember.user)).filter(GroupMember.group_id == group.id).order_by(GroupMember.created_at.asc()).all()
        return [group_member_to_dict(member) for member in members], "full"
    membership = _viewer_membership(db, group.id, user.id)
    if membership is not None and membership.role_in_group in {"assistant", "director"}:
        members = (
            db.query(GroupMember)
            .options(joinedload(GroupMember.user))
            .filter(GroupMember.group_id == group.id, GroupMember.status == "active")
            .order_by(GroupMember.created_at.asc())
            .all()
        )
        payloads = []
        for member in members:
            payload = group_member_to_dict(member)
            payload.pop("user_id", None)
            payload.pop("username", None)
            if member.user_id == user.id:
                payload["is_current_user"] = True
            payloads.append(payload)
        return payloads, "active_redacted"
    membership = (
        db.query(GroupMember)
        .options(joinedload(GroupMember.user))
        .filter(GroupMember.group_id == group.id, GroupMember.user_id == user.id, GroupMember.status == "active")
        .first()
    )
    return ([group_member_to_dict(membership, include_identity=False)] if membership else []), "self"


def _group_viewer_capabilities(db: Session, group: Group, user: User) -> dict:
    """Describe the viewer's effective class capabilities without relying on
    management-only fields such as the join code."""
    membership = _viewer_membership(db, group.id, user.id)
    is_owner = group.director_user_id == user.id
    if is_owner:
        viewer_role = "owner"
    elif membership is not None and membership.role_in_group in {"assistant", "director"}:
        # Non-owner `director` memberships have the same effective read
        # capability as assistants; ownership remains the management boundary.
        viewer_role = "assistant"
    elif membership is not None:
        viewer_role = "student"
    elif user.role == "admin":
        viewer_role = "admin_observer"
    else:
        viewer_role = "student"
    return {
        "viewer_role": viewer_role,
        "viewer_can_leave": bool(
            membership is not None
            and not is_owner
        ),
        "viewer_can_manage": _can_manage_group(user, group),
    }


@router.post("/ensemble/groups")
def create_ensemble_group(payload: CreateGroupRequest, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    # Self-serve: any signed-in user can start an ensemble and becomes its director.
    _lock_class_quota_user(db, auth.user.id)
    owned_count = db.query(Group.id).filter(Group.director_user_id == auth.user.id).count()
    owned_limit = _positive_env_limit("BRASSTUNE_MAX_OWNED_CLASSES_PER_USER", DEFAULT_MAX_OWNED_CLASSES_PER_USER)
    if owned_count >= owned_limit:
        raise HTTPException(status_code=409, detail="You have reached the class ownership limit.")
    group = Group(name=payload.name.strip(), director_user_id=auth.user.id, join_code=_generate_join_code(db))
    db.add(group)
    if auth.user.role == "student":
        auth.user.role = "director"
        db.add(auth.user)
    db.commit()
    db.refresh(group)
    record_event(db, "group_created", auth.user.id, {"group_id": group.id})
    return group_to_dict(group)


@router.get("/ensemble/groups")
def list_ensemble_groups(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    if auth.user.role == "admin":
        groups = db.query(Group).order_by(Group.name.asc()).all()
    elif auth.user.role == "director":
        owned_ids = {g.id for g in db.query(Group).filter(Group.director_user_id == auth.user.id).all()}
        member_ids = {r.group_id for r in db.query(GroupMember).filter(GroupMember.user_id == auth.user.id, GroupMember.status == "active").all()}
        ids = owned_ids | member_ids
        groups = db.query(Group).filter(Group.id.in_(ids)).order_by(Group.name.asc()).all() if ids else []
    else:
        group_ids = [row.group_id for row in db.query(GroupMember).filter(GroupMember.user_id == auth.user.id, GroupMember.status == "active").all()]
        groups = db.query(Group).filter(Group.id.in_(group_ids)).order_by(Group.name.asc()).all() if group_ids else []
    # The global "director" role only means the user owns at least one class. It
    # must not reveal management details for unrelated classes they merely joined.
    payloads = []
    for group in groups:
        payload = group_to_dict(group, include_director_identity=_can_manage_group(auth.user, group))
        payload.update(_group_viewer_capabilities(db, group, auth.user))
        payloads.append(payload)
    return payloads


@router.get("/ensemble/groups/{group_id}")
def get_ensemble_group(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    group = _group_or_404(db, group_id)
    if not _can_view_group(auth.user, group, db):
        raise HTTPException(status_code=403, detail="You do not have access to this ensemble.")
    members, roster_scope = _visible_group_members(db, group, auth.user)
    # Assistants can view the roster, but the join code remains a management
    # credential and is only returned to the owner or an administrator.
    payload = group_to_dict(group, members, include_director_identity=_can_manage_group(auth.user, group))
    payload["roster_scope"] = roster_scope
    payload.update(_group_viewer_capabilities(db, group, auth.user))
    return payload


@router.get("/ensemble/groups/{group_id}/members")
def get_ensemble_members(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    group = _group_or_404(db, group_id)
    if not _can_view_group(auth.user, group, db):
        raise HTTPException(status_code=403, detail="You do not have access to this ensemble.")
    members, _ = _visible_group_members(db, group, auth.user)
    return members


@router.post("/ensemble/groups/{group_id}/members/by-username")
def add_member_by_username(group_id: int, payload: AddMemberByUsernameRequest, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    """Invite a user to the ensemble by username. The user joins with
    status='invited' and must accept before they become an active member."""
    _require_group_manager(db, group_id, auth)
    _validate_optional_instrument(payload.instrument_id)
    if payload.role_in_group not in {"student", "assistant", "director"}:
        raise HTTPException(status_code=400, detail="Invalid role_in_group.")
    # The instrument is optional at invite time; the student sets their own when
    # they accept. Store a neutral placeholder until then.
    invite_instrument = payload.instrument_id or "unassigned"
    user = db.query(User).filter(User.username == payload.username).first()
    if user is None:
        raise HTTPException(status_code=404, detail="That username could not be invited.")
    _lock_class_quota_user(db, user.id)
    existing = db.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.user_id == user.id).first()
    if existing:
        previous_status = existing.status
        if previous_status == "active":
            raise HTTPException(status_code=409, detail="This user is already an active ensemble member.")
        if previous_status == "invited":
            raise HTTPException(status_code=409, detail="This user already has a pending invitation.")
        pending_count = db.query(GroupMember.id).filter(GroupMember.user_id == user.id, GroupMember.status == "invited").count()
        pending_limit = _positive_env_limit(
            "BRASSTUNE_MAX_PENDING_CLASS_INVITATIONS_PER_USER",
            DEFAULT_MAX_PENDING_CLASS_INVITATIONS_PER_USER,
        )
        if pending_count >= pending_limit:
            raise HTTPException(status_code=409, detail="That username could not be invited right now.")
        existing.instrument_id = invite_instrument
        existing.role_in_group = payload.role_in_group
        existing.status = "invited"
        existing.active_since = None
        existing.removed_at = None
        member = existing
    else:
        pending_count = db.query(GroupMember.id).filter(GroupMember.user_id == user.id, GroupMember.status == "invited").count()
        pending_limit = _positive_env_limit(
            "BRASSTUNE_MAX_PENDING_CLASS_INVITATIONS_PER_USER",
            DEFAULT_MAX_PENDING_CLASS_INVITATIONS_PER_USER,
        )
        if pending_count >= pending_limit:
            raise HTTPException(status_code=409, detail="That username could not be invited right now.")
        member = GroupMember(group_id=group_id, user_id=user.id, instrument_id=invite_instrument, role_in_group=payload.role_in_group, status="invited", active_since=None)
        db.add(member)
    db.commit()
    db.refresh(member)
    record_event(db, "invitation_sent", auth.user.id, {"group_id": group_id, "invited_user_id": user.id})
    return group_member_to_dict(db.query(GroupMember).options(joinedload(GroupMember.user)).filter(GroupMember.id == member.id).first())


def _my_invitation_or_404(db: Session, member_id: int, auth: AuthContext) -> GroupMember:
    member = (
        db.query(GroupMember)
        .filter(GroupMember.id == member_id, GroupMember.user_id == auth.user.id, GroupMember.status == "invited")
        .first()
    )
    if member is None:
        raise HTTPException(status_code=404, detail="Invitation not found.")
    return member


@router.get("/ensemble/invitations")
def list_my_invitations(db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    """Pending ensemble invitations for the signed-in user."""
    rows = (
        db.query(GroupMember, Group)
        .join(Group, Group.id == GroupMember.group_id)
        .filter(GroupMember.user_id == auth.user.id, GroupMember.status == "invited")
        .order_by(GroupMember.created_at.desc())
        .all()
    )
    invitations = []
    for member, group in rows:
        director = db.query(User).filter(User.id == group.director_user_id).first()
        invitations.append({
            "member_id": member.id,
            "group_id": group.id,
            "group_name": group.name,
            "instrument_id": member.instrument_id,
            "role_in_group": member.role_in_group,
            "invited_at": iso(member.created_at),
            "director_name": (director.display_name or director.name) if director else None,
        })
    return {"invitations": invitations}


@router.post("/ensemble/invitations/{member_id}/accept")
def accept_invitation(member_id: int, payload: Optional[AcceptInvitationRequest] = None, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    member = _my_invitation_or_404(db, member_id, auth)
    _lock_class_quota_user(db, auth.user.id)
    active_count = db.query(GroupMember.id).filter(GroupMember.user_id == auth.user.id, GroupMember.status == "active").count()
    active_limit = _positive_env_limit(
        "BRASSTUNE_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER",
        DEFAULT_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER,
    )
    if active_count >= active_limit:
        raise HTTPException(status_code=409, detail="You have reached the active class limit.")
    # The invited student may set their own instrument when accepting, overriding
    # whatever placeholder the director used.
    chosen_instrument = payload.instrument_id if payload else None
    if chosen_instrument:
        _validate_instrument(chosen_instrument)
        member.instrument_id = chosen_instrument
    member.status = "active"
    member.active_since = dt.datetime.utcnow()
    member.removed_at = None
    db.add(member)
    db.commit()
    record_event(db, "invitation_accepted", auth.user.id, {"group_id": member.group_id})
    return {"accepted": True, "group_id": member.group_id}


@router.post("/ensemble/invitations/{member_id}/decline")
def decline_invitation(member_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    member = _my_invitation_or_404(db, member_id, auth)
    member.status = "removed"
    member.removed_at = dt.datetime.utcnow()
    db.add(member)
    db.commit()
    return {"declined": True}


@router.post("/ensemble/join")
def join_ensemble_by_code(payload: JoinByCodeRequest, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    """Self-join a class with its join code. Entering the code is the student's
    consent, so they join as an active member immediately and choose their own
    instrument."""
    group = db.query(Group).filter(Group.join_code == payload.code).first()
    if group is None:
        raise HTTPException(status_code=404, detail="No class found with that code. Double-check it with your teacher.")
    if group.director_user_id == auth.user.id:
        raise HTTPException(status_code=400, detail="You're the director of this class.")
    _validate_optional_instrument(payload.instrument_id)
    instrument = payload.instrument_id or getattr(auth.user, "primary_instrument_id", None) or "unassigned"
    existing = db.query(GroupMember).filter(GroupMember.group_id == group.id, GroupMember.user_id == auth.user.id).first()
    if existing and existing.status == "active":
        raise HTTPException(status_code=409, detail="You're already in this class.")
    _lock_class_quota_user(db, auth.user.id)
    active_count = db.query(GroupMember.id).filter(GroupMember.user_id == auth.user.id, GroupMember.status == "active").count()
    active_limit = _positive_env_limit(
        "BRASSTUNE_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER",
        DEFAULT_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER,
    )
    if active_count >= active_limit:
        raise HTTPException(status_code=409, detail="You have reached the active class limit.")
    now = dt.datetime.utcnow()
    if existing:
        existing.status = "active"
        existing.active_since = now
        existing.removed_at = None
        # A join code always grants ordinary student access. Do not resurrect an
        # elevated role from a removed or stale membership record.
        existing.role_in_group = "student"
        existing.instrument_id = instrument
        member = existing
    else:
        member = GroupMember(group_id=group.id, user_id=auth.user.id, instrument_id=instrument, role_in_group="student", status="active", active_since=now)
        db.add(member)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        # With the (group_id, user_id) uniqueness constraint, another request
        # may have won the join race after our initial lookup. Translate only
        # that verified outcome; unrelated integrity failures still propagate.
        concurrent_membership = (
            db.query(GroupMember)
            .filter(
                GroupMember.group_id == group.id,
                GroupMember.user_id == auth.user.id,
                GroupMember.status == "active",
            )
            .first()
        )
        if concurrent_membership is not None:
            raise HTTPException(status_code=409, detail="You're already in this class.")
        raise
    record_event(db, "invitation_accepted", auth.user.id, {"group_id": group.id, "via": "join_code"})
    return {"joined": True, "group_id": group.id, "group_name": group.name}


@router.delete("/ensemble/groups/{group_id}/membership")
def leave_ensemble_group(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    """Soft-remove only the signed-in user's membership in one class."""
    group = _group_or_404(db, group_id)
    if group.director_user_id == auth.user.id:
        raise HTTPException(status_code=409, detail="The class owner cannot leave their own class.")
    membership = (
        db.query(GroupMember)
        .filter(
            GroupMember.group_id == group_id,
            GroupMember.user_id == auth.user.id,
            GroupMember.status == "active",
        )
        .first()
    )
    if membership is None:
        raise HTTPException(status_code=404, detail="You are not an active member of this class.")
    membership.status = "removed"
    membership.removed_at = dt.datetime.utcnow()
    db.add(membership)
    db.commit()
    record_event(db, "group_left", auth.user.id, {"group_id": group_id})
    return {"left": True, "group_id": group_id}


@router.post("/ensemble/groups/{group_id}/join-code/rotate")
def rotate_ensemble_join_code(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    """Invalidate the previous class code and return a fresh management-only code."""
    group = _require_group_manager(db, group_id, auth)
    previous_code = group.join_code
    for _ in range(4):
        group.join_code = _generate_join_code(db)
        if group.join_code == previous_code:
            continue
        db.add(group)
        try:
            db.commit()
            db.refresh(group)
            record_event(db, "group_join_code_rotated", auth.user.id, {"group_id": group.id})
            return {"group_id": group.id, "join_code": group.join_code}
        except IntegrityError:
            db.rollback()
            group = _require_group_manager(db, group_id, auth)
    raise HTTPException(status_code=503, detail="A new class code could not be created. Try again.")


@router.patch("/ensemble/groups/{group_id}/members/{member_id}")
def update_ensemble_member(group_id: int, member_id: int, payload: UpdateGroupMemberRequest, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_group_manager(db, group_id, auth)
    member = db.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.id == member_id).first()
    if member is None:
        raise HTTPException(status_code=404, detail="Group member not found.")
    if payload.status:
        if payload.status not in {"active", "invited", "removed"}:
            raise HTTPException(status_code=400, detail="Invalid member status.")
        # Activation is always an act of member consent: invitation acceptance or
        # entering a join code. Managers may edit an already-active member, but
        # cannot reactivate invited or removed records.
        if payload.status == "active" and member.status != "active":
            raise HTTPException(status_code=409, detail="The member must activate their membership themselves.")
    if payload.instrument_id:
        _validate_instrument(payload.instrument_id)
        member.instrument_id = payload.instrument_id
    if payload.role_in_group:
        if payload.role_in_group not in {"student", "assistant", "director"}:
            raise HTTPException(status_code=400, detail="Invalid role_in_group.")
        requested_status = payload.status or member.status
        if (
            member.status == "active"
            and requested_status == "active"
            and payload.role_in_group in {"assistant", "director"}
            and payload.role_in_group != member.role_in_group
        ):
            raise HTTPException(
                status_code=409,
                detail="Elevated class access requires a new invitation and member acceptance.",
            )
        member.role_in_group = payload.role_in_group
    if payload.status:
        previous_status = member.status
        member.status = payload.status
        if payload.status in {"invited", "removed"} and previous_status == "active":
            member.removed_at = dt.datetime.utcnow()
    db.add(member)
    db.commit()
    db.refresh(member)
    return group_member_to_dict(db.query(GroupMember).options(joinedload(GroupMember.user)).filter(GroupMember.id == member.id).first())


@router.delete("/ensemble/groups/{group_id}/members/{member_id}")
def remove_ensemble_member(group_id: int, member_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_group_manager(db, group_id, auth)
    member = db.query(GroupMember).filter(GroupMember.group_id == group_id, GroupMember.id == member_id).first()
    if member is None:
        raise HTTPException(status_code=404, detail="Group member not found.")
    member.status = "removed"
    member.removed_at = dt.datetime.utcnow()
    db.add(member)
    db.commit()
    return {"removed": True}


@router.get("/ensemble/groups/{group_id}/summary")
def ensemble_group_summary(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_group_manager(db, group_id, auth)
    sessions = _group_scoped_sessions(db, group_id)
    return calculate_ensemble_summary(group_id, sessions)


@router.get("/ensemble/groups/{group_id}/report")
def ensemble_group_report(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    _require_group_manager(db, group_id, auth)
    sessions = _group_scoped_sessions(db, group_id)
    return generate_rehearsal_report(group_id, sessions)


@router.get("/ensemble/summary")
def ensemble_summary(group_id: int = 1, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    return ensemble_group_summary(group_id, db, auth)


@router.get("/ensemble/report")
def ensemble_report(group_id: int = 1, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    return ensemble_group_report(group_id, db, auth)


def _weighted_mean(pairs):
    total_weight = sum(weight for _, weight in pairs)
    if total_weight <= 0:
        return None
    return sum(value * weight for value, weight in pairs) / total_weight


@router.get("/ensemble/groups/{group_id}/roster")
def ensemble_group_roster(group_id: int, db: Session = Depends(get_db), auth: AuthContext = Depends(get_auth_context)):
    """Per-student practice stats for the ensemble director/admin."""
    _require_group_manager(db, group_id, auth)
    members = (
        db.query(GroupMember)
        .options(joinedload(GroupMember.user))
        .filter(GroupMember.group_id == group_id, GroupMember.status.in_(["active", "invited"]))
        .order_by(GroupMember.created_at.asc())
        .all()
    )
    students = []
    for member in members:
        since = _member_active_since(member)
        sessions = []
        if member.status == "active":
            sessions = (
                db.query(PracticeSession)
                .filter(PracticeSession.user_id == member.user_id, PracticeSession.started_at >= since)
                .all()
            )
        weighted = [(s.average_abs_cents, s.notes_count or 0) for s in sessions if (s.notes_count or 0) > 0]
        intune = [(s.in_tune_percentage, s.notes_count or 0) for s in sessions if (s.notes_count or 0) > 0]
        avg_abs_cents = _weighted_mean(weighted)
        in_tune_pct = _weighted_mean(intune)
        last_practice_at = max((s.started_at for s in sessions), default=None)
        user = member.user
        students.append({
            "member_id": member.id,
            "user_id": member.user_id,
            "username": getattr(user, "username", None),
            "display_name": getattr(user, "display_name", None) or getattr(user, "name", None),
            "instrument_id": member.instrument_id,
            "status": member.status,
            "role_in_group": getattr(member, "role_in_group", "student"),
            "sessions_count": len(sessions),
            "practice_minutes": round(sum(s.duration_seconds or 0.0 for s in sessions) / 60.0, 1),
            "average_abs_cents": round(avg_abs_cents, 1) if avg_abs_cents is not None else None,
            "in_tune_percentage": round(in_tune_pct, 1) if in_tune_pct is not None else None,
            "last_practice_at": iso(last_practice_at),
            # Do not expose a not-yet-accepted (invited) person's activity — only
            # show it once they have consented by accepting.
            "last_active_at": iso(getattr(user, "last_active_at", None)) if member.status == "active" else None,
        })
    return {"group_id": group_id, "students": students}


@router.get("/admin/metrics")
def admin_usage_metrics(db: Session = Depends(get_db), auth: AuthContext = Depends(require_roles("admin"))):
    """Private product-usage dashboard data. Admin-only."""
    now = dt.datetime.utcnow()

    def since(days: int) -> dt.datetime:
        return now - dt.timedelta(days=days)

    def count(model, *conditions) -> int:
        query = db.query(func.count(model.id))
        for condition in conditions:
            query = query.filter(condition)
        return int(query.scalar() or 0)

    event_rows = (
        db.query(UsageEvent.event_name, func.count(UsageEvent.id))
        .filter(UsageEvent.created_at >= since(30))
        .group_by(UsageEvent.event_name)
        .all()
    )
    signup_rows = (
        db.query(func.date(User.created_at), func.count(User.id))
        .filter(User.created_at >= since(14))
        .group_by(func.date(User.created_at))
        .all()
    )
    return {
        "generated_at": iso(now),
        "totals": {
            "users": count(User),
            "sessions": count(PracticeSession),
            "ensembles": count(Group),
        },
        "new_users": {"last_7d": count(User, User.created_at >= since(7)), "last_30d": count(User, User.created_at >= since(30))},
        "active_users": {
            "dau": count(User, User.last_active_at >= since(1)),
            "wau": count(User, User.last_active_at >= since(7)),
            "mau": count(User, User.last_active_at >= since(30)),
        },
        "sessions": {"last_7d": count(PracticeSession, PracticeSession.started_at >= since(7)), "last_30d": count(PracticeSession, PracticeSession.started_at >= since(30))},
        "events_30d": {name: int(total) for name, total in event_rows},
        "signups_by_day": [{"date": str(day), "count": int(total)} for day, total in sorted(signup_rows, key=lambda row: str(row[0]))],
    }
