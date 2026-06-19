# BrassTune Release Baseline

Date: 2026-06-18

## Repository State

- Working directory: `/Users/aryasalem/Downloads/BrassTune`
- Current branch: `arya/release-readiness-hardening`
- Starting deployed branch verified: `main`
- Original PR continuation baseline: `a77a669460aece83f395f7acda879a67e54f0c12`
- Hosted-beta handoff recheck HEAD: `81285b653bc5e357f79fe41f04b51e93418f541d`
- CI repair baseline HEAD: `fc7ee5db54d7dc7a29fce37eeb67acf83fc70011`; Backend and Security Actions passed, Swift failed at Native app unit tests, and Frontend was stuck at Browser release journeys.
- Swift UI smoke repair baseline HEAD: `d05fe773499393ad50af15c59322f66adeb98c11`; Backend, Frontend, and Security Actions passed, while Swift failed at Native app UI smoke.
- Merge base with `main`: `652a787c2e643542dfac5911820a2fed01885622`
- `swift-migration` fact: local branch exists at `2d44e24...` and is behind `main`; current work stayed on a new release branch from `main`.
- Dirty state at start of hosted-beta continuation: clean at `e56cacd61114cd453b21d3d6d597b702e30e67a9`.
- Dirty state before closed-beta handoff edits: clean at `81285b653bc5e357f79fe41f04b51e93418f541d`.
- Dirty state before CI repair edits: clean at `fc7ee5db54d7dc7a29fce37eeb67acf83fc70011`.
- Dirty state before Swift UI smoke repair edits: clean at `d05fe773499393ad50af15c59322f66adeb98c11`.

## Toolchain

- Node: `v22.22.3`
- npm: `10.9.8`
- Python command: `python` was unavailable in the shell.
- Python 3: `Python 3.9.6`
- Backend test Python: `backend/.venv/bin/python`
- Swift: `Apple Swift version 6.2.3`
- Xcode: `Xcode 26.2`, build `17C52`
- iOS runtime: `iOS 26.2 (23C54)`
- Available simulators verified: `iPhone 17`, `iPhone 17 Pro`, `iPhone 17 Pro Max`, `iPhone Air`, `iPad Pro 13-inch (M5)`, `iPad Pro 11-inch (M5)`

## Existing CI Workflows

- `.github/workflows/backend.yml`
- `.github/workflows/frontend.yml`
- `.github/workflows/security.yml`
- `.github/workflows/device-simulation.yml`
- `.github/workflows/deploy.yml`
- Existing workflow set was preserved and hardened with permissions, timeouts, browser artifacts, and dynamic simulator selection.

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
| Backend | `cd backend && .venv/bin/python -m pytest` | Passed after fixes: `48 passed`. |
| Frontend | `cd frontend && npm test` | Passed: `16 tests`. |
| Frontend | `cd frontend && npm run build` | Passed; Vite emitted the pre-existing large chunk warning. |
| Frontend | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities`. |
| Browser | `cd frontend && npm run e2e:local` | Current CI-repair command passed: `30 passed` across Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit. Hosted smoke is now an explicit command. |
| Device simulation | `cd frontend && npm run simulate:devices` | Passed and updated `docs/device-simulation-report.md` plus screenshots. |
| Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3 tests`. |
| Hosted production smoke | `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` | Passed for root, health, CORS, and WebSocket upgrade/app response. |
| Hosted preview smoke | `BRASSTUNE_WEB_BASE_URL=https://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app ... npm run smoke:hosted` | Passed with protected-page skips: `15 passed`, `20 skipped`; health, CORS, and raw WebSocket upgrade passed. |
| Native project list | `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj` | Passed; schemes `BrassTuneApp`, `BrassTuneAppUISmoke`, `BrassTuneCore`. |
| Native unit | `xcodebuild test ... -only-testing:BrassTuneAppTests` | Current post-fix pass on iPhone 17 Pro simulator: `3` tests. |
| Native UI smoke | `xcodebuild test ... -only-testing:BrassTuneAppUITests/...` | Current post-fix pass on iPhone 17 Pro simulator: `1` XCUITest. |
| Native Debug builds | `xcodebuild clean build ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO` | Passed on iPhone 17 Pro and iPad Pro 13-inch simulators. |
| Native Release build | `xcodebuild clean build ... -configuration Release ... CODE_SIGNING_ALLOWED=NO` | Passed on iPhone 17 Pro simulator. |
| Security | `gitleaks git --redact=100 --verbose .` | Passed: 25 commits scanned, no leaks found. |
| Security | `pip-audit ...` | Passed: no known vulnerabilities found, five documented ignores. |
| Security | `bandit -r app -x app/tests` | Passed: no issues identified. |

## Hosted Smoke

| Surface | Command | Result |
|---|---|---|
| Vercel root | `curl -IL --max-time 30 https://brass-tune.vercel.app` | Passed: `HTTP/2 200`, `server: Vercel`. |
| Vercel deep link | `curl -IL --max-time 30 https://brass-tune.vercel.app/settings` | Passed: `HTTP/2 200`, `filename="index.html"`. |
| Render health | `curl -fsS --max-time 70 https://brasstune.onrender.com/api/health` | Passed after cold start: `{"ok":true,"service":"BrassTune Analytics API"}`. |
| Render CORS | `OPTIONS /api/health` from Vercel origin | Passed after warmup: `access-control-allow-origin: https://brass-tune.vercel.app`. |
| Hosted WebSocket handshake | Node `WebSocket('wss://brasstune.onrender.com/ws/pitch')` ping probe | Initially failed with Uvicorn missing WebSocket protocol support; fixed by `uvicorn[standard]` and verified after Render deploy `dep-d8q7296gvqtc73a0djm0`. |
