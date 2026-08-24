import datetime as dt
import math
import re
import unicodedata
from typing import List, Literal, Optional

from pydantic import BaseModel, Field, field_validator

MAX_PCM_SAMPLES = 16384
MAX_BATCH_PITCH_FRAMES = 1000
CLASS_PRACTICE_AGGREGATE_SCOPE_CODE = "cloud_practice_sessions_since_membership_v1"
_CLIENT_SYNC_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")


def _normalize_client_sync_id(value):
    if value is None or not isinstance(value, str):
        return value
    normalized = value.strip()
    if not _CLIENT_SYNC_ID_PATTERN.fullmatch(normalized):
        raise ValueError("Client sync ID contains unsupported characters.")
    return normalized


def _normalize_utc_timestamp(value):
    if value is None or not isinstance(value, dt.datetime):
        return value
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Client timestamps must include a UTC offset.")
    return value.astimezone(dt.timezone.utc)


class StartSessionRequest(BaseModel):
    instrument_id: str = Field(default="trumpet", max_length=40)
    name: Optional[str] = Field(default=None, max_length=120)
    reference_pitch_hz: float = Field(default=440.0, ge=400.0, le=480.0)
    user_id: int = Field(default=1, ge=1)
    client_session_id: Optional[str] = Field(default=None, min_length=1, max_length=128)
    started_at: Optional[dt.datetime] = None

    @field_validator("client_session_id", mode="before")
    @classmethod
    def normalize_client_session_id(cls, value):
        return _normalize_client_sync_id(value)

    @field_validator("started_at")
    @classmethod
    def normalize_started_at(cls, value):
        return _normalize_utc_timestamp(value)


class StopSessionRequest(BaseModel):
    client_session_id: Optional[str] = Field(default=None, min_length=1, max_length=128)
    ended_at: Optional[dt.datetime] = None

    @field_validator("client_session_id", mode="before")
    @classmethod
    def normalize_client_session_id(cls, value):
        return _normalize_client_sync_id(value)

    @field_validator("ended_at")
    @classmethod
    def normalize_ended_at(cls, value):
        return _normalize_utc_timestamp(value)


class PitchFrameIn(BaseModel):
    client_frame_index: Optional[int] = Field(default=None, ge=0, le=2_147_483_647)
    timestamp_ms: int = Field(ge=0, le=86_400_000)
    frequency_hz: Optional[float] = Field(default=None, ge=0.0, le=5000.0)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    rms: float = Field(default=0.0, ge=0.0, le=10.0)
    midi_note_float: Optional[float] = Field(default=None, ge=0.0, le=127.0)
    nearest_midi: Optional[int] = Field(default=None, ge=0, le=127)
    concert_note_name: Optional[str] = Field(default=None, max_length=3)
    concert_octave: Optional[int] = Field(default=None, ge=-1, le=9)
    written_note_name: Optional[str] = Field(default=None, max_length=3)
    written_octave: Optional[int] = Field(default=None, ge=-1, le=9)
    cents_deviation: Optional[float] = Field(default=None, ge=-1200.0, le=1200.0)
    tuning_status: str = Field(default="unstable", max_length=20)
    instrument_id: str = Field(default="trumpet", max_length=40)
    reference_pitch_hz: float = Field(default=440.0, ge=400.0, le=480.0)
    is_valid_for_recording: bool = False
    save_eligibility_reason: Optional[str] = Field(default=None, max_length=120)
    detector_source: Optional[str] = Field(default=None, max_length=80)


class AudioFrameIn(BaseModel):
    type: str = Field(default="audio_frame", max_length=32)
    session_id: Optional[int] = None
    instrument_id: str = Field(default="trumpet", max_length=40)
    reference_pitch_hz: float = Field(default=440.0, ge=400.0, le=480.0)
    sample_rate: int = Field(default=48000, ge=8000, le=192000)
    pcm: List[float] = Field(default_factory=list, max_length=MAX_PCM_SAMPLES)

    @field_validator("pcm")
    @classmethod
    def pcm_size(cls, value):
        if len(value) > MAX_PCM_SAMPLES:
            raise ValueError("PCM frame is too large.")
        if any(not math.isfinite(sample) or sample < -1.5 or sample > 1.5 for sample in value):
            raise ValueError("PCM frame contains invalid samples.")
        return value


class UserProfileUpdate(BaseModel):
    username: Optional[str] = Field(default=None, max_length=32)
    display_name: Optional[str] = Field(default=None, max_length=80)
    primary_instrument_id: Optional[str] = Field(default=None, max_length=40)
    onboarding_completed: bool = False

    @field_validator("display_name", mode="before")
    @classmethod
    def normalize_display_name(cls, value):
        if value is None or not isinstance(value, str):
            return value
        # Normalize before Pydantic applies max_length so the public contract
        # is 80 NFC Unicode code points, independent of decomposed input.
        return unicodedata.normalize("NFC", value).strip()

    @field_validator("username")
    @classmethod
    def username_format(cls, value):
        if value is None:
            return value
        normalized = value.strip().lower()
        if len(normalized) < 3 or len(normalized) > 32:
            raise ValueError("Username must be 3-32 characters.")
        allowed = set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        if any(char not in allowed for char in normalized):
            raise ValueError("Username may contain letters, numbers, underscores, and hyphens.")
        return normalized


class CreateGroupRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80)

    @field_validator("name", mode="before")
    @classmethod
    def normalize_name(cls, value):
        if not isinstance(value, str):
            return value
        return unicodedata.normalize("NFC", value).strip()


class ClassAggregateSharingConsent(BaseModel):
    scope_code: Literal[CLASS_PRACTICE_AGGREGATE_SCOPE_CODE]
    acknowledged: Literal[True]


class UpdateClassSharingConsentRequest(BaseModel):
    sharing_consent: ClassAggregateSharingConsent


class AddMemberByUsernameRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    # Optional: the director may leave the instrument unset and the student
    # chooses it when they accept the invitation.
    instrument_id: Optional[str] = Field(default=None, max_length=40)
    role_in_group: str = Field(default="student", max_length=24)

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value):
        return value.strip().lower()


class AcceptInvitationRequest(BaseModel):
    # A student may set their own instrument at the moment they accept.
    instrument_id: Optional[str] = Field(default=None, max_length=40)
    sharing_consent: ClassAggregateSharingConsent


class JoinByCodeRequest(BaseModel):
    code: str = Field(min_length=4, max_length=16)
    instrument_id: Optional[str] = Field(default=None, max_length=40)
    sharing_consent: ClassAggregateSharingConsent

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value):
        return value.strip().upper().replace(" ", "")


class UpdateGroupMemberRequest(BaseModel):
    instrument_id: Optional[str] = Field(default=None, max_length=40)
    role_in_group: Optional[str] = Field(default=None, max_length=24)
    status: Optional[str] = Field(default=None, max_length=24)


class AudioUploadMetadata(BaseModel):
    duration_seconds: Optional[float] = Field(default=None, ge=0, le=86_400)


class AccountDeletionRequest(BaseModel):
    confirmation: str = Field(min_length=6, max_length=120)
