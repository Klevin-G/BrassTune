import datetime as dt
import math
import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.instruments.profiles import require_instrument_profile
from app.core.music.theory import MIN_RECORDING_CONFIDENCE, frequency_to_pitch_frame, transpose_concert_to_written
from app.core.sessions.segmentation import compute_session_summary, segment_note_events
from app.models.db import NoteEvent, PitchSample, PracticeSession, User
from app.services.account_mutation import account_mutation_guard, assert_account_accepts_mutation
from app.services.serializers import sample_to_frame_dict, session_to_dict


MAX_CLIENT_CLOCK_SKEW = dt.timedelta(minutes=5)
MAX_CLIENT_SESSION_DURATION = dt.timedelta(hours=24)
MIN_CLIENT_SYNC_TIMESTAMP = dt.datetime(2000, 1, 1)


@dataclass
class PitchFrameSaveResult:
    saved_samples: List[PitchSample] = field(default_factory=list)
    replayed_samples: List[PitchSample] = field(default_factory=list)
    rejected: int = 0

    @property
    def accepted_samples(self) -> List[PitchSample]:
        return self.saved_samples + self.replayed_samples


def _client_utc_naive(value: Optional[dt.datetime], field_name: str) -> Optional[dt.datetime]:
    if value is None:
        return None
    if value.tzinfo is None or value.utcoffset() is None:
        raise HTTPException(status_code=400, detail="%s must include a UTC offset." % field_name)
    normalized = value.astimezone(dt.timezone.utc).replace(tzinfo=None)
    if normalized < MIN_CLIENT_SYNC_TIMESTAMP:
        raise HTTPException(status_code=400, detail="%s is outside the supported sync window." % field_name)
    if normalized > dt.datetime.utcnow() + MAX_CLIENT_CLOCK_SKEW:
        raise HTTPException(status_code=400, detail="%s is too far in the future." % field_name)
    return normalized


def _float_matches(left: object, right: object) -> bool:
    return math.isclose(float(left or 0), float(right or 0), rel_tol=1e-9, abs_tol=1e-9)


def _timestamp_matches(left: dt.datetime, right: dt.datetime) -> bool:
    return abs((_utc_naive(left) - _utc_naive(right)).total_seconds()) < 0.001


def _assert_start_replay_matches(
    session: PracticeSession,
    *,
    instrument_id: str,
    name: str,
    reference_pitch_hz: float,
    started_at: Optional[dt.datetime],
) -> None:
    matches = (
        session.instrument_id == instrument_id
        and session.name == name
        and _float_matches(session.reference_pitch_hz, reference_pitch_hz)
        and (started_at is None or _timestamp_matches(session.started_at, started_at))
    )
    if not matches:
        raise HTTPException(
            status_code=409,
            detail="client_session_id was already used with different session data.",
        )


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if value >= 0 else default


def _utc_naive(value: dt.datetime) -> dt.datetime:
    """Return a UTC wall-clock value that is safe to compare across DB backends.

    SQLite returns the app's historical naive timestamps unchanged, while the
    Supabase/PostgreSQL ``timestamptz`` columns are returned as UTC-aware
    values.  Session finalization may receive either representation during the
    staged migration period, so normalize only at the arithmetic boundary.
    """
    if value.tzinfo is None:
        return value
    return value.astimezone(dt.timezone.utc).replace(tzinfo=None)


