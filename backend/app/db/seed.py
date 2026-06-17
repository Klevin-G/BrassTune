import datetime as dt
import json
import random
from typing import Dict, List, Tuple

from sqlalchemy.orm import Session

from app.core.instruments.profiles import get_all_profiles, get_instrument_profile
from app.core.music.theory import MIN_RECORDING_CONFIDENCE, frequency_to_pitch_frame, midi_to_frequency
from app.models.db import Group, GroupMember, InstrumentProfileModel, PracticeSession, User
from app.services.session_service import rebuild_note_events, save_pitch_frame, stop_session

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "D#": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "Ab": 8, "G#": 8, "A": 9, "Bb": 10, "A#": 10, "B": 11}
DEMO_RECORDING_CONFIDENCE = max(MIN_RECORDING_CONFIDENCE, 0.97)


def note_to_midi(label: str) -> int:
    if len(label) >= 2 and label[1] in ("#", "b"):
        note = label[:2]
        octave = int(label[2:])
    else:
        note = label[:1]
        octave = int(label[1:])
    return (octave + 1) * 12 + NOTE_INDEX[note]


def upsert_instrument_profiles(db: Session) -> None:
    for profile in get_all_profiles():
        row = db.query(InstrumentProfileModel).filter(InstrumentProfileModel.id == profile.id).first()
        metadata = profile.to_dict()
        if row is None:
            row = InstrumentProfileModel(id=profile.id)
            db.add(row)
        row.name = profile.display_name
        row.transposition_semitones = profile.transposition_semitones
        row.min_frequency_hz = profile.min_frequency_hz
        row.max_frequency_hz = profile.max_frequency_hz
        row.metadata_json = json.dumps(metadata)
    db.commit()


def ensure_users_and_group(db: Session) -> None:
    users = [
        User(id=1, username="avery", name="Avery Brass", display_name="Avery Brass", role="student", primary_instrument_id="trumpet"),
        User(id=2, username="jordan", name="Jordan Reed", display_name="Jordan Reed", role="director", primary_instrument_id="trombone"),
        User(id=3, username="maya", name="Maya Chen", display_name="Maya Chen", role="student", primary_instrument_id="horn"),
        User(id=4, username="luis", name="Luis Martin", display_name="Luis Martin", role="student", primary_instrument_id="trombone"),
        User(id=5, username="sam", name="Sam Rivera", display_name="Sam Rivera", role="student", primary_instrument_id="tuba"),
    ]
    for user in users:
        existing = db.query(User).filter(User.id == user.id).first()
        if existing is None:
            db.add(user)
        else:
            existing.username = existing.username or user.username
            existing.display_name = existing.display_name or user.display_name
    db.commit()
    group = db.query(Group).filter(Group.id == 1).first()
    if group is None:
        group = Group(id=1, name="Central Wind Ensemble Brass", director_user_id=2)
        db.add(group)
        db.commit()
    members = [(1, "trumpet"), (3, "horn"), (4, "trombone"), (5, "tuba")]
    for user_id, instrument_id in members:
        exists = db.query(GroupMember).filter(GroupMember.group_id == 1, GroupMember.user_id == user_id).first()
        if exists is None:
            db.add(GroupMember(group_id=1, user_id=user_id, instrument_id=instrument_id, role_in_group="student", status="active"))
    db.commit()


def _make_sample_frames(
    instrument_id: str,
    note_plan: List[Tuple[str, float, float]],
    reference_pitch_hz: float,
    start_offset_ms: int = 0,
) -> List[Dict[str, object]]:
    profile = get_instrument_profile(instrument_id)
    frames: List[Dict[str, object]] = []
    ts = start_offset_ms
    for written_label, cents_center, jitter in note_plan:
        written_midi = note_to_midi(written_label)
        concert_midi = written_midi - profile.transposition_semitones
        for _ in range(18):
            cents = random.gauss(cents_center, jitter)
            freq = midi_to_frequency(concert_midi, reference_pitch_hz) * (2 ** (cents / 1200.0))
            frame = frequency_to_pitch_frame(freq, DEMO_RECORDING_CONFIDENCE, 0.08, ts, instrument_id, reference_pitch_hz).to_dict()
            frames.append(frame)
            ts += 110
        ts += 180
    return frames


def _create_seed_session(db: Session, user_id: int, instrument_id: str, days_ago: int, name: str, note_plan: List[Tuple[str, float, float]]) -> None:
    started = dt.datetime.utcnow() - dt.timedelta(days=days_ago, hours=days_ago % 6)
    session = PracticeSession(
        user_id=user_id,
        instrument_id=instrument_id,
        name=name,
        started_at=started,
        created_at=started,
        reference_pitch_hz=440.0,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    for frame in _make_sample_frames(instrument_id, note_plan, 440.0):
        save_pitch_frame(db, session.id, frame)
    rebuild_note_events(db, session)
    stop_session(db, session.id)
    session.started_at = started
    session.created_at = started
    if session.ended_at:
        session.ended_at = started + dt.timedelta(seconds=session.duration_seconds)
    db.add(session)
    db.commit()


def seed_demo_data(db: Session) -> None:
    random.seed(22)
    upsert_instrument_profiles(db)
    ensure_users_and_group(db)
    if db.query(PracticeSession).count() > 0:
        return
    trumpet_sessions = [
        (12, "Long tones and flow study", [("G4", -6, 3), ("A4", 8, 4), ("D5", 17, 4), ("C5", 1, 13), ("F#4", 5, 4)]),
        (8, "All-state scale tuning", [("G4", -4, 3), ("A4", 5, 3), ("D5", 14, 3), ("C5", -1, 11), ("Bb4", 2, 4)]),
        (4, "Drone practice", [("G4", -2, 3), ("A4", 2, 3), ("D5", 11, 3), ("C5", 0, 8), ("E5", 7, 4)]),
        (1, "Evening intonation check", [("G4", -2, 2), ("A4", 1, 2), ("D5", 9, 3), ("C5", 1, 7), ("E5", 5, 3)]),
    ]
    for days, name, plan in trumpet_sessions:
        _create_seed_session(db, 1, "trumpet", days, name, plan)
    _create_seed_session(db, 3, "horn", 5, "Horn section drone work", [("G4", 9, 5), ("C5", -12, 4), ("E5", 2, 9), ("A4", 6, 4)])
    _create_seed_session(db, 4, "trombone", 3, "Slide center rehearsal", [("Bb3", -3, 3), ("F3", 11, 4), ("D4", -9, 4), ("Ab3", 4, 5)])
    _create_seed_session(db, 5, "tuba", 2, "Low register resonance", [("Bb2", -11, 5), ("F2", -6, 4), ("C3", 3, 4), ("Eb3", 14, 5)])


if __name__ == "__main__":
    from app.db.database import SessionLocal, init_db

    init_db()
    database = SessionLocal()
    try:
        seed_demo_data(database)
    finally:
        database.close()
