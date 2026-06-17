import datetime as dt
from typing import Any, Dict


def iso(value):
    if isinstance(value, dt.datetime):
        return value.isoformat()
    return value


def session_to_dict(session) -> Dict[str, Any]:
    return {
        "id": session.id,
        "user_id": session.user_id,
        "instrument_id": session.instrument_id,
        "name": session.name,
        "started_at": iso(session.started_at),
        "ended_at": iso(session.ended_at),
        "duration_seconds": session.duration_seconds,
        "reference_pitch_hz": session.reference_pitch_hz,
        "notes_count": session.notes_count,
        "average_signed_cents": session.average_signed_cents,
        "average_abs_cents": session.average_abs_cents,
        "in_tune_percentage": session.in_tune_percentage,
        "created_at": iso(session.created_at),
    }


def sample_to_dict(sample) -> Dict[str, Any]:
    return {
        "id": sample.id,
        "session_id": sample.session_id,
        "timestamp_ms": sample.timestamp_ms,
        "frequency_hz": sample.frequency_hz,
        "confidence": sample.confidence,
        "rms": sample.rms,
        "concert_midi_float": sample.concert_midi_float,
        "concert_nearest_midi": sample.concert_nearest_midi,
        "concert_note": sample.concert_note,
        "concert_octave": sample.concert_octave,
        "written_midi": sample.written_midi,
        "written_note": sample.written_note,
        "written_octave": sample.written_octave,
        "cents_deviation": sample.cents_deviation,
        "tuning_status": sample.tuning_status,
        "is_valid_for_recording": bool(sample.is_valid_for_recording),
        "created_at": iso(sample.created_at),
    }


def sample_to_frame_dict(sample) -> Dict[str, Any]:
    return {
        "timestamp_ms": sample.timestamp_ms,
        "frequency_hz": sample.frequency_hz,
        "confidence": sample.confidence,
        "rms": sample.rms,
        "midi_note_float": sample.concert_midi_float,
        "nearest_midi": sample.concert_nearest_midi,
        "concert_note_name": sample.concert_note,
        "concert_octave": sample.concert_octave,
        "written_note_name": sample.written_note,
        "written_octave": sample.written_octave,
        "cents_deviation": sample.cents_deviation,
        "tuning_status": sample.tuning_status,
        "instrument_id": sample.session.instrument_id,
        "reference_pitch_hz": sample.session.reference_pitch_hz,
        "is_valid_for_recording": bool(sample.is_valid_for_recording),
    }


def event_to_dict(event) -> Dict[str, Any]:
    return {
        "id": event.id,
        "session_id": event.session_id,
        "instrument_id": event.instrument_id,
        "written_note": event.written_note,
        "written_octave": event.written_octave,
        "note_label": "%s%s" % (event.written_note, event.written_octave),
        "concert_note": event.concert_note,
        "concert_octave": event.concert_octave,
        "started_at_ms": event.started_at_ms,
        "ended_at_ms": event.ended_at_ms,
        "duration_ms": event.duration_ms,
        "duration_seconds": event.duration_ms / 1000.0,
        "sample_count": event.sample_count,
        "avg_signed_cents": event.avg_signed_cents,
        "avg_abs_cents": event.avg_abs_cents,
        "median_cents": event.median_cents,
        "stddev_cents": event.stddev_cents,
        "min_cents": event.min_cents,
        "max_cents": event.max_cents,
        "in_tune_percentage": event.in_tune_percentage,
        "stability_score": event.stability_score,
        "created_at": iso(event.created_at),
    }

