import datetime as dt
import math
import statistics
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from typing import Dict, Iterable, List, Optional, Tuple

from app.core.instruments.profiles import InstrumentProfile
from app.core.music.theory import midi_range_from_labels, midi_to_note_name

CENTERED_CENTS_LIMIT = 5.0


def _value(row, key, default=None):
    if isinstance(row, dict):
        return row.get(key, default)
    return getattr(row, key, default)


def _note_key(event) -> Tuple[str, int]:
    return (str(_value(event, "written_note")), int(_value(event, "written_octave")))


def duration_weighted_mean(
    rows: Iterable[object],
    value_key: str,
    duration_key: str,
) -> Optional[float]:
    """Return one consistent aggregate for session-derived tuning metrics.

    Positive measured duration is the canonical weight. Rows without positive
    duration never dilute rows that have measured time. If every row predates
    duration tracking, fall back to an even mean so legacy data stays usable.
    """
    values = []
    weighted_values = []
    total_duration = 0.0
    for row in rows:
        raw_value = _value(row, value_key)
        if raw_value is None:
            continue
        value = float(raw_value)
        duration = max(0.0, float(_value(row, duration_key, 0) or 0))
        values.append(value)
        if duration > 0:
            weighted_values.append(value * duration)
            total_duration += duration
    if total_duration > 0:
        return sum(weighted_values) / total_duration
    if values:
        return statistics.fmean(values)
    return None


def _duration_weighted_values(
    rows: Iterable[object],
    value_key: str,
    duration_key: str,
) -> list[tuple[float, float]]:
    entries = []
    for row in rows:
        raw_value = _value(row, value_key)
        if raw_value is None:
            continue
        entries.append(
            (
                float(raw_value),
                max(0.0, float(_value(row, duration_key, 0) or 0)),
            )
        )
    if any(duration > 0 for _, duration in entries):
        return [(value, duration) for value, duration in entries if duration > 0]
    return [(value, 1.0) for value, _ in entries]


def duration_weighted_median(
    rows: Iterable[object],
    value_key: str,
    duration_key: str,
) -> Optional[float]:
    """Return a deterministic duration-weighted median.

    Positive-duration rows define the distribution and legacy zero-duration
    rows do not dilute it. If all rows are legacy, each row receives equal
    weight. At an exact 50/50 boundary, the two adjacent values are averaged,
    matching ``statistics.median`` for equal-weight even-sized inputs.
    """
    values = sorted(_duration_weighted_values(rows, value_key, duration_key))
    if not values:
        return None
    halfway = sum(weight for _, weight in values) / 2.0
    cumulative = 0.0
    for index, (value, weight) in enumerate(values):
        cumulative += weight
        if math.isclose(cumulative, halfway, rel_tol=0.0, abs_tol=1e-12):
            if index + 1 < len(values):
                return (value + values[index + 1][0]) / 2.0
            return value
        if cumulative > halfway:
            return value
    return values[-1][0]


def duration_weighted_pstdev(
    rows: Iterable[object],
    value_key: str,
    duration_key: str,
) -> Optional[float]:
    """Return population deviation of event centers using duration weights."""
    values = _duration_weighted_values(rows, value_key, duration_key)
    if not values:
        return None
    total_weight = sum(weight for _, weight in values)
    mean = sum(value * weight for value, weight in values) / total_weight
    variance = sum(weight * ((value - mean) ** 2) for value, weight in values) / total_weight
    return math.sqrt(max(0.0, variance))


