# BrassTune Release Baseline

Date: 2026-06-18

## Repository State

- Working directory: `/Users/aryasalem/Downloads/BrassTune`
- Current branch: `arya/release-readiness-hardening`
- Starting deployed branch verified: `main`
- Current HEAD at baseline: `652a787c2e643542dfac5911820a2fed01885622`
- Merge base with `main`: `652a787c2e643542dfac5911820a2fed01885622`
- `swift-migration` fact: local branch exists at `2d44e24...` and is behind `main`; current work stayed on a new release branch from `main`.
- Dirty state at start of implementation: clean before release branch work; dirty state now contains intentional source, workflow, native app, E2E, AGENTS, and release-readiness doc changes.

## Toolchain

- Node: `v22.22.3`
- npm: `10.9.8`
- Python command: `python` was unavailable in the shell.
- Python 3: `Python 3.9.6`
- Backend test Python: `backend/.venv/bin/python`
- Swift: `Apple Swift version 6.2.3`
- Xcode: `Xcode 26.2`, build `17C52`
- iOS runtime: `iOS 26.2 (23C54)`
- Available simulators verified: `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, `iPad Pro 11-inch (M5)`

## Existing CI Workflows

- `.github/workflows/backend.yml`
- `.github/workflows/frontend.yml`
- `.github/workflows/security.yml`
- `.github/workflows/device-simulation.yml`
- `.github/workflows/deploy.yml`
- Added in this pass: `.github/workflows/swift.yml`

## Config Names Only

No secret values were printed or committed. Local/example config names observed:

- Supabase: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_JWKS_URL`, `SUPABASE_JWT_SECRET`, `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`
- Backend/API: `APP_ENV`, `DATABASE_URL`, `BRASSTUNE_DATABASE_URL`, `BACKEND_PUBLIC_URL`, `CORS_ALLOWED_ORIGINS`, `CORS_ALLOWED_ORIGIN_REGEX`, `SESSION_AUDIO_STORAGE_BACKEND`, `SUPABASE_STORAGE_BUCKET`, `SESSION_AUDIO_MAX_BYTES`
- Vercel: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `VITE_API_BASE_URL`, `VITE_WS_BASE_URL`
- Render: `RENDER_API_KEY`, `RENDER_SERVICE_ID`, `RENDER_DEPLOY_HOOK_URL`, `RENDER_BACKEND_URL`

## Baseline Commands

| Area | Command | Result |
|---|---|---|
| Backend | `cd backend && python -m pytest` | Failed: `python` command not found. |
| Backend | `cd backend && .venv/bin/python -m pytest` | Passed after fixes: `41 passed, 5 warnings`. |
| Frontend | `cd frontend && npm test` | Passed: `13 tests` across `5` files. |
| Frontend | `cd frontend && npm run build` | Passed; Vite emitted the pre-existing large chunk warning. |
| Frontend | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities`. |
| Browser | `cd frontend && npm run e2e` | Passed after adding Playwright journeys: `24 passed` across Chromium, Firefox, WebKit, mobile Chromium. |
| Device simulation | `cd frontend && npm run simulate:devices` | Passed and updated `docs/device-simulation-report.md` plus screenshots. |
| Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3 tests`. |
| Native Debug build | `xcodebuild ... -configuration Debug ... clean build` | Passed on iPhone 17 simulator. |
| Native Release build | `xcodebuild ... -configuration Release ... clean build` | Passed on iPhone 17 simulator. |
| Native iPad Debug build | `xcodebuild ... iPad Pro 11-inch (M5) ... clean build` | Passed. |
| Native app unit tests | `xcodebuild test ... -only-testing:BrassTuneAppTests` | Passed on a fresh temporary iPhone 17 simulator: `3 tests`. |
| Native UI smoke | `xcodebuild test ... -only-testing:BrassTuneAppUITests/...` | Passed on a fresh temporary iPhone 17 simulator: `1 test`. |

## Hosted Smoke

| Surface | Command | Result |
|---|---|---|
| Vercel root | `curl -IL --max-time 30 https://brass-tune.vercel.app` | Passed: `HTTP/2 200`, `server: Vercel`. |
| Vercel deep link | `curl -IL --max-time 30 https://brass-tune.vercel.app/settings` | Passed: `HTTP/2 200`, `filename="index.html"`. |
| Render health | `curl -fsS --max-time 70 https://brasstune.onrender.com/api/health` | Passed after cold start: `{"ok":true,"service":"BrassTune Analytics API"}`. |
| Render CORS | `OPTIONS /api/health` from Vercel origin | Passed after warmup: `access-control-allow-origin: https://brass-tune.vercel.app`. |
| Hosted WebSocket | `wss://brasstune.onrender.com/ws/pitch` and `/api/ws/pitch` probes | Failed: hosted service returned `404 Not Found`; local backend has `/ws/pitch`, so Render appears out of sync or not routing WebSockets. |
