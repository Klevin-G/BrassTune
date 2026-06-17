import datetime as dt

from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship

from app.db.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    role = Column(String, nullable=False, default="student")
    primary_instrument_id = Column(String, nullable=False, default="trumpet")
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    sessions = relationship("PracticeSession", back_populates="user")


class InstrumentProfileModel(Base):
    __tablename__ = "instrument_profiles"

    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False)
    transposition_semitones = Column(Integer, nullable=False)
    min_frequency_hz = Column(Float, nullable=False)
    max_frequency_hz = Column(Float, nullable=False)
    metadata_json = Column(Text, nullable=False, default="{}")


class PracticeSession(Base):
    __tablename__ = "practice_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    instrument_id = Column(String, nullable=False, index=True)
    name = Column(String, nullable=False)
    started_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)
    duration_seconds = Column(Float, nullable=False, default=0.0)
    reference_pitch_hz = Column(Float, nullable=False, default=440.0)
    notes_count = Column(Integer, nullable=False, default=0)
    average_signed_cents = Column(Float, nullable=False, default=0.0)
    average_abs_cents = Column(Float, nullable=False, default=0.0)
    in_tune_percentage = Column(Float, nullable=False, default=0.0)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    user = relationship("User", back_populates="sessions")
    samples = relationship("PitchSample", back_populates="session", cascade="all, delete-orphan")
    note_events = relationship("NoteEvent", back_populates="session", cascade="all, delete-orphan")


class PitchSample(Base):
    __tablename__ = "pitch_samples"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("practice_sessions.id"), nullable=False, index=True)
    timestamp_ms = Column(Integer, nullable=False)
    frequency_hz = Column(Float, nullable=False)
    confidence = Column(Float, nullable=False)
    rms = Column(Float, nullable=False)
    concert_midi_float = Column(Float, nullable=False)
    concert_nearest_midi = Column(Integer, nullable=False)
    concert_note = Column(String, nullable=False)
    concert_octave = Column(Integer, nullable=False)
    written_midi = Column(Integer, nullable=False)
    written_note = Column(String, nullable=False)
    written_octave = Column(Integer, nullable=False)
    cents_deviation = Column(Float, nullable=False)
    tuning_status = Column(String, nullable=False)
    is_valid_for_recording = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    session = relationship("PracticeSession", back_populates="samples")


class NoteEvent(Base):
    __tablename__ = "note_events"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("practice_sessions.id"), nullable=False, index=True)
    instrument_id = Column(String, nullable=False, index=True)
    written_note = Column(String, nullable=False)
    written_octave = Column(Integer, nullable=False)
    concert_note = Column(String, nullable=False)
    concert_octave = Column(Integer, nullable=False)
    started_at_ms = Column(Integer, nullable=False)
    ended_at_ms = Column(Integer, nullable=False)
    duration_ms = Column(Integer, nullable=False)
    sample_count = Column(Integer, nullable=False)
    avg_signed_cents = Column(Float, nullable=False)
    avg_abs_cents = Column(Float, nullable=False)
    median_cents = Column(Float, nullable=False)
    stddev_cents = Column(Float, nullable=False)
    min_cents = Column(Float, nullable=False)
    max_cents = Column(Float, nullable=False)
    in_tune_percentage = Column(Float, nullable=False)
    stability_score = Column(Float, nullable=False)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    session = relationship("PracticeSession", back_populates="note_events")


class Group(Base):
    __tablename__ = "groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    director_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    members = relationship("GroupMember", back_populates="group", cascade="all, delete-orphan")


class GroupMember(Base):
    __tablename__ = "group_members"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("groups.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    instrument_id = Column(String, nullable=False)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    group = relationship("Group", back_populates="members")


class Recommendation(Base):
    __tablename__ = "recommendations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    session_id = Column(Integer, ForeignKey("practice_sessions.id"), nullable=True)
    note_event_id = Column(Integer, ForeignKey("note_events.id"), nullable=True)
    written_note = Column(String, nullable=True)
    written_octave = Column(Integer, nullable=True)
    severity = Column(String, nullable=False)
    title = Column(String, nullable=False)
    message = Column(Text, nullable=False)
    suggestions_json = Column(Text, nullable=False, default="[]")
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

