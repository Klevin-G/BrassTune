import math
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator

MAX_PCM_SAMPLES = 16384
MAX_BATCH_PITCH_FRAMES = 1000


class StartSessionRequest(BaseModel):
    instrument_id: str = Field(default="trumpet", max_length=40)
    name: Optional[str] = Field(default=None, max_length=120)
    reference_pitch_hz: float = Field(default=440.0, ge=400.0, le=480.0)
    user_id: int = 1


class PitchFrameIn(BaseModel):
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
    username: Optional[str] = None
    display_name: Optional[str] = None
    primary_instrument_id: Optional[str] = None
    onboarding_completed: bool = False

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


class AddMemberByUsernameRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    instrument_id: str
    role_in_group: str = "student"

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value):
        return value.strip().lower()


class UpdateGroupMemberRequest(BaseModel):
    instrument_id: Optional[str] = None
    role_in_group: Optional[str] = None
    status: Optional[str] = None


class AudioUploadMetadata(BaseModel):
    duration_seconds: Optional[float] = None


class AccountDeletionRequest(BaseModel):
    confirmation: str = Field(min_length=6, max_length=120)
