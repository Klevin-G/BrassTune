from typing import Dict, Iterable, List, Optional

from app.core.analytics.stats import calculate_note_stats
from app.core.recommendations.rules import generate_practice_plan
from app.core.instruments.profiles import get_instrument_profile


def calculate_ensemble_note_stats(group_sessions: Iterable[object]) -> List[Dict[str, object]]:
    events = []
    for session in group_sessions:
        events.extend(getattr(session, "note_events", []))
    return calculate_note_stats(events)


def calculate_section_summary(group_sessions: Iterable[object], instrument_id: Optional[str] = None) -> Dict[str, object]:
    sessions = [session for session in group_sessions if instrument_id is None or getattr(session, "instrument_id", None) == instrument_id]
    events = []
    for session in sessions:
        events.extend(getattr(session, "note_events", []))
    note_stats = calculate_note_stats(events)
    total_seconds = sum(float(getattr(session, "duration_seconds", 0) or 0) for session in sessions)
    avg_abs = sum(float(getattr(session, "average_abs_cents", 0) or 0) for session in sessions) / len(sessions) if sessions else 0
    return {
        "instrument_id": instrument_id or "all",
        "session_count": len(sessions),
        "practice_minutes": round(total_seconds / 60.0, 2),
        "average_abs_cents": avg_abs,
        "top_problem_notes": sorted(note_stats, key=lambda row: float(row.get("problem_severity", 0)), reverse=True)[:5],
    }


def calculate_ensemble_summary(group_id: int, group_sessions: Iterable[object]) -> Dict[str, object]:
    sessions = list(group_sessions)
    sections = sorted(set(getattr(session, "instrument_id", "trumpet") for session in sessions))
    return {
        "group_id": group_id,
        "session_count": len(sessions),
        "sections": [calculate_section_summary(sessions, section) for section in sections],
        "overall": calculate_section_summary(sessions, None),
    }


def calculate_section_trends(group_id: int, group_sessions: Iterable[object], instrument_id: str, date_range=None) -> Dict[str, object]:
    return {"group_id": group_id, **calculate_section_summary(group_sessions, instrument_id)}


def generate_rehearsal_report(group_id: int, group_sessions: Iterable[object], date_range=None) -> Dict[str, object]:
    summary = calculate_ensemble_summary(group_id, group_sessions)
    top = summary["overall"]["top_problem_notes"]
    profile = get_instrument_profile(str(top[0].get("instrument_id", "trumpet")) if top else "trumpet")
    plan = generate_practice_plan(top, profile)
    return {
        "group_id": group_id,
        "date_range": date_range or "seeded local MVP data",
        "instrument_section": "all brass",
        "top_problem_notes": top,
        "average_tuning_error": summary["overall"]["average_abs_cents"],
        "recommended_rehearsal_focus": plan["coach_message"],
        "suggested_long_tone_sequence": [step["detail"] for step in plan["steps"]],
        "sections": summary["sections"],
    }