def get_or_create_default_user(db: Session) -> User:
    user = db.query(User).filter(User.id == 1).first()
    if user:
        changed = False
        if not user.username:
            user.username = "avery"
            changed = True
        if not user.display_name:
            user.display_name = user.name
            changed = True
        if changed:
            db.add(user)
            db.commit()
            db.refresh(user)
        return user
    user = User(id=1, username="avery", name="Avery Brass", display_name="Avery Brass", role="student", primary_instrument_id="trumpet")
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def start_session_with_replay(
    db: Session,
    instrument_id: str,
    name: Optional[str],
    reference_pitch_hz: float,
    user_id: int = 1,
    *,
    client_session_id: Optional[str] = None,
    started_at: Optional[dt.datetime] = None,
) -> tuple[PracticeSession, bool]:
    normalized_started_at = _client_utc_naive(started_at, "started_at")
    with account_mutation_guard(db, user_id):
        profile = require_instrument_profile(instrument_id)
        # Keep the existing row lock inside the cross-commit account guard. The
        # row lock protects quota decisions within this transaction; the
        # advisory/process guard also excludes deletion and audio replacement.
        user = db.query(User).filter(User.id == user_id).with_for_update().first()
        if user is None:
            raise HTTPException(status_code=404, detail="Account not found.")
        assert_account_accepts_mutation(db, user.id)
        session_name = name or "%s practice" % profile.display_name
        if client_session_id is not None:
            existing = (
                db.query(PracticeSession)
                .filter(
                    PracticeSession.user_id == user.id,
                    PracticeSession.client_session_id == client_session_id,
                )
                .first()
            )
            if existing is not None:
                _assert_start_replay_matches(
                    existing,
                    instrument_id=instrument_id,
                    name=session_name,
                    reference_pitch_hz=reference_pitch_hz,
                    started_at=normalized_started_at,
                )
                return existing, True
        max_sessions = _positive_int_env("BRASSTUNE_MAX_SESSIONS_PER_USER", 5000)
        if max_sessions:
            session_count = int(
                db.query(func.count(PracticeSession.id))
                .filter(PracticeSession.user_id == user.id)
                .scalar()
                or 0
            )
            if session_count >= max_sessions:
                raise HTTPException(
                    status_code=409,
                    detail="Session storage limit reached. Delete old cloud sessions before starting another.",
                )
        # A mode switch or dropped client must not leave overlapping active
        # sessions. Finalize any stranded session in the same owner-locked
        # transaction before creating its replacement.
        active_sessions = (
            db.query(PracticeSession)
            .filter(
                PracticeSession.user_id == user.id,
                PracticeSession.ended_at.is_(None),
            )
            .with_for_update()
            .all()
        )
        ended_at = dt.datetime.utcnow()
        for active_session in active_sessions:
            _finalize_session(db, active_session, ended_at=ended_at)
        session = PracticeSession(
            user_id=user.id,
            client_session_id=client_session_id,
            instrument_id=instrument_id,
            name=session_name,
            reference_pitch_hz=reference_pitch_hz,
            started_at=normalized_started_at or dt.datetime.utcnow(),
        )
        db.add(session)
        db.commit()
        db.refresh(session)
        return session, False


def start_session(
    db: Session,
    instrument_id: str,
    name: Optional[str],
    reference_pitch_hz: float,
    user_id: int = 1,
    *,
    client_session_id: Optional[str] = None,
    started_at: Optional[dt.datetime] = None,
) -> PracticeSession:
    session, _ = start_session_with_replay(
        db,
        instrument_id,
        name,
        reference_pitch_hz,
        user_id,
        client_session_id=client_session_id,
        started_at=started_at,
    )
    return session


def save_pitch_frame(db: Session, session_id: int, frame: Dict[str, object]) -> Optional[PitchSample]:
    result = save_pitch_frames_detailed(db, session_id, [frame])
    return result.accepted_samples[0] if result.accepted_samples else None


def _sample_from_frame(session: PracticeSession, frame: Dict[str, object]) -> Optional[PitchSample]:
    if str(frame.get("instrument_id") or session.instrument_id) != session.instrument_id:
        return None
    confidence = float(frame.get("confidence") or 0)
    if confidence < MIN_RECORDING_CONFIDENCE:
        return None
    frequency_hz = frame.get("frequency_hz")
    if frequency_hz is None:
        return None
    canonical = frequency_to_pitch_frame(
        float(frequency_hz),
        confidence,
        float(frame.get("rms") or 0),
        int(frame.get("timestamp_ms") or 0),
        session.instrument_id,
        float(session.reference_pitch_hz or 440.0),
        str(frame.get("detector_source") or "backend-canonicalized"),
    )
    if not canonical.is_valid_for_recording or canonical.nearest_midi is None or canonical.cents_deviation is None:
        return None
    written_midi = transpose_concert_to_written(canonical.nearest_midi, require_instrument_profile(session.instrument_id))
    return PitchSample(
        session_id=session.id,
        client_frame_index=frame.get("client_frame_index"),
        timestamp_ms=canonical.timestamp_ms,
        frequency_hz=float(canonical.frequency_hz or 0),
        confidence=canonical.confidence,
        rms=canonical.rms,
        concert_midi_float=float(canonical.midi_note_float or canonical.nearest_midi),
        concert_nearest_midi=canonical.nearest_midi,
        concert_note=str(canonical.concert_note_name or ""),
        concert_octave=int(canonical.concert_octave or 0),
        written_midi=written_midi,
        written_note=str(canonical.written_note_name or ""),
        written_octave=int(canonical.written_octave or 0),
        cents_deviation=float(canonical.cents_deviation),
        tuning_status=canonical.tuning_status,
        is_valid_for_recording=1,
    )


