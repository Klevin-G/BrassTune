import json
from typing import Dict

from sqlalchemy.orm import Session

from app.db.seed import seed_demo_data
from app.models.db import Group, GroupMember, InstrumentProfileModel, NoteEvent, PitchSample, PracticeSession, User
from app.services.audio_storage import delete_audio_for_session
from app.services.serializers import event_to_dict, sample_to_dict, session_to_dict


def clear_practice_data(db: Session) -> Dict[str, int]:
    sessions = db.query(PracticeSession).all()
    counts = {
        "note_events": db.query(NoteEvent).count(),
        "pitch_samples": db.query(PitchSample).count(),
        "practice_sessions": len(sessions),
    }
    for session in sessions:
        delete_audio_for_session(session)
    db.query(NoteEvent).delete()
    db.query(PitchSample).delete()
    db.query(PracticeSession).delete()
    db.commit()
    return counts


def demo_data_needs_repair(db: Session) -> bool:
    sessions = db.query(PracticeSession).all()
    if not sessions:
        return True
    if db.query(PitchSample).count() == 0 or db.query(NoteEvent).count() == 0:
        return True
    for session in sessions:
        has_samples = db.query(PitchSample).filter(PitchSample.session_id == session.id).first() is not None
        has_events = db.query(NoteEvent).filter(NoteEvent.session_id == session.id).first() is not None
        if not has_samples or not has_events:
            return True
    return False


def repair_demo_data(db: Session) -> Dict[str, object]:
    if not demo_data_needs_repair(db):
        return {"repaired": False, "reason": "Demo data already has sessions, samples, and note events."}
    cleared = clear_practice_data(db)
    seed_demo_data(db)
    return {"repaired": True, "cleared": cleared, "sessions": db.query(PracticeSession).count()}


def reset_demo_data(db: Session) -> Dict[str, object]:
    cleared = clear_practice_data(db)
    seed_demo_data(db)
    return {"reset": True, "cleared": cleared, "sessions": db.query(PracticeSession).count()}


def export_all_data(db: Session) -> str:
    payload = {
        "users": [
            {"id": row.id, "name": row.name, "role": row.role, "primary_instrument_id": row.primary_instrument_id, "created_at": row.created_at.isoformat()}
            for row in db.query(User).order_by(User.id.asc()).all()
        ],
        "instrument_profiles": [
            {
                "id": row.id,
                "name": row.name,
                "transposition_semitones": row.transposition_semitones,
                "min_frequency_hz": row.min_frequency_hz,
                "max_frequency_hz": row.max_frequency_hz,
                "metadata": json.loads(row.metadata_json or "{}"),
            }
            for row in db.query(InstrumentProfileModel).order_by(InstrumentProfileModel.id.asc()).all()
        ],
        "groups": [{"id": row.id, "name": row.name, "director_user_id": row.director_user_id} for row in db.query(Group).order_by(Group.id.asc()).all()],
        "group_members": [
            {"id": row.id, "group_id": row.group_id, "user_id": row.user_id, "instrument_id": row.instrument_id}
            for row in db.query(GroupMember).order_by(GroupMember.id.asc()).all()
        ],
        "sessions": [session_to_dict(row) for row in db.query(PracticeSession).order_by(PracticeSession.started_at.asc()).all()],
        "samples": [sample_to_dict(row) for row in db.query(PitchSample).order_by(PitchSample.session_id.asc(), PitchSample.timestamp_ms.asc()).all()],
        "note_events": [event_to_dict(row) for row in db.query(NoteEvent).order_by(NoteEvent.session_id.asc(), NoteEvent.started_at_ms.asc()).all()],
    }
    return json.dumps(payload, indent=2)
