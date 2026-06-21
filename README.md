# BrassTune Analytics

BrassTune Analytics is a local MVP for brass musicians who want to understand recurring intonation patterns, not only whether a single note is in tune right now.

The project includes:

- React + TypeScript + Vite frontend
- Python + FastAPI backend
- SQLite persistence with SQLAlchemy
- Real pitch math, transposition, note event segmentation, analytics, heat maps, exports, relistenable audio, and deterministic recommendations
- WebSocket pitch streaming with Aubio support when installed and a NumPy autocorrelation fallback
- Demo mode so the tuner and recording flow work without a microphone
- Optional Supabase Auth/Storage/Postgres production integration
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
  deployment.md
  supabase-integration.md
  security-review.md
  phone-microphone-test-report.md
  manual-test-plan.md
  swift-migration-plan.md
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
python -m pip install -r requirements-dev.txt
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

Demo recordings also generate a short synthetic WAV so Sessions and Session Review can exercise relisten/playback UI without a real microphone.

Pitch frames must reach at least 95% confidence before the app treats them as recordable tuning data. Lower-confidence demo or live frames show as unstable/no-lock instead of being saved into session analytics.

`No lock` means the detector confidence is too low to trust, so the frame is excluded from recordings. `Unstable pitch` means the detector has a high-confidence lock, but the player's cents values vary enough over time for analytics to flag a stability problem.

## Microphone Mode

Turn off Demo in the top bar or Settings, then use the Practice page's microphone button. The browser asks for microphone permission and analyzes mono PCM frames locally for guest live tuning. This path does not require login, Supabase, Render, or an authenticated WebSocket.

Recording persistence is single-source:

- Demo mode generates `PitchFrame` objects in the browser and saves them through `POST /api/sessions/{id}/samples`.
- Guest microphone mode derives pitch frames in the browser and stores guest practice on this device.
- Signed cloud sync and backend diagnostics use the WebSocket path when account infrastructure is configured.

Friendly failure states are shown for denied permission, missing browser audio APIs, cloud sync disconnects, silence, and unstable pitch.

The browser streams 4096-sample audio frames to give the detector more context for steady notes. That adds a little live-tuner latency, but improves stability for low brass and noisy rooms.

When recording, the browser also captures playback audio with `MediaRecorder`. On stop, audio uploads to `POST /api/sessions/{id}/audio`. Local MVP mode stores files under `backend/data/audio/`; Supabase mode stores private objects in the `session-audio` bucket and serves signed playback URLs through the backend.

## Local Video and Audio Imports

Practice includes a local media import panel for students who record in the native Camera app or already have a video in Photos/Files.

- Choose a local audio/video file, or use the `Camera` button on mobile to open the native camera picker.
- BrassTune decodes the media audio in the browser and runs local YIN-style pitch detection.
- The original video/audio file is not uploaded or stored by BrassTune.
- Only derived pitch frames are saved into the normal session analytics pipeline.
- The local MVP analyzes the first few minutes of a file to keep phone browsers responsive.

If a browser cannot decode a specific video container, export audio or use a browser-supported MP4/WebM/M4A file.

## Auth and Production Mode

Local development still works as a guest demo. In production, set `APP_ENV=production` and configure Supabase env vars so private endpoints require a Bearer token.

Frontend Supabase env vars:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Backend Supabase env vars:

- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`

See `docs/supabase-integration.md` for Auth, Storage, database, and security notes.

## Audio Calibration Lab

Open `/settings/audio-lab` from Settings or More when validating real microphones. The lab shows raw frequency, note labels, cents, confidence, RMS, sample rate, frame size, detector source, save eligibility, invalid-frame reason, and recent frame history. It observes by default and only saves frames when its recording control is explicitly active.

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

GitHub Actions workflows run backend tests, frontend tests/build/audit, and a manual or scheduled device simulation artifact workflow.
The security workflow runs frontend audit, backend dependency audit, Bandit, and Gitleaks.

Shared JSON fixtures live in `fixtures/` for pitch math, transposition, segmentation, analytics, recommendations, and session audio metadata. Pytest uses them now; `swift/BrassTuneCore` already reads pitch math and transposition fixtures.

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
- `GET /api/export/session/{session_id}.zip`
- `GET /api/export/session/{session_id}/audio`
- `GET /api/export/note-events/{session_id}.csv`
- `GET /api/export/all.json`
- `GET /api/export/all.zip`
- `POST /api/sessions/{session_id}/audio`
- `GET /api/sessions/{session_id}/audio`
- `POST /api/admin/sessions/clear`
- `POST /api/admin/demo-data/reset`
- `POST /api/admin/demo-data/repair`
- `POST /api/dev/repair-demo-data`
- `GET /api/users/me`
- `PATCH /api/users/me`
- `POST /api/users/me/clear-sessions`
- `GET /api/users/me/export.zip`
- `POST /api/ensemble/groups`
- `GET /api/ensemble/groups`
- `POST /api/ensemble/groups/{group_id}/members/by-username`
- `GET /api/ensemble/summary`
- `GET /api/ensemble/report`
- `WS /ws/pitch`

## Deployment

Repo-side deployment scaffolding is included:

- `vercel.json` for the Vercel frontend
- `render.yaml` for the Render backend
- `supabase/migrations/20260617_brasstune_production_readiness.sql`
- `docs/deployment.md`

The expected hosted backend URL is `https://brasstune.onrender.com`. Set `VITE_API_BASE_URL` and `VITE_WS_BASE_URL` in Vercel for phone testing.

## Known Limitations

- Supabase Auth is wired, but live sign-up/sign-in requires Supabase env vars and project configuration.
- Pitch detection quality depends on microphone, room noise, and browser audio frame timing. Session analytics now reject pitch frames below 95% confidence rather than storing questionable tuning data.
- The fallback detector has synthetic tone tests and interpolation, but Aubio or a tuned native detector is still preferred for production tuning accuracy.
- Analytics date filters apply to session `started_at`, and progress improvement compares the selected/current period against the previous equivalent period.
- Heat maps return the full written instrument range, with unrecorded notes shown as insufficient data.
- API paths that persist or analyze instrument-specific data reject unknown `instrument_id` values with HTTP 400 instead of silently treating them as trumpet.
- Ensemble Mode now has group and add-by-username APIs, but invitations and full school roster administration remain future work.
- Real iPhone/iPad microphone behavior still requires manual testing; see `docs/phone-microphone-test-report.md`.

## Future iOS Direction

The backend core modules are intentionally plain functions and data-driven profiles. See `docs/swift-porting-notes.md` and `docs/swift-migration-plan.md`. A starter Swift package lives at `swift/BrassTuneCore` and can be tested with:

```powershell
cd swift\BrassTuneCore
swift test
```