def calculate_note_stats(events: Iterable[object]) -> List[Dict[str, object]]:
    grouped: Dict[Tuple[str, int], List[object]] = defaultdict(list)
    for event in events:
        if _value(event, "written_note") is not None:
            grouped[_note_key(event)].append(event)

    stats: List[Dict[str, object]] = []
    for (note, octave), rows in grouped.items():
        duration = sum(max(0.0, float(_value(row, "duration_ms", 0) or 0)) for row in rows)
        sample_count = sum(int(_value(row, "sample_count", 0)) for row in rows)
        avg_signed = duration_weighted_mean(rows, "avg_signed_cents", "duration_ms") or 0.0
        avg_abs = duration_weighted_mean(rows, "avg_abs_cents", "duration_ms") or 0.0
        in_tune = duration_weighted_mean(rows, "in_tune_percentage", "duration_ms") or 0.0
        stability = duration_weighted_mean(rows, "stability_score", "duration_ms") or 0.0
        median = duration_weighted_median(rows, "median_cents", "duration_ms")
        if median is None:
            median = duration_weighted_median(rows, "avg_signed_cents", "duration_ms") or 0.0
        # One event already carries within-event detector variation. With
        # multiple events, report duration-weighted variation of their centers.
        stddev = (
            duration_weighted_pstdev(rows, "avg_signed_cents", "duration_ms") or 0.0
            if len(rows) > 1
            else float(_value(rows[0], "stddev_cents", 0))
        )
        row = {
            "written_note": note,
            "written_octave": octave,
            "note_label": "%s%s" % (note, octave),
            "avg_signed_cents": avg_signed,
            "avg_abs_cents": avg_abs,
            "median_cents": median,
            "stddev_cents": stddev,
            "in_tune_percentage": in_tune,
            "duration_ms": duration,
            "duration_seconds": duration / 1000.0,
            "sample_count": sample_count,
            "event_count": len(rows),
            "stability_score": stability,
        }
        row["trend"] = classify_note_trend(row)
        row["severity"] = classify_note_problem(row)
        row["problem_severity"] = problem_score(row)
        row["severity_color"] = heatmap_severity(row)
        stats.append(row)
    return sorted(stats, key=lambda row: (int(row["written_octave"]), str(row["written_note"])))


def classify_note_problem(note_stats: Dict[str, object]) -> str:
    avg_abs = float(note_stats.get("avg_abs_cents", 0))
    in_tune = float(note_stats.get("in_tune_percentage", 0))
    if avg_abs <= 5 and in_tune >= 80:
        return "excellent"
    if avg_abs <= 8:
        return "good"
    if avg_abs <= 15:
        return "moderate issue"
    return "severe issue"


def classify_note_trend(note_stats: Dict[str, object]) -> str:
    signed = float(note_stats.get("avg_signed_cents", 0))
    stddev = float(note_stats.get("stddev_cents", 0))
    stability = float(note_stats.get("stability_score", 100))
    if stddev >= 12 or stability < 50:
        return "Unstable"
    if signed > CENTERED_CENTS_LIMIT:
        return "Mostly sharp"
    if signed < -CENTERED_CENTS_LIMIT:
        return "Mostly flat"
    return "Centered"


