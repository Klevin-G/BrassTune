from typing import List, Optional

from pydantic import BaseModel, Field


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
    sample_rate: int = 48000
    pcm: List[float] = Field(default_factory=list)
