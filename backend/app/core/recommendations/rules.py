from typing import Dict, Iterable, List, Optional

from app.core.analytics.stats import classify_note_problem, classify_note_trend
from app.core.instruments.profiles import InstrumentProfile, get_instrument_profile


def _instrument_suggestions(profile: InstrumentProfile, category: str) -> List[str]:
    return profile.recommendation_templates.get(category, [])[:2]


def generate_note_recommendation(note_stats: Dict[str, object], instrument_profile: InstrumentProfile) -> Dict[str, object]:
    label = str(note_stats.get("note_label", "%s%s" % (note_stats.get("written_note"), note_stats.get("written_octave"))))
    signed = float(note_stats.get("avg_signed_cents", 0))
    avg_abs = float(note_stats.get("avg_abs_cents", 0))
    stddev = float(note_stats.get("stddev_cents", 0))
    duration = float(note_stats.get("duration_seconds", 0))
    severity = classify_note_problem(note_stats)
    trend = classify_note_trend(note_stats)
    suggestions: List[str] = []

    if duration < 3:
        title = "More data needed for %s" % label
        message = "You need more recorded attempts on written %s before BrassTune can identify a reliable pattern." % label
        category = "Insufficient data"
        suggestions = ["Record at least three steady long-tone attempts on this note."]
    elif trend == "Unstable":
        title = "%s is inconsistent" % label
        message = "Your pitch on written %s changes too much for BrassTune to call it centered yet." % label
        category = "Inconsistent pitch"
        suggestions = [
            "Hold the note for 8-12 seconds and aim for a steady needle.",
            "Use a drone and focus on minimizing motion.",
            "Record several repetitions with full breaths.",
        ] + _instrument_suggestions(instrument_profile, "unstable")
    elif signed >= 10:
        title = "%s tends sharp" % label
        message = "You consistently play written %s %.0f cents sharp." % (label, abs(signed))
        category = "Sharp tendency"
        suggestions = [
            "Practice slow long tones on this note with a drone.",
            "Start slightly below the pitch and gently center upward.",
            "Check whether you are over-tightening your embouchure.",
        ] + _instrument_suggestions(instrument_profile, "sharp")
    elif signed <= -10:
        title = "%s tends flat" % label
        message = "You consistently play written %s %.0f cents flat." % (label, abs(signed))
        category = "Flat tendency"
        suggestions = [
            "Practice long tones with a drone.",
            "Support the air stream and avoid letting the pitch sag.",
            "Check posture and breath support.",
        ] + _instrument_suggestions(instrument_profile, "flat")
    elif severity == "severe issue":
        title = "%s needs focused intonation work" % label
        message = "Written %s averages %.0f cents away from center." % (label, avg_abs)
        category = "Severe problem note"
        suggestions = [
            "Use a drone and repeat the note in short sets of five.",
            "Approach the note from a neighboring pitch, then sustain it.",
        ]
    else:
        title = "%s is improving" % label
        message = "Written %s is generally centered. Keep reinforcing it in context." % label
        category = "Good progress"
        suggestions = [
            "Play the note inside simple scale patterns.",
            "Try one repetition with the tuner hidden, then check your result.",
        ]

    return {
        "title": title,
        "message": message,
        "severity": severity,
        "category": category,
        "related_note": label,
        "suggested_exercises": suggestions[:5],
        "suggested_focus": trend,
        "explanation": "Generated from average cents, in-tune percentage, stability, and %s profile rules." % instrument_profile.display_name,
    }


def generate_session_recommendations(session_stats: Optional[Dict[str, object]], note_stats: Iterable[Dict[str, object]]) -> List[Dict[str, object]]:
    instrument_id = str((session_stats or {}).get("instrument_id", "trumpet"))
    profile = get_instrument_profile(instrument_id)
    candidates = sorted(note_stats, key=lambda row: float(row.get("problem_severity", row.get("avg_abs_cents", 0))), reverse=True)
    return [generate_note_recommendation(row, profile) for row in candidates[:6]]


def generate_recommendations(note_stats: Iterable[Dict[str, object]], instrument_profile: InstrumentProfile) -> List[Dict[str, object]]:
    candidates = sorted(note_stats, key=lambda row: float(row.get("problem_severity", row.get("avg_abs_cents", 0))), reverse=True)
    return [generate_note_recommendation(row, instrument_profile) for row in candidates[:8]]


def generate_practice_plan(problem_notes: Iterable[Dict[str, object]], instrument_profile: InstrumentProfile) -> Dict[str, object]:
    top = list(problem_notes)[:3]
    focus = [str(row.get("note_label")) for row in top]
    if not focus:
        focus = ["C4", "G4", "A4"]
    worst = focus[0]
    neighboring = " - ".join(focus)
    return {
        "title": "10-minute intonation plan",
        "focus_notes": focus,
        "steps": [
            {"minutes": 2, "label": "Breathing and warmup", "detail": "Use relaxed full breaths, then play easy middle-register long tones."},
            {"minutes": 3, "label": "Worst-note long tones", "detail": "Hold written %s for 8 seconds with a drone, rest 4 seconds, repeat 5 times." % worst},
            {"minutes": 3, "label": "Neighboring-note pattern", "detail": "Play %s as slow connected long tones and center each pitch before moving." % neighboring},
            {"minutes": 2, "label": "Hidden tuner review", "detail": "Play the focus notes once without watching the needle, then check the result."},
        ],
        "coach_message": "Focus on %s. The plan prioritizes your largest recurring intonation patterns for %s." % (", ".join(focus), instrument_profile.display_name),
    }