def _pitch_sample_matches(left: PitchSample, right: PitchSample) -> bool:
    exact_fields = (
        "client_frame_index",
        "timestamp_ms",
        "concert_nearest_midi",
        "concert_note",
        "concert_octave",
        "written_midi",
        "written_note",
        "written_octave",
        "tuning_status",
        "is_valid_for_recording",
    )
    float_fields = (
        "frequency_hz",
        "confidence",
        "rms",
        "concert_midi_float",
        "cents_deviation",
    )
    return all(getattr(left, key) == getattr(right, key) for key in exact_fields) and all(
        _float_matches(getattr(left, key), getattr(right, key)) for key in float_fields
    )


def save_pitch_frames_detailed(
    db: Session,
    session_id: int,
    frames: List[Dict[str, object]],
) -> PitchFrameSaveResult:
    owner_id = db.query(PracticeSession.user_id).filter(PracticeSession.id == session_id).scalar()
    if owner_id is None:
        return PitchFrameSaveResult(rejected=len(frames))
    with account_mutation_guard(db, int(owner_id)):
        return _save_pitch_frames_locked(db, session_id, frames)


def _save_pitch_frames_locked(
    db: Session,
    session_id: int,
    frames: List[Dict[str, object]],
) -> PitchFrameSaveResult:
    # Serialize sample persistence with stop/finalization on PostgreSQL. The
    # winner commits first; the other operation then observes the durable
    # active/ended state instead of inserting after completion.
    session = (
        db.query(PracticeSession)
        # WebSocket connections intentionally keep this Session open. Replace a
        # previously cached row before the lock/ended check so an HTTP stop in a
        # different Session cannot be followed by stale pitch inserts.
        .populate_existing()
        .filter(PracticeSession.id == session_id)
        .with_for_update()
        .first()
    )
    if session is None:
        return PitchFrameSaveResult(rejected=len(frames))
    frame_indices = {
        int(frame["client_frame_index"])
        for frame in frames
        if frame.get("client_frame_index") is not None
    }
    existing_by_index = {
        int(sample.client_frame_index): sample
        for sample in (
            db.query(PitchSample)
            .filter(
                PitchSample.session_id == session.id,
                PitchSample.client_frame_index.in_(frame_indices),
            )
            .all()
            if frame_indices
            else []
        )
    }
    pending_by_index: Dict[int, PitchSample] = {}
    result = PitchFrameSaveResult()
    for frame in frames:
        sample = _sample_from_frame(session, frame)
        client_frame_index = frame.get("client_frame_index")
        prior = None
        if client_frame_index is not None:
            index = int(client_frame_index)
            prior = existing_by_index.get(index) or pending_by_index.get(index)
        if sample is None:
            if prior is not None:
                raise HTTPException(
                    status_code=409,
                    detail="client_frame_index was already used with different pitch data.",
                )
            result.rejected += 1
            continue
        if prior is not None:
            if not _pitch_sample_matches(prior, sample):
                raise HTTPException(
                    status_code=409,
                    detail="client_frame_index was already used with different pitch data.",
                )
            result.replayed_samples.append(prior)
            continue
        result.saved_samples.append(sample)
        if client_frame_index is not None:
            pending_by_index[int(client_frame_index)] = sample
    if session.ended_at is not None:
        if result.saved_samples:
            raise HTTPException(
                status_code=409,
                detail="Practice session has already ended; only exact durable frame replays are accepted.",
            )
        return result
    if not result.saved_samples:
        return result
    # Live recording can send many frames per second. Batch insert keeps SQLite
    # responsive while the single-frame endpoint remains convenient for demo mode.
    db.add_all(result.saved_samples)
    db.commit()
    for sample in result.saved_samples:
        db.refresh(sample)
    return result


def save_pitch_frames(db: Session, session_id: int, frames: List[Dict[str, object]]) -> List[PitchSample]:
    return save_pitch_frames_detailed(db, session_id, frames).accepted_samples


def _replace_note_events(db: Session, session: PracticeSession) -> List[NoteEvent]:
    db.query(NoteEvent).filter(NoteEvent.session_id == session.id).delete()
    db.flush()
    samples = db.query(PitchSample).filter(PitchSample.session_id == session.id).order_by(PitchSample.timestamp_ms.asc()).all()
    frames = [sample_to_frame_dict(sample) for sample in samples]
    stats = segment_note_events(frames)
    events: List[NoteEvent] = []
    for item in stats:
        event = NoteEvent(
            session_id=session.id,
            instrument_id=str(item["instrument_id"]),
            written_note=str(item["written_note"]),
            written_octave=int(item["written_octave"]),
            concert_note=str(item["concert_note"]),
            concert_octave=int(item["concert_octave"]),
            started_at_ms=int(item["started_at_ms"]),
            ended_at_ms=int(item["ended_at_ms"]),
            duration_ms=int(item["duration_ms"]),
            sample_count=int(item["sample_count"]),
            avg_signed_cents=float(item["avg_signed_cents"]),
            avg_abs_cents=float(item["avg_abs_cents"]),
            median_cents=float(item["median_cents"]),
            stddev_cents=float(item["stddev_cents"]),
            min_cents=float(item["min_cents"]),
            max_cents=float(item["max_cents"]),
            in_tune_percentage=float(item["in_tune_percentage"]),
            stability_score=float(item["stability_score"]),
        )
        db.add(event)
        events.append(event)
    return events


