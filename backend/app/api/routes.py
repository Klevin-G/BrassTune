import csv
import datetime as dt
import io
import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session, joinedload

from app.core.analytics.stats import build_heatmap, build_instrument_heatmap, calculate_note_stats, calculate_period_bounds, calculate_progress_metrics
from app.core.ensemble.analytics import calculate_ensemble_summary, generate_rehearsal_report
from app.core.instruments.profiles import get_all_profiles, get_instrument_profile, is_valid_instrument_id, require_instrument_profile
from app.core.recommendations.rules import generate_practice_plan, generate_recommendations, generate_session_recommendations
from app.db.database import get_db
from app.models.db import GroupMember, NoteEvent, PitchSample, PracticeSession, User
from app.schemas.schemas import PitchFrameIn, StartSessionRequest
from app.services.serializers import event_to_dict, sample_to_dict, session_to_dict
from app.services.session_service import save_pitch_frame, start_session, stop_session

router = APIRouter(prefix="/api")


def _bad_instrument(instrument_id: str) -> HTTPException:
    return HTTPException(status_code=400, detail="Unknown instrument_id: %s" % instrument_id)


def _validate_instrument(instrument_id: str) -> None:
    if not is_valid_instrument_id(instrument_id):
        raise _bad_instrument(instrument_id)


def _validate_optional_instrument(instrument_id: Optional[str]) -> None:
    if instrument_id:
        _validate_instrument(instrument_id)


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


@router.get("/health")
def health():
    return {"ok": True, "service": "BrassTune Analytics API"}


@router.get("/instruments")
def instruments():
    return [profile.to_dict() for profile in get_all_profiles()]


@router.get("/users/current")
def current_user(db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == 1).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Default local user was not seeded.")
    return {"id": user.id, "name": user.name, "role": user.role, "primary_instrument_id": user.primary_instrument_id, "created_at": user.created_at.isoformat()}


@router.post("/sessions/start")
def start_practice_session(payload: StartSessionRequest, db: Session = Depends(get_db)):
    _validate_instrument(payload.instrument_id)
    session = start_session(db, payload.instrument_id, payload.name, payload.reference_pitch_hz, payload.user_id)
    return session_to_dict(session)


@router.post("/sessions/{session_id}/samples")
def add_session_sample(session_id: int, frame: PitchFrameIn, db: Session = Depends(get_db)):
    _validate_instrument(frame.instrument_id)
    sample = save_pitch_frame(db, session_id, frame.dict())
    if sample is None:
        return {"saved": False, "reason": "Frame was invalid, silent, or session was not found."}
    return {"saved": True, "sample": sample_to_dict(sample)}


@router.post("/sessions/{session_id}/stop")
def stop_practice_session(session_id: int, db: Session = Depends(get_db)):
    session = stop_session(db, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return session_to_dict(session)


@router.get("/sessions")
def list_sessions(db: Session = Depends(get_db)):
    rows = db.query(PracticeSession).order_by(PracticeSession.started_at.desc()).all()
    return [session_to_dict(row) for row in rows]


@router.get("/sessions/{session_id}")
def get_session(session_id: int, db: Session = Depends(get_db)):
    session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return {
        **session_to_dict(session),
        "samples_count": db.query(PitchSample).filter(PitchSample.session_id == session_id).count(),
        "note_events": [event_to_dict(event) for event in db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()],
    }


@router.get("/sessions/{session_id}/samples")
def get_samples(session_id: int, db: Session = Depends(get_db)):
    samples = db.query(PitchSample).filter(PitchSample.session_id == session_id).order_by(PitchSample.timestamp_ms.asc()).all()
    return [sample_to_dict(sample) for sample in samples]


@router.get("/sessions/{session_id}/note-events")
def get_note_events(session_id: int, db: Session = Depends(get_db)):
    events = db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()
    return [event_to_dict(event) for event in events]


@router.get("/sessions/{session_id}/analytics")
def get_session_analytics(session_id: int, db: Session = Depends(get_db)):
    session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    events = db.query(NoteEvent).filter(NoteEvent.session_id == session_id).all()
    note_stats = calculate_note_stats([event_to_dict(event) for event in events])
    profile = get_instrument_profile(session.instrument_id)
    recommendations = generate_session_recommendations(session_to_dict(session), note_stats)
    return {"session": session_to_dict(session), "note_stats": note_stats, "heatmap": build_instrument_heatmap(note_stats, profile), "recommendations": recommendations, "instrument": profile.to_dict()}


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
):
    _validate_optional_instrument(instrument_id)
    parsed_from = _parse_date_start(date_from, "date_from")
    parsed_to = _parse_date_end(date_to, "date_to")
    events = _filtered_events(db, user_id, instrument_id, parsed_from, parsed_to)
    return calculate_note_stats([event_to_dict(event) for event in events])


