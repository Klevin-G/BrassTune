import math
from dataclasses import asdict, dataclass
from typing import Dict, Optional

from app.core.instruments.profiles import InstrumentProfile, get_instrument_profile

DEFAULT_REFERENCE_PITCH_HZ = 440.0
MIN_RECORDING_CONFIDENCE = 0.95
NOTE_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
NOTE_NAME_TO_INDEX = {
    "C": 0,
    "C#": 1,
    "Db": 1,
    "D": 2,
    "D#": 3,
    "Eb": 3,
    "E": 4,
    "F": 5,
    "F#": 6,
    "Gb": 6,
    "G": 7,
    "G#": 8,
    "Ab": 8,
    "A": 9,
    "A#": 10,
    "Bb": 10,
    "B": 11,
}


@dataclass
class PitchFrame:
    timestamp_ms: int
    frequency_hz: Optional[float]
    confidence: float
    rms: float
    midi_note_float: Optional[float]
    nearest_midi: Optional[int]
    concert_note_name: Optional[str]
    concert_octave: Optional[int]
    written_note_name: Optional[str]
    written_octave: Optional[int]
    cents_deviation: Optional[float]
    tuning_status: str
    instrument_id: str
    reference_pitch_hz: float
    is_valid_for_recording: bool
    save_eligibility_reason: str = "unknown"
    detector_source: Optional[str] = None

    def to_dict(self) -> Dict[str, object]:
        return asdict(self)


def frequency_to_midi(frequency_hz: float, reference_pitch_hz: float = DEFAULT_REFERENCE_PITCH_HZ) -> float:
    if frequency_hz <= 0:
        raise ValueError("frequency_hz must be positive")
    return 69 + 12 * math.log2(frequency_hz / reference_pitch_hz)


def midi_to_frequency(midi_note: float, reference_pitch_hz: float = DEFAULT_REFERENCE_PITCH_HZ) -> float:
    return reference_pitch_hz * (2 ** ((midi_note - 69) / 12))


def round_midi_half_up(midi_note: float) -> int:
    """Match JavaScript Math.round and Swift's default midpoint behavior."""
    if not math.isfinite(midi_note):
        raise ValueError("midi_note must be finite")
    return int(math.floor(midi_note + 0.5))


def midi_to_note_name(midi_note: int, spelling_preference=None) -> Dict[str, object]:
    names = spelling_preference or NOTE_NAMES
    pitch_class = midi_note % 12
    octave = midi_note // 12 - 1
    return {"note": names[pitch_class], "octave": octave, "pitch_class": pitch_class}


def note_label_to_midi(note_label: str) -> int:
    if len(note_label) < 2:
        raise ValueError("Invalid note label: %s" % note_label)
    has_accidental = len(note_label) >= 3 and note_label[1] in ("#", "b")
    note = note_label[:2] if has_accidental else note_label[:1]
    octave = int(note_label[2:] if has_accidental else note_label[1:])
    try:
        pitch_class = NOTE_NAME_TO_INDEX[note]
    except KeyError as exc:
        raise ValueError("Invalid note name: %s" % note) from exc
    return (octave + 1) * 12 + pitch_class


def midi_range_from_labels(range_label: str) -> range:
    try:
        start_label, end_label = range_label.split("-", 1)
    except ValueError as exc:
        raise ValueError("Range must look like F#3-C6") from exc
    start = note_label_to_midi(start_label.strip())
    end = note_label_to_midi(end_label.strip())
    if end < start:
        raise ValueError("Range end must be above range start")
    return range(start, end + 1)


def calculate_cents_deviation(frequency_hz: float, target_frequency_hz: float) -> float:
    if frequency_hz <= 0 or target_frequency_hz <= 0:
        raise ValueError("frequency and target_frequency must be positive")
    return 1200 * math.log2(frequency_hz / target_frequency_hz)


def transpose_concert_to_written(concert_midi: int, instrument_profile: InstrumentProfile) -> int:
    return concert_midi + instrument_profile.transposition_semitones


def classify_tuning_status(
    cents: Optional[float],
    confidence: float,
    rms: float,
    rms_threshold: float = 0.01,
    confidence_threshold: float = MIN_RECORDING_CONFIDENCE,
) -> str:
    if rms < rms_threshold:
        return "silence"
    if cents is None or confidence < confidence_threshold:
        return "unstable"
    if abs(cents) <= 5:
        return "in_tune"
    if cents < -5:
        return "flat"
    return "sharp"


