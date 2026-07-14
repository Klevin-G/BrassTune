import datetime as dt
import os
from typing import Dict, List, Optional

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.instruments.profiles import require_instrument_profile
from app.core.music.theory import MIN_RECORDING_CONFIDENCE, frequency_to_pitch_frame, transpose_concert_to_written
from app.core.sessions.segmentation import compute_session_summary, segment_note_events
from app.models.db import NoteEvent, PitchSample, PracticeSession, User
from app.services.serializers import sample_to_frame_dict, session_to_dict


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except (TypeError, ValueError):
        return default
    return value if value >= 0 else default


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


def start_session(db: Session, instrument_id: str, name: Optional[str], reference_pitch_hz: float, user_id: int = 1) -> PracticeSession:
    profile = require_instrument_profile(instrument_id)
    # Lock the owner row so concurrent HTTP/WebSocket starts for one account
    # serialize around the quota check on PostgreSQL.
    user = db.query(User).filter(User.id == user_id).with_for_update().first() or get_or_create_default_user(db)
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
    session = PracticeSession(
        user_id=user.id,
        instrument_id=instrument_id,
        name=name or "%s practice" % profile.display_name,
        reference_pitch_hz=reference_pitch_hz,
        started_at=dt.datetime.utcnow(),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


def save_pitch_frame(db: Session, session_id: int, frame: Dict[str, object]) -> Optional[PitchSample]:
    samples = save_pitch_frames(db, session_id, [frame])
    return samples[0] if samples else None


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


def save_pitch_frames(db: Session, session_id: int, frames: List[Dict[str, object]]) -> List[PitchSample]:
    session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
    if session is None:
        return []
    samples = []
    for frame in frames:
        sample = _sample_from_frame(session, frame)
        if sample is not None:
            samples.append(sample)
    if not samples:
        return []
    # Live recording can send many frames per second. Batch insert keeps SQLite
    # responsive while the single-frame endpoint remains convenient for demo mode.
    db.add_all(samples)
    db.commit()
    for sample in samples:
        db.refresh(sample)
    return samples


def rebuild_note_events(db: Session, session: PracticeSession) -> List[NoteEvent]:
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
    db.commit()
    for event in events:
        db.refresh(event)
    return events


def stop_session(db: Session, session_id: int) -> Optional[PracticeSession]:
    session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
    if session is None:
        return None
    session.ended_at = dt.datetime.utcnow()
    events = rebuild_note_events(db, session)
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
        session.duration_seconds = max(0.0, (session.ended_at - session.started_at).total_seconds())
    session.notes_count = int(summary["notes_count"])
    session.average_signed_cents = float(summary["average_signed_cents"])
    session.average_abs_cents = float(summary["average_abs_cents"])
    session.in_tune_percentage = float(summary["in_tune_percentage"])
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


def session_payload(session: PracticeSession) -> Dict[str, object]:
    return session_to_dict(session)