@router.get("/analytics/progress")
def analytics_progress(
    user_id: int = 1,
    instrument_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: Session = Depends(get_db),
):
    _validate_optional_instrument(instrument_id)
    parsed_from = _parse_date_start(date_from, "date_from")
    parsed_to = _parse_date_end(date_to, "date_to")
    sessions = _filtered_sessions(db, user_id, instrument_id, parsed_from, parsed_to)
    period = calculate_period_bounds(parsed_from, parsed_to)
    current_events = _filtered_events(db, user_id, instrument_id, period["current_start"], period["current_end"])
    previous_events = _filtered_events(db, user_id, instrument_id, period["previous_start"], period["previous_end"])
    current_stats = calculate_note_stats([event_to_dict(event) for event in current_events])
    previous_stats = calculate_note_stats([event_to_dict(event) for event in previous_events])
    payload = calculate_progress_metrics(user_id, sessions, current_stats, previous_stats)
    payload["period"] = {key: value.isoformat() for key, value in period.items()}
    return payload


@router.get("/analytics/heatmap")
def analytics_heatmap(
    user_id: int = 1,
    instrument_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    db: Session = Depends(get_db),
):
    _validate_optional_instrument(instrument_id)
    parsed_from = _parse_date_start(date_from, "date_from")
    parsed_to = _parse_date_end(date_to, "date_to")
    events = _filtered_events(db, user_id, instrument_id, parsed_from, parsed_to)
    stats = calculate_note_stats([event_to_dict(event) for event in events])
    if instrument_id:
        return build_instrument_heatmap(stats, require_instrument_profile(instrument_id))
    return build_heatmap(stats)


@router.get("/recommendations")
def recommendations(user_id: int = 1, instrument_id: str = "trumpet", db: Session = Depends(get_db)):
    _validate_instrument(instrument_id)
    events = _filtered_events(db, user_id, instrument_id)
    stats = calculate_note_stats([event_to_dict(event) for event in events])
    return generate_recommendations(stats, get_instrument_profile(instrument_id))


@router.get("/practice-plan")
def practice_plan(user_id: int = 1, instrument_id: str = "trumpet", db: Session = Depends(get_db)):
    _validate_instrument(instrument_id)
    events = _filtered_events(db, user_id, instrument_id)
    stats = calculate_note_stats([event_to_dict(event) for event in events])
    problem_notes = sorted(stats, key=lambda row: float(row.get("problem_severity", 0)), reverse=True)
    return generate_practice_plan(problem_notes, get_instrument_profile(instrument_id))


@router.get("/export/session/{session_id}.csv")
def export_session_csv(session_id: int, db: Session = Depends(get_db)):
    samples = db.query(PitchSample).filter(PitchSample.session_id == session_id).order_by(PitchSample.timestamp_ms.asc()).all()
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=["timestamp_ms", "frequency_hz", "confidence", "rms", "concert_note", "concert_octave", "written_note", "written_octave", "cents_deviation", "tuning_status"])
    writer.writeheader()
    for sample in samples:
        data = sample_to_dict(sample)
        writer.writerow({key: data[key] for key in writer.fieldnames})
    return Response(output.getvalue(), media_type="text/csv", headers={"Content-Disposition": "attachment; filename=session-%s-samples.csv" % session_id})


@router.get("/export/session/{session_id}.json")
def export_session_json(session_id: int, db: Session = Depends(get_db)):
    session = db.query(PracticeSession).filter(PracticeSession.id == session_id).first()
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    payload = {
        "session": session_to_dict(session),
        "samples": [sample_to_dict(sample) for sample in db.query(PitchSample).filter(PitchSample.session_id == session_id).order_by(PitchSample.timestamp_ms.asc()).all()],
        "note_events": [event_to_dict(event) for event in db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()],
    }
    return Response(json.dumps(payload, indent=2), media_type="application/json", headers={"Content-Disposition": "attachment; filename=session-%s.json" % session_id})


@router.get("/export/note-events/{session_id}.csv")
def export_note_events_csv(session_id: int, db: Session = Depends(get_db)):
    events = db.query(NoteEvent).filter(NoteEvent.session_id == session_id).order_by(NoteEvent.started_at_ms.asc()).all()
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=["note_label", "duration_ms", "sample_count", "avg_signed_cents", "avg_abs_cents", "median_cents", "stddev_cents", "in_tune_percentage", "stability_score"])
    writer.writeheader()
    for event in events:
        data = event_to_dict(event)
        writer.writerow({key: data[key] for key in writer.fieldnames})
    return Response(output.getvalue(), media_type="text/csv", headers={"Content-Disposition": "attachment; filename=session-%s-note-events.csv" % session_id})


@router.get("/ensemble/summary")
def ensemble_summary(group_id: int = 1, db: Session = Depends(get_db)):
    member_ids = [member.user_id for member in db.query(GroupMember).filter(GroupMember.group_id == group_id).all()]
    sessions = db.query(PracticeSession).options(joinedload(PracticeSession.note_events)).filter(PracticeSession.user_id.in_(member_ids)).all()
    return calculate_ensemble_summary(group_id, sessions)


@router.get("/ensemble/report")
def ensemble_report(group_id: int = 1, db: Session = Depends(get_db)):
    member_ids = [member.user_id for member in db.query(GroupMember).filter(GroupMember.group_id == group_id).all()]
    sessions = db.query(PracticeSession).options(joinedload(PracticeSession.note_events)).filter(PracticeSession.user_id.in_(member_ids)).all()
    return generate_rehearsal_report(group_id, sessions)
