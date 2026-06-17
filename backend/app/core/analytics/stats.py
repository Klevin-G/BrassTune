import datetime as dt
import statistics
from collections import defaultdict
from typing import Dict, Iterable, List, Optional, Tuple


def _value(row, key, default=None):
    if isinstance(row, dict):
        return row.get(key, default)
    return getattr(row, key, default)


def _note_key(event) -> Tuple[str, int]:
    return (str(_value(event, "written_note")), int(_value(event, "written_octave")))


def calculate_note_stats(events: Iterable[object]) -> List[Dict[str, object]]:
    grouped: Dict[Tuple[str, int], List[object]] = defaultdict(list)
    for event in events:
        if _value(event, "written_note") is not None:
            grouped[_note_key(event)].append(event)

    stats: List[Dict[str, object]] = []
    for (note, octave), rows in grouped.items():
        duration = sum(float(_value(row, "duration_ms", 0)) for row in rows)
        if duration <= 0:
            duration = float(len(rows))
        signed = sum(float(_value(row, "avg_signed_cents", 0)) * float(_value(row, "duration_ms", 1)) for row in rows)
        absolute = sum(float(_value(row, "avg_abs_cents", 0)) * float(_value(row, "duration_ms", 1)) for row in rows)
        in_tune = sum(float(_value(row, "in_tune_percentage", 0)) * float(_value(row, "duration_ms", 1)) for row in rows)
        all_cents = [float(_value(row, "avg_signed_cents", 0)) for row in rows]
        sample_count = sum(int(_value(row, "sample_count", 0)) for row in rows)
        stability = sum(float(_value(row, "stability_score", 0)) * float(_value(row, "duration_ms", 1)) for row in rows)
        avg_signed = signed / duration
        avg_abs = absolute / duration
        stddev = statistics.pstdev(all_cents) if len(all_cents) > 1 else float(_value(rows[0], "stddev_cents", 0))
        row = {
            "written_note": note,
            "written_octave": octave,
            "note_label": "%s%s" % (note, octave),
            "avg_signed_cents": avg_signed,
            "avg_abs_cents": avg_abs,
            "median_cents": statistics.median(all_cents),
            "stddev_cents": stddev,
            "in_tune_percentage": in_tune / duration,
            "duration_ms": duration,
            "duration_seconds": duration / 1000.0,
            "sample_count": sample_count,
            "event_count": len(rows),
            "stability_score": stability / duration,
        }
        row["trend"] = classify_note_trend(row)
        row["severity"] = classify_note_problem(row)
        row["problem_severity"] = problem_score(row)
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
    if signed >= 6:
        return "Mostly sharp"
    if signed <= -6:
        return "Mostly flat"
    return "Centered"


def problem_score(note_stats: Dict[str, object]) -> float:
    avg_abs = float(note_stats.get("avg_abs_cents", 0))
    stddev = float(note_stats.get("stddev_cents", 0))
    in_tune = float(note_stats.get("in_tune_percentage", 0))
    return round(avg_abs * 2 + stddev + max(0.0, 80 - in_tune) * 0.25, 2)


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
        avg_abs = statistics.fmean([float(_value(row, "average_abs_cents", 0) or 0) for row in rows])
        in_tune = statistics.fmean([float(_value(row, "in_tune_percentage", 0) or 0) for row in rows])
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

