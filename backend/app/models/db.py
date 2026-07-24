import datetime as dt

from sqlalchemy import JSON, Boolean, Column, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship

from app.db.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    supabase_user_id = Column(String, nullable=True, unique=True, index=True)
    username = Column(String, nullable=True, unique=True, index=True)
    name = Column(String, nullable=False)
    display_name = Column(String, nullable=True)
    email = Column(String, nullable=True, index=True)
    role = Column(String, nullable=False, default="student")
    # True only when admin was granted by the BRASSTUNE_ADMIN_EMAILS env list, so
    # removing an email can safely revoke that admin without touching admins that
    # were granted some other way.
    admin_granted_by_env = Column(Boolean, nullable=False, default=False)
    primary_instrument_id = Column(String, nullable=False, default="trumpet")
    onboarding_completed_at = Column(DateTime, nullable=True)
    last_active_at = Column(DateTime, nullable=True, index=True)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow, onupdate=dt.datetime.utcnow)

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
    audio_storage_provider = Column(String, nullable=True)
    audio_object_key = Column(String, nullable=True)
    audio_mime_type = Column(String, nullable=True)
    audio_duration_seconds = Column(Float, nullable=True)
    audio_size_bytes = Column(Integer, nullable=True)
    audio_uploaded_at = Column(DateTime, nullable=True)
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
    # Short shareable code students type to self-join the class.
    join_code = Column(String, nullable=True, unique=True, index=True)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow, onupdate=dt.datetime.utcnow)

    members = relationship("GroupMember", back_populates="group", cascade="all, delete-orphan")


class GroupMember(Base):
    __tablename__ = "group_members"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_members_group_user"),
    )

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("groups.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    instrument_id = Column(String, nullable=False)
    role_in_group = Column(String, nullable=False, default="student")
    status = Column(String, nullable=False, default="active")
    active_since = Column(DateTime, nullable=True)
    removed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)

    group = relationship("Group", back_populates="members")
    user = relationship("User")


class Invitation(Base):
    __tablename__ = "invitations"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("groups.id"), nullable=False)
    invited_username = Column(String, nullable=False)
    invited_user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    invited_by_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    status = Column(String, nullable=False, default="pending")
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    accepted_at = Column(DateTime, nullable=True)


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


class UsageEvent(Base):
    __tablename__ = "usage_events"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    event_name = Column(String, nullable=False, index=True)
    properties = Column(JSON().with_variant(JSONB(), "postgresql"), nullable=False, default=dict)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow, index=True)


class AccountDeletionJob(Base):
    __tablename__ = "account_deletion_jobs"

    id = Column(Integer, primary_key=True, index=True)
    # Required while cleanup is operational; terminal jobs are scrubbed and
    # retained only briefly for coarse maintenance observability.
    user_id = Column(Integer, nullable=True, index=True)
    supabase_user_id = Column(String, nullable=True, index=True)
    idempotency_key = Column(String, nullable=False, unique=True, index=True)
    stage = Column(String, nullable=False, default="requested")
    status = Column(String, nullable=False, default="pending")
    retry_count = Column(Integer, nullable=False, default=0)
    next_retry_at = Column(DateTime, nullable=True)
    safe_error_category = Column(String, nullable=True)
    counts_json = Column(JSON().with_variant(JSONB(), "postgresql"), nullable=False, default=dict)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow, onupdate=dt.datetime.utcnow)


class DeletedIdentityTombstone(Base):
    """Minimal permanent deny-list entry for a deleted Supabase subject.

    The digest is a keyed HMAC generated by the backend. It preserves the
    account-recreation block without retaining the provider's raw identifier.
    """

    __tablename__ = "deleted_identity_tombstones"

    id = Column(Integer, primary_key=True, index=True)
    subject_digest = Column(String(64), nullable=False, unique=True, index=True)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)


class DeletedIdentityTombstoneConfig(Base):
    """Non-identity verifier and privacy rollout state."""

    __tablename__ = "deleted_identity_tombstone_config"

    id = Column(Integer, primary_key=True)
    key_verifier = Column(String(64), nullable=False)
    enforcement_phase = Column(String, nullable=False, default="expand", server_default="expand")
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)


class MaintenanceRequestNonce(Base):
    """Short-lived replay protection for authenticated maintenance requests.

    Only a one-way nonce digest and coarse executor metadata are retained. Raw
    nonces, request signatures, bodies, and user identifiers never enter this
    table.
    """

    __tablename__ = "maintenance_request_nonces"

    id = Column(Integer, primary_key=True, index=True)
    nonce_digest = Column(String(64), nullable=False, unique=True, index=True)
    key_id = Column(String(64), nullable=False)
    purpose = Column(String(64), nullable=False)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    expires_at = Column(DateTime, nullable=False, index=True)


class AudioStorageJob(Base):
    """Durable upload reservations, cleanup tombstones, and reconciliations.

    User/session identifiers intentionally are not foreign keys: cleanup work
    must survive account or session deletion until the storage object is gone.
    """

    __tablename__ = "audio_storage_jobs"

    id = Column(Integer, primary_key=True, index=True)
    # Nullable by design: terminal jobs are immediately scrubbed of account and
    # session identifiers, then purged after the short maintenance TTL.
    user_id = Column(Integer, nullable=True, index=True)
    session_id = Column(Integer, nullable=True, index=True)
    idempotency_key = Column(String, nullable=False, unique=True, index=True)
    action = Column(String, nullable=False)
    provider = Column(String, nullable=False)
    object_key = Column(String, nullable=False)
    size_bytes = Column(Integer, nullable=False, default=0)
    reason = Column(String, nullable=False)
    status = Column(String, nullable=False, default="pending")
    retry_count = Column(Integer, nullable=False, default=0)
    next_retry_at = Column(DateTime, nullable=True)
    safe_error_category = Column(String, nullable=True)
    details_json = Column(JSON().with_variant(JSONB(), "postgresql"), nullable=False, default=dict)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=dt.datetime.utcnow, onupdate=dt.datetime.utcnow)