def save_eligibility_reason(
    status: str,
    confidence: float,
    rms: float,
    frequency_hz: Optional[float],
    in_instrument_range: bool = True,
) -> str:
    if status == "silence" or rms < 0.01:
        return "silence"
    if frequency_hz is None or frequency_hz <= 0:
        return "unstable/no pitch lock"
    if not in_instrument_range:
        return "outside instrument range"
    if confidence < MIN_RECORDING_CONFIDENCE:
        return "confidence below 95%"
    if status in ("flat", "in_tune", "sharp"):
        return "valid for recording"
    return "unstable/no pitch lock"


def frequency_to_pitch_frame(
    frequency_hz: Optional[float],
    confidence: float,
    rms: float,
    timestamp_ms: int,
    instrument_id: str = "trumpet",
    reference_pitch_hz: float = DEFAULT_REFERENCE_PITCH_HZ,
    detector_source: Optional[str] = None,
) -> PitchFrame:
    profile = get_instrument_profile(instrument_id)
    if frequency_hz is None or frequency_hz <= 0:
        status = classify_tuning_status(None, confidence, rms)
        return PitchFrame(
            timestamp_ms=timestamp_ms,
            frequency_hz=None,
            confidence=confidence,
            rms=rms,
            midi_note_float=None,
            nearest_midi=None,
            concert_note_name=None,
            concert_octave=None,
            written_note_name=None,
            written_octave=None,
            cents_deviation=None,
            tuning_status=status,
            instrument_id=instrument_id,
            reference_pitch_hz=reference_pitch_hz,
            is_valid_for_recording=False,
            save_eligibility_reason=save_eligibility_reason(status, confidence, rms, frequency_hz),
            detector_source=detector_source,
        )

    if frequency_hz < profile.min_frequency_hz or frequency_hz > profile.max_frequency_hz:
        status = "unstable" if rms >= 0.01 else "silence"
        return PitchFrame(
            timestamp_ms=timestamp_ms,
            frequency_hz=frequency_hz,
            confidence=confidence,
            rms=rms,
            midi_note_float=None,
            nearest_midi=None,
            concert_note_name=None,
            concert_octave=None,
            written_note_name=None,
            written_octave=None,
            cents_deviation=None,
            tuning_status=status,
            instrument_id=instrument_id,
            reference_pitch_hz=reference_pitch_hz,
            is_valid_for_recording=False,
            save_eligibility_reason=save_eligibility_reason(status, confidence, rms, frequency_hz, False),
            detector_source=detector_source,
        )

    midi_float = frequency_to_midi(frequency_hz, reference_pitch_hz)
    nearest_midi = round_midi_half_up(midi_float)
    target_frequency = midi_to_frequency(nearest_midi, reference_pitch_hz)
    cents = calculate_cents_deviation(frequency_hz, target_frequency)
    concert = midi_to_note_name(nearest_midi, profile.preferred_note_spellings)
    written_midi = transpose_concert_to_written(nearest_midi, profile)
    written = midi_to_note_name(written_midi, profile.preferred_note_spellings)
    status = classify_tuning_status(cents, confidence, rms)
    valid = status in ("flat", "in_tune", "sharp")
    reason = save_eligibility_reason(status, confidence, rms, frequency_hz)

    return PitchFrame(
        timestamp_ms=timestamp_ms,
        frequency_hz=frequency_hz,
        confidence=confidence,
        rms=rms,
        midi_note_float=midi_float,
        nearest_midi=nearest_midi,
        concert_note_name=str(concert["note"]),
        concert_octave=int(concert["octave"]),
        written_note_name=str(written["note"]),
        written_octave=int(written["octave"]),
        cents_deviation=cents,
        tuning_status=status,
        instrument_id=instrument_id,
        reference_pitch_hz=reference_pitch_hz,
        is_valid_for_recording=valid,
        save_eligibility_reason=reason,
        detector_source=detector_source,
    )


def note_label(note: Optional[str], octave: Optional[int]) -> str:
    if note is None or octave is None:
        return "-"
    return "%s%s" % (note, octave)
