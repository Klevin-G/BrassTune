# BrassTune Release Baseline

Date: 2026-06-18

## Repository State

- Working directory: `/Users/aryasalem/Downloads/BrassTune`
- Current branch: `arya/release-readiness-hardening`
- Starting deployed branch verified: `main`
- Current HEAD at continuation baseline: `a77a669460aece83f395f7acda879a67e54f0c12`
- Merge base with `main`: `652a787c2e643542dfac5911820a2fed01885622`
- `swift-migration` fact: local branch exists at `2d44e24...` and is behind `main`; current work stayed on a new release branch from `main`.
- Dirty state at start of hosted-beta continuation: clean at `e56cacd61114cd453b21d3d6d597b702e30e67a9`. Current working tree contains intentional post-deploy docs/evidence updates until the final commit is created.

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
| Backend | `cd backend && .venv/bin/python -m pytest` | Passed after fixes: `47 passed, 5 warnings`. |
| Frontend | `cd frontend && npm test` | Passed: `15 tests` across `5` files. |
| Frontend | `cd frontend && npm run build` | Passed; Vite emitted the pre-existing large chunk warning. |
| Frontend | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities`. |
| Browser | `cd frontend && npm run e2e:local` | Passed: `35 passed`, `10 skipped` across Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit. |
| Device simulation | `cd frontend && npm run simulate:devices` | Passed and updated `docs/device-simulation-report.md` plus screenshots. |
| Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3 tests`. |
| Hosted browser smoke | `cd frontend && E2E_BASE_URL=... E2E_API_BASE_URL=... E2E_WS_BASE_URL=... npm run e2e:hosted` | Passed: `15 passed`. Strict branch-content checks remain post-deploy. |
| Native project list | `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj` | Passed; schemes `BrassTuneApp`, `BrassTuneCore`. |
| Native Debug/unit/UI | `xcodebuild test ... -only-testing:BrassTuneAppTests -only-testing:BrassTuneAppUITests/...` | Passed on dynamically selected iPhone simulator: `3 unit`, `1 UI`. |
| Native Release build | `xcodebuild ... -configuration Release ... CODE_SIGNING_ALLOWED=NO build` | Passed on dynamically selected iPhone simulator. |
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
