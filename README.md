# BrassTune Analytics

BrassTune Analytics is a local MVP for brass musicians who want to understand recurring intonation patterns, not only whether a single note is in tune right now.

The project includes:

- React + TypeScript + Vite frontend
- Python + FastAPI backend
- SQLite persistence with SQLAlchemy
- Real pitch math, transposition, note event segmentation, analytics, heat maps, exports, and deterministic recommendations
- WebSocket pitch streaming with Aubio support when installed and a NumPy autocorrelation fallback
- Demo mode so the tuner and recording flow work without a microphone
- Seeded local data for dashboard, progress, coach, and ensemble views

## Project Structure

```text
frontend/
  src/components/
  src/pages/
  src/hooks/
  src/api/
  src/domain/
  src/state/

backend/
  app/api/
  app/core/pitch/
  app/core/music/
  app/core/analytics/
  app/core/recommendations/
  app/core/instruments/
  app/core/sessions/
  app/core/ensemble/
  app/db/
  app/models/
  app/schemas/
  app/services/
  app/tests/

docs/
  architecture.md
  swift-porting-notes.md
  pitch-detection-notes.md
```

## Windows Setup

These commands assume Windows PowerShell from the project root.

```powershell
cd C:\path\to\BrassTune
```

Install Python 3.11+ and Node.js 20+ first. Then open two PowerShell windows.

If PowerShell blocks virtualenv activation, run this once in that PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Backend Setup

PowerShell window 1:

```powershell
cd backend
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The backend initializes SQLite and seeds demo data on startup. The database file is created at `backend/data/brasstune.db`.

Run the seed script manually if needed:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m app.db.seed
```

## Frontend Setup

PowerShell window 2:

```powershell
cd frontend
npm install
npm run dev
```

Open [http://localhost:5173](http://localhost:5173). Vite proxies `/api` and `/ws` to the FastAPI server on port `8000`.

## Demo Mode

Demo mode is enabled by default. It simulates believable brass pitch patterns, including:

- Trumpet written D5 consistently sharp
- G4 slightly flat
- C5 unstable
- A4 improving in seeded progress data

Start a recording in demo mode, wait a few seconds, then stop. The frontend stores valid demo pitch frames through the REST API and the session review page will show real computed analytics.

Pitch frames must reach at least 95% confidence before the app treats them as recordable tuning data. Lower-confidence demo or live frames show as unstable/no-lock instead of being saved into session analytics.

## Microphone Mode

Turn off Demo in the top bar or Settings, then use the Practice page's microphone button. The browser asks for microphone permission and streams mono PCM frames to `WS /ws/pitch`.

Recording persistence is single-source:

- Demo mode generates `PitchFrame` objects in the browser and saves them through `POST /api/sessions/{id}/samples`.
- Microphone mode sends PCM to the WebSocket; the backend detects pitch and batch-saves valid frames when `session_id` is present.

Friendly failure states are shown for denied permission, missing browser audio APIs, backend/WebSocket disconnects, silence, and unstable pitch.

The browser streams 4096-sample audio frames to give the detector more context for steady notes. That adds a little live-tuner latency, but improves stability for low brass and noisy rooms.

## Aubio and Librosa

The backend tries Aubio when it is installed, then falls back to a lightweight NumPy YIN-style detector if Aubio is unavailable. The MVP does not require Aubio to run locally.

Optional install:

```powershell
python -m pip install aubio librosa
```

On some systems Aubio may need native build tools. If installation fails, keep using the fallback detector.

## Tests

Backend tests:

```powershell
cd backend
.\.venv\Scripts\Activate.ps1
python -m pytest
```

Frontend unit tests, build, and audit:

```powershell
cd frontend
npm test
npm run build
npm audit --omit=dev
```

Full device simulation:

```powershell
cd frontend
npm run simulate:devices
```

The device simulation starts the backend and frontend automatically if they are not already running. It saves the browser report to `docs/device-simulation-report.md` and screenshots to `docs/assets/device-simulation/`.

## Key API Routes

- `GET /api/health`
- `GET /api/instruments`
- `POST /api/sessions/start`
- `POST /api/sessions/{session_id}/samples`
- `POST /api/sessions/{session_id}/stop`
- `GET /api/sessions/{session_id}/analytics`
- `GET /api/analytics/notes`
- `GET /api/analytics/progress`
- `GET /api/analytics/heatmap`
- `GET /api/recommendations`
- `GET /api/practice-plan`
- `GET /api/export/session/{session_id}.csv`
- `GET /api/export/session/{session_id}.json`
- `GET /api/export/note-events/{session_id}.csv`
- `GET /api/ensemble/summary`
- `GET /api/ensemble/report`
- `WS /ws/pitch`

## Known Limitations

- Authentication is intentionally omitted; the MVP uses a default local user and seeded demo users.
- Pitch detection quality depends on microphone, room noise, and browser audio frame timing. Session analytics now reject pitch frames below 95% confidence rather than storing questionable tuning data.
- The fallback detector has synthetic tone tests and interpolation, but Aubio or a tuned native detector is still preferred for production tuning accuracy.
- Analytics date filters apply to session `started_at`, and progress improvement compares the selected/current period against the previous equivalent period.
- Heat maps return the full written instrument range, with unrecorded notes shown as insufficient data.
- API paths that persist or analyze instrument-specific data reject unknown `instrument_id` values with HTTP 400 instead of silently treating them as trumpet.
- Ensemble Mode is scaffolded with seeded local data rather than full class management workflows.

## Future iOS Direction

The backend core modules are intentionally plain functions and data-driven profiles. See `docs/swift-porting-notes.md` for how to map the pitch math, `PitchFrame`, `NoteEvent`, analytics, recommendations, and persistence into Swift.