def problem_score(note_stats: Dict[str, object]) -> float:
    """Return nonnegative severity rounded to cents-style hundredths, half up."""
    avg_abs = float(note_stats.get("avg_abs_cents", 0))
    stddev = float(note_stats.get("stddev_cents", 0))
    in_tune = float(note_stats.get("in_tune_percentage", 0))
    value = avg_abs * 2 + stddev + max(0.0, 80 - in_tune) * 0.25
    return float(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def heatmap_severity(note_stats: Optional[Dict[str, object]]) -> str:
    if not note_stats:
        return "insufficient"
    duration = float(note_stats.get("duration_seconds", 0))
    samples = int(note_stats.get("sample_count", 0))
    avg_abs = float(note_stats.get("avg_abs_cents", 0))
    if duration < 3 or samples < 8:
        return "insufficient"
    if avg_abs <= 5:
        return "green"
    if avg_abs <= 10:
        return "yellow"
    if avg_abs <= 15:
        return "orange"
    return "red"


def build_heatmap(note_stats: Iterable[Dict[str, object]]) -> List[Dict[str, object]]:
    return [
        {
            **stat,
            "severity_color": heatmap_severity(stat),
            "recommendation_summary": _summary_for_stat(stat),
        }
        for stat in note_stats
    ]


def build_instrument_heatmap(note_stats: Iterable[Dict[str, object]], instrument_profile: InstrumentProfile) -> List[Dict[str, object]]:
    stats_by_label = {str(stat["note_label"]): stat for stat in note_stats}
    cells: List[Dict[str, object]] = []
    for midi in midi_range_from_labels(instrument_profile.typical_range_written):
        note = midi_to_note_name(midi, instrument_profile.preferred_note_spellings)
        label = "%s%s" % (note["note"], note["octave"])
        stat = stats_by_label.get(label)
        if stat:
            cell = {
                **stat,
                "has_data": True,
                "severity_color": heatmap_severity(stat),
                "recommendation_summary": _summary_for_stat(stat),
            }
        else:
            cell = {
                "written_note": note["note"],
                "written_octave": note["octave"],
                "note_label": label,
                "avg_signed_cents": 0.0,
                "avg_abs_cents": 0.0,
                "median_cents": 0.0,
                "stddev_cents": 0.0,
                "in_tune_percentage": 0.0,
                "duration_ms": 0.0,
                "duration_seconds": 0.0,
                "sample_count": 0,
                "event_count": 0,
                "stability_score": 0.0,
                "trend": "Insufficient data",
                "severity": "insufficient data",
                "problem_severity": 0.0,
                "has_data": False,
                "severity_color": "insufficient",
                "recommendation_summary": "No recorded attempts yet",
            }
        cells.append(cell)
    return cells


def _summary_for_stat(stat: Dict[str, object]) -> str:
    trend = classify_note_trend(stat)
    avg = abs(float(stat.get("avg_signed_cents", 0)))
    if trend == "Mostly sharp":
        return "Tends sharp by %.0f cents" % avg
    if trend == "Mostly flat":
        return "Tends flat by %.0f cents" % avg
    if trend == "Unstable":
        return "Pitch is inconsistent"
    return "Generally centered"


def calculate_session_summary(session) -> Dict[str, object]:
    return {
        "id": _value(session, "id"),
        "name": _value(session, "name"),
        "instrument_id": _value(session, "instrument_id"),
        "duration_seconds": float(_value(session, "duration_seconds", 0) or 0),
        "average_signed_cents": float(_value(session, "average_signed_cents", 0) or 0),
        "average_abs_cents": float(_value(session, "average_abs_cents", 0) or 0),
        "in_tune_percentage": float(_value(session, "in_tune_percentage", 0) or 0),
    }


def aggregate_note_stats(note_events: Iterable[object], group_by: str = "written_note") -> List[Dict[str, object]]:
    return calculate_note_stats(note_events)


def calculate_progress_timeseries(sessions: Iterable[object], interval: str = "day") -> List[Dict[str, object]]:
    grouped: Dict[str, List[object]] = defaultdict(list)
    for session in sessions:
        started = _value(session, "started_at") or _value(session, "created_at")
        if isinstance(started, str):
            started = dt.datetime.fromisoformat(started)
        if not isinstance(started, dt.datetime):
            continue
        if interval == "month":
            key = started.strftime("%Y-%m")
        elif interval == "week":
            year, week, _ = started.isocalendar()
            key = "%s-W%02d" % (year, week)
        else:
            key = started.strftime("%Y-%m-%d")
        grouped[key].append(session)
    series = []
    for key, rows in sorted(grouped.items()):
        duration = sum(float(_value(row, "duration_seconds", 0) or 0) for row in rows)
        count = len(rows)
        tuning_rows = [
            row
            for row in rows
            if _value(row, "notes_count") is None or int(_value(row, "notes_count", 0) or 0) > 0
        ]
        avg_abs = duration_weighted_mean(tuning_rows, "average_abs_cents", "duration_seconds") or 0.0
        in_tune = duration_weighted_mean(tuning_rows, "in_tune_percentage", "duration_seconds") or 0.0
        series.append(
            {
                "period": key,
                "sessions": count,
                "practice_minutes": round(duration / 60.0, 2),
                "avg_abs_cents": avg_abs,
                "in_tune_percentage": in_tune,
            }
        )
    return series


def calculate_most_improved_notes(current_period: Iterable[Dict[str, object]], previous_period: Iterable[Dict[str, object]]) -> List[Dict[str, object]]:
    previous = {str(row["note_label"]): row for row in previous_period}
    improved = []
    for current in current_period:
        label = str(current["note_label"])
        prior = previous.get(label)
        if not prior:
            continue
        if float(current.get("duration_seconds", 0)) < 3 or float(prior.get("duration_seconds", 0)) < 3:
            continue
        improvement = float(prior["avg_abs_cents"]) - float(current["avg_abs_cents"])
        if improvement > 0:
            improved.append({**current, "previous_avg_abs_cents": prior["avg_abs_cents"], "improvement": improvement})
    return sorted(improved, key=lambda row: float(row["improvement"]), reverse=True)


def calculate_period_bounds(
    date_from: Optional[dt.datetime] = None,
    date_to: Optional[dt.datetime] = None,
    as_of: Optional[dt.datetime] = None,
) -> Dict[str, dt.datetime]:
    current_end = date_to or as_of or dt.datetime.utcnow()
    if date_from:
        current_start = date_from
        period_length = current_end - current_start
        if period_length.total_seconds() <= 0:
            period_length = dt.timedelta(days=7)
    else:
        period_length = dt.timedelta(days=7)
        current_start = current_end - period_length
    previous_end = current_start
    previous_start = previous_end - period_length
    return {
        "current_start": current_start,
        "current_end": current_end,
        "previous_start": previous_start,
        "previous_end": previous_end,
    }


def calculate_practice_consistency(sessions: Iterable[object], today: Optional[dt.date] = None) -> Dict[str, object]:
    today = today or dt.date.today()
    week_start = today - dt.timedelta(days=today.weekday())
    practiced_days = set()
    for session in sessions:
        started = _value(session, "started_at") or _value(session, "created_at")
        if isinstance(started, str):
            started = dt.datetime.fromisoformat(started)
        if isinstance(started, dt.datetime):
            practiced_days.add(started.date())
    this_week = [day for day in practiced_days if week_start <= day <= today]
    streak = 0
    cursor = today
    while cursor in practiced_days:
        streak += 1
        cursor -= dt.timedelta(days=1)
    return {
        "current_week_practice_days": len(this_week),
        "days_in_week": 7,
        "practice_days_label": "%d of 7 days practiced" % len(this_week),
        "practice_streak_days": streak,
    }


def calculate_progress_metrics(user_id: int, sessions: Iterable[object], current_stats=None, previous_stats=None) -> Dict[str, object]:
    session_list = list(sessions)
    total_time = sum(float(_value(session, "duration_seconds", 0) or 0) for session in session_list)
    consistency = calculate_practice_consistency(session_list)
    current_stats = current_stats or []
    previous_stats = previous_stats or []
    worst = sorted(current_stats, key=lambda row: float(row.get("avg_abs_cents", 0)), reverse=True)[:5]
    sharp = sorted(
        [row for row in current_stats if float(row.get("avg_signed_cents", 0)) > 0],
        key=lambda row: float(row.get("avg_signed_cents", 0)),
        reverse=True,
    )[:5]
    flat = sorted(
        [row for row in current_stats if float(row.get("avg_signed_cents", 0)) < 0],
        key=lambda row: float(row.get("avg_signed_cents", 0)),
    )[:5]
    return {
        "user_id": user_id,
        "total_practice_time_seconds": total_time,
        "session_count": len(session_list),
        "average_session_length_seconds": total_time / len(session_list) if session_list else 0,
        "timeseries": calculate_progress_timeseries(session_list),
        "consistency": consistency,
        "most_improved_notes": calculate_most_improved_notes(current_stats, previous_stats),
        "worst_notes": worst,
        "most_consistently_sharp_notes": sharp,
        "most_consistently_flat_notes": flat,
    }
