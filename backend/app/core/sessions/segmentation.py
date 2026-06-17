import statistics
from typing import Dict, Iterable, List, Optional


def _value(frame, key, default=None):
    if isinstance(frame, dict):
        return frame.get(key, default)
    return getattr(frame, key, default)


def _is_valid(frame) -> bool:
    return bool(_value(frame, "is_valid_for_recording", False)) and _value(frame, "cents_deviation") is not None


def compute_note_event_stats(frames: List[object]) -> Dict[str, object]:
    valid = [frame for frame in frames if _is_valid(frame)]
    if not valid:
        return {}
    cents = [float(_value(frame, "cents_deviation")) for frame in valid]
    statuses = [_value(frame, "tuning_status") for frame in valid]
    started = int(_value(valid[0], "timestamp_ms", 0))
    ended = int(_value(valid[-1], "timestamp_ms", started))
    duration = max(0, ended - started)
    if len(valid) > 1:
        gaps = [
            int(_value(valid[index], "timestamp_ms", 0)) - int(_value(valid[index - 1], "timestamp_ms", 0))
            for index in range(1, len(valid))
        ]
        median_gap = int(statistics.median(gaps)) if gaps else 0
        duration += max(60, min(median_gap, 180))
    in_tune = len([status for status in statuses if status == "in_tune"])
    stddev = statistics.pstdev(cents) if len(cents) > 1 else 0.0
    stability_score = max(0.0, min(100.0, 100.0 - (stddev * 5.0)))
    return {
        "instrument_id": _value(valid[0], "instrument_id"),
        "written_note": _value(valid[0], "written_note_name", _value(valid[0], "written_note")),
        "written_octave": _value(valid[0], "written_octave"),
        "concert_note": _value(valid[0], "concert_note_name", _value(valid[0], "concert_note")),
        "concert_octave": _value(valid[0], "concert_octave"),
        "started_at_ms": started,
        "ended_at_ms": ended,
        "duration_ms": duration,
        "sample_count": len(valid),
        "avg_signed_cents": statistics.fmean(cents),
        "avg_abs_cents": statistics.fmean([abs(value) for value in cents]),
        "median_cents": statistics.median(cents),
        "stddev_cents": stddev,
        "min_cents": min(cents),
        "max_cents": max(cents),
        "in_tune_percentage": (in_tune / len(valid)) * 100.0,
        "stability_score": stability_score,
    }


def segment_note_events(
    frames: Iterable[object],
    max_merge_gap_ms: int = 220,
    min_duration_ms: int = 120,
) -> List[Dict[str, object]]:
    ordered = sorted(list(frames), key=lambda frame: int(_value(frame, "timestamp_ms", 0)))
    events: List[Dict[str, object]] = []
    current: List[object] = []
    last_valid_ts: Optional[int] = None
    current_label = None

    def close_current() -> None:
        nonlocal current
        if not current:
            return
        stats = compute_note_event_stats(current)
        if stats and int(stats["duration_ms"]) >= min_duration_ms:
            events.append(stats)
        current = []

    for frame in ordered:
        ts = int(_value(frame, "timestamp_ms", 0))
        if not _is_valid(frame):
            if current and last_valid_ts is not None and ts - last_valid_ts > max_merge_gap_ms:
                close_current()
                current_label = None
            continue
        label = (_value(frame, "written_note_name", _value(frame, "written_note")), _value(frame, "written_octave"))
        if not current:
            current = [frame]
            current_label = label
            last_valid_ts = ts
            continue
        gap = ts - int(last_valid_ts or ts)
        if label == current_label and gap <= max_merge_gap_ms:
            current.append(frame)
        else:
            close_current()
            current = [frame]
            current_label = label
        last_valid_ts = ts
    close_current()
    return events


def compute_session_summary(note_events: List[Dict[str, object]]) -> Dict[str, object]:
    if not note_events:
        return {
            "duration_seconds": 0.0,
            "notes_count": 0,
            "average_signed_cents": 0.0,
            "average_abs_cents": 0.0,
            "in_tune_percentage": 0.0,
        }
    total_duration = sum(float(event.get("duration_ms", 0)) for event in note_events)
    if total_duration <= 0:
        total_duration = float(len(note_events))
    signed = sum(float(event["avg_signed_cents"]) * float(event.get("duration_ms", 1)) for event in note_events)
    absolute = sum(float(event["avg_abs_cents"]) * float(event.get("duration_ms", 1)) for event in note_events)
    in_tune = sum(float(event["in_tune_percentage"]) * float(event.get("duration_ms", 1)) for event in note_events)
    return {
        "duration_seconds": round(total_duration / 1000.0, 2),
        "notes_count": len(note_events),
        "average_signed_cents": signed / total_duration,
        "average_abs_cents": absolute / total_duration,
        "in_tune_percentage": in_tune / total_duration,
    }


def reject_outliers(frames: List[object], max_abs_cents: float = 50.0) -> List[object]:
    return [
        frame
        for frame in frames
        if _value(frame, "cents_deviation") is None or abs(float(_value(frame, "cents_deviation"))) <= max_abs_cents
    ]

