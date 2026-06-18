from typing import List, Optional

from pydantic import BaseModel, Field, validator

MAX_PCM_SAMPLES = 16384
MAX_BATCH_PITCH_FRAMES = 1000


class StartSessionRequest(BaseModel):
    instrument_id: str = "trumpet"
    name: Optional[str] = None
    reference_pitch_hz: float = 440.0
    user_id: int = 1


class PitchFrameIn(BaseModel):
    timestamp_ms: int
    frequency_hz: Optional[float]
    confidence: float = 0.0
    rms: float = 0.0
    midi_note_float: Optional[float] = None
    nearest_midi: Optional[int] = None
    concert_note_name: Optional[str] = None
    concert_octave: Optional[int] = None
    written_note_name: Optional[str] = None
    written_octave: Optional[int] = None
    cents_deviation: Optional[float] = None
    tuning_status: str = "unstable"
    instrument_id: str = "trumpet"
    reference_pitch_hz: float = 440.0
    is_valid_for_recording: bool = False
    save_eligibility_reason: Optional[str] = None
    detector_source: Optional[str] = None


class AudioFrameIn(BaseModel):
    type: str = "audio_frame"
    session_id: Optional[int] = None
    instrument_id: str = "trumpet"
    reference_pitch_hz: float = 440.0
    sample_rate: int = Field(default=48000, ge=8000, le=192000)
    pcm: List[float] = Field(default_factory=list)

    @validator("pcm")
    def pcm_size(cls, value):
        if len(value) > MAX_PCM_SAMPLES:
            raise ValueError("PCM frame is too large.")
        return value


class UserProfileUpdate(BaseModel):
    username: Optional[str] = None
    display_name: Optional[str] = None
    primary_instrument_id: Optional[str] = None
    onboarding_completed: bool = False

    @validator("username")
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

    @validator("username")
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
