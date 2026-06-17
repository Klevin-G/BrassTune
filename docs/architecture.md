# Architecture

BrassTune Analytics is split into a React frontend, a FastAPI backend, and a portable domain core.

## Layers

`backend/app/core` contains the important product logic:

- `music/theory.py`: frequency-to-MIDI, MIDI-to-frequency, cents, note naming, transposition, and `PitchFrame`.
- `instruments/profiles.py`: data-driven brass instrument profiles.
- `pitch/detector.py`: Aubio wrapper and NumPy autocorrelation fallback.
- `sessions/segmentation.py`: note event grouping and session summary calculations.
- `analytics/stats.py`: note stats, heat map severity, progress metrics, and improvement comparisons.
- `recommendations/rules.py`: deterministic coaching recommendations and practice plans.
- `ensemble/analytics.py`: local MVP group and section analytics.

`backend/app/api` adapts that logic to REST and WebSocket routes. It should stay thin.

`backend/app/models` and `backend/app/db` own SQLAlchemy/SQLite persistence.

`frontend/src/domain` mirrors the portable pitch math needed for demo mode. UI components do not contain analytics business rules.

## Data Flow

1. Browser captures microphone audio or uses the demo pitch generator.
2. PCM frames are sent to `WS /ws/pitch`, or demo `PitchFrame` objects are saved through `POST /api/sessions/{id}/samples`.
3. Backend pitch detection produces a `PitchFrame`.
4. Valid frames are stored as `PitchSample` rows.
5. Stopping a session rebuilds `NoteEvent` rows from samples.
6. Session summary metrics are persisted on `PracticeSession`.
7. Analytics, heat maps, recommendations, progress, and ensemble reports are computed from stored events and sessions.

## Portability Rules

- FastAPI endpoints do not own musical calculations.
- SQLAlchemy models do not own pitch math.
- Instrument behavior is data-driven through profiles.
- Recommendation rules are deterministic and testable.
- Analytics functions accept plain dicts or model-like objects.
- Browser demo mode uses matching formulas so future client-native behavior can be compared.

## Session Recording

Frames are grouped into note events when consecutive valid samples share the same written note and octave. Short silence or unstable gaps are tolerated up to `220 ms`. Very short note events under `120 ms` are discarded.

## Analytics

Note stats are duration-weighted. A note can be flagged by absolute error, signed sharp/flat tendency, low in-tune percentage, or instability. Heat map severity is based on minimum data and average absolute cents.

## Ensemble Mode

The MVP creates a local group and seeded demo students. Ensemble endpoints aggregate real `PracticeSession` and `NoteEvent` rows, so the page is scaffolded but not static.