def rebuild_note_events(db: Session, session: PracticeSession) -> List[NoteEvent]:
    events = _replace_note_events(db, session)
    db.commit()
    for event in events:
        db.refresh(event)
    return events


def _finalize_session(
    db: Session,
    session: PracticeSession,
    *,
    ended_at: Optional[dt.datetime] = None,
) -> PracticeSession:
    session.ended_at = ended_at or dt.datetime.utcnow()
    events = _replace_note_events(db, session)
    summary = compute_session_summary(
        [
            {
                "duration_ms": event.duration_ms,
                "avg_signed_cents": event.avg_signed_cents,
                "avg_abs_cents": event.avg_abs_cents,
                "in_tune_percentage": event.in_tune_percentage,
            }
            for event in events
        ]
    )
    if events:
        session.duration_seconds = float(summary["duration_seconds"])
    else:
        session.duration_seconds = max(
            0.0,
            (_utc_naive(session.ended_at) - _utc_naive(session.started_at)).total_seconds(),
        )
    session.notes_count = int(summary["notes_count"])
    session.average_signed_cents = float(summary["average_signed_cents"])
    session.average_abs_cents = float(summary["average_abs_cents"])
    session.in_tune_percentage = float(summary["in_tune_percentage"])
    db.add(session)
    return session


def stop_session_with_replay(
    db: Session,
    session_id: int,
    *,
    client_session_id: Optional[str] = None,
    ended_at: Optional[dt.datetime] = None,
) -> tuple[Optional[PracticeSession], bool]:
    owner_id = db.query(PracticeSession.user_id).filter(PracticeSession.id == session_id).scalar()
    if owner_id is None:
        return None, False
    normalized_ended_at = _client_utc_naive(ended_at, "ended_at")
    with account_mutation_guard(db, int(owner_id)):
        return _stop_session_locked(
            db,
            session_id,
            client_session_id=client_session_id,
            ended_at=normalized_ended_at,
        )


def _stop_session_locked(
    db: Session,
    session_id: int,
    *,
    client_session_id: Optional[str],
    ended_at: Optional[dt.datetime],
) -> tuple[Optional[PracticeSession], bool]:
    session = (
        db.query(PracticeSession)
        # Disconnect cleanup may reuse a WebSocket's long-lived Session after
        # HTTP has already finalized this row. Refresh first so an idempotent
        # stop never overwrites the original completion timestamp or summary.
        .populate_existing()
        .filter(PracticeSession.id == session_id)
        .with_for_update()
        .first()
    )
    if session is None:
        return None, False
    if client_session_id is not None and session.client_session_id != client_session_id:
        raise HTTPException(status_code=409, detail="client_session_id does not match this practice session.")
    if session.ended_at is not None:
        if ended_at is not None and not _timestamp_matches(session.ended_at, ended_at):
            raise HTTPException(status_code=409, detail="Practice session was already stopped with a different ended_at.")
        return session, True
    final_ended_at = ended_at or dt.datetime.utcnow()
    started_at = _utc_naive(session.started_at)
    if final_ended_at < started_at:
        raise HTTPException(status_code=409, detail="ended_at cannot be earlier than started_at.")
    if ended_at is not None and final_ended_at - started_at > MAX_CLIENT_SESSION_DURATION:
        raise HTTPException(status_code=400, detail="Practice sessions cannot exceed 24 hours.")
    _finalize_session(db, session, ended_at=final_ended_at)
    db.commit()
    db.refresh(session)
    return session, False


def stop_session(
    db: Session,
    session_id: int,
    *,
    client_session_id: Optional[str] = None,
    ended_at: Optional[dt.datetime] = None,
) -> Optional[PracticeSession]:
    session, _ = stop_session_with_replay(
        db,
        session_id,
        client_session_id=client_session_id,
        ended_at=ended_at,
    )
    return session


def session_payload(session: PracticeSession) -> Dict[str, object]:
    return session_to_dict(session)
