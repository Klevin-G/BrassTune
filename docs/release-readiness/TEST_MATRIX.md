# Release Test Matrix

## Current Run Update - 2026-06-20 UTC

| Journey/Gate | Command | Result | Notes |
|---|---|---|---|
| Backend regression suite | `cd backend && .venv/bin/python -m pytest` | Passed: `53 passed`, `5 warnings` | Warnings are Pydantic/FastAPI deprecations. |
| Web unit tests | `cd frontend && npm test` | Passed: `8` files, `27` tests | Includes new metronome and score-practice domain tests. |
| Web build/typecheck | `cd frontend && npm run build` | Passed | Vite large chunk warning remains, JS about `904 kB` minified. |
| Frontend dependency audit | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities` | Dev dependencies excluded. |
| Swift package parity smoke | `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift tests | Native app UI/build tests not rerun yet in this current run. |
| Browser E2E local | `cd frontend && npm run e2e:local` | Passed: `75 passed` | Chromium, Firefox, WebKit, mobile Chromium, and mobile WebKit. |
| Device simulation | `cd frontend && npm run simulate:devices` | Passed | Refreshed `docs/device-simulation-report.md` and screenshots. |
| Rendered browser spot check | Browser plugin against `http://127.0.0.1:5173` | Passed | Metronome Tap tempo changed BPM/status; score-practice import controls rendered with no console errors/overlap. |
| Backend Bandit | `cd backend && .venv/bin/python -m bandit -r app -x app/tests` | Passed: no issues | Bandit emitted comment-token warnings only. |
| Backend pip-audit | `cd backend && .venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt` | Failed: `7` advisories | Starlette, pytest, python-dotenv dependency remediation required. |
| Live provider lifecycle | Env-gated/manual | Blocked | Requires disposable Supabase/Apple/Google provider setup. |
| Physical microphone/device | Manual protocol | Blocked | Requires supported iPhone/iPad hardware and real brass. |

| Journey/Gate | Persona | Environment | Automation | Command | Result | Evidence | Blocker |
|---|---|---|---|---|---|---|---|
| Backend regression suite | API users | Local venv | Pytest | `cd backend && .venv/bin/python -m pytest` | Passed: `48 passed` | Terminal output | None |
| Web unit tests | Web user | Local | Vitest | `cd frontend && npm test` | Passed: `16 tests` | Terminal output | None |
| Web build/typecheck | Web app | Local | npm/Vite | `cd frontend && npm run build` | Passed | Terminal output | Large chunk warning only |
| Frontend dependency audit | Web app | Local | npm audit | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities` | Terminal output | None |
| Browser critical routes | Guest | Local Chromium/Firefox/WebKit/mobile | Playwright | `cd frontend && CI=true npm run e2e:local` | Passed: `30 passed` after mobile WebKit demo recording timing fix | `frontend/e2e/release-journeys.spec.ts` | Hosted-only API/WS checks run through `npm run e2e:hosted` / `npm run smoke:hosted`; verify latest Frontend Action before merge |
| Auth reset/Apple surfaces | Guest/auth user | Local mocked Supabase config | Playwright | `npm run e2e:local` | Passed for disabled/mocked surfaces | `WEB_E2E_REPORT.md` | Live Supabase/Apple provider not configured |
| Demo tuner recording/session review | Guest | Local browser | Playwright | `npm run e2e:local` | Passed across desktop/mobile browser projects | `WEB_E2E_REPORT.md` | Real microphone quality not covered |
| Settings export before delete | Signed-in surface | Local browser | Playwright | `npm run e2e:local` | Passed | `WEB_E2E_REPORT.md` | Live deletion requires credentials |
| Server-side ensemble forbidden write | Student/director | Local backend | Playwright API request | `npm run e2e:local` | Passed: student 403, director 200 | `frontend/e2e/release-journeys.spec.ts` | Broader live personas unavailable |
| Web device simulation | Guest/demo | Local browser screenshots | Node/Playwright | `cd frontend && npm run simulate:devices` | Passed | `docs/device-simulation-report.md` | Generated screenshot diffs are artifacts |
| Swift package parity smoke | Domain logic | Local SwiftPM | XCTest | `cd swift/BrassTuneCore && swift test` | Passed: `3 tests` | Terminal output | Parity breadth still limited |
| Native app unit tests | Native app | iPhone simulator | XCTest | `xcodebuild test ... -scheme BrassTuneApp ... -only-testing:BrassTuneAppTests` | Passed locally and in GitHub Swift on PR head `91ca605...` | Local xcodebuild output and GitHub Actions | None for simulator unit scope |
| Native app UI smoke | Native app | iPhone simulator | XCUITest | `xcodebuild test ... -scheme BrassTuneAppUISmoke ... -only-testing:BrassTuneAppUITests/BrassTuneAppUITests/testLaunchPracticeAndSettingsSurfaces` | Passed locally and in GitHub Swift on PR head `91ca605...`; prior head `d05fe773...` failed before nested-observable fix | Local xcodebuild output, `/tmp/BrassTuneAppUISmoke.xcresult`, and GitHub Actions | Physical microphone/signing not covered |
| Native Debug builds | iPhone/iPad | Dynamically selected iOS simulators | xcodebuild | `xcodebuild clean build ... Debug ... CODE_SIGNING_ALLOWED=NO` | Passed on iPhone 17 Pro and iPad Pro 13-inch simulators | `/tmp/brasstune-dd-debug-iphone-handoff-final`, `/tmp/brasstune-dd-debug-ipad-handoff-final` | No signing/archive |
| Native Release build | iPhone | Dynamically selected iOS simulator | xcodebuild | `xcodebuild clean build ... Release ... CODE_SIGNING_ALLOWED=NO` | Passed | `/tmp/brasstune-dd-release-iphone-handoff-final` | No signing/archive |
| Vercel root/deep link | Public web | Hosted | curl | `curl -IL https://brass-tune.vercel.app[/settings]` | Passed: `HTTP/2 200` | Terminal output | None |
| Render health/CORS | Public API | Hosted | curl | `curl /api/health`, `OPTIONS /api/health` | Passed after cold start | Terminal output | Cold start latency |
| Hosted production root/API/WS smoke | Public web/API | Hosted | Node script | `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` | Passed | Terminal output | Strict post-merge content check still required after production deploy |
| Production smoke workflow | Public web/API | GitHub Actions | Scheduled/manual workflow | `.github/workflows/production-smoke.yml` | Added, not run in this docs pass | Workflow file | Requires GitHub Actions run after merge/deploy for fresh evidence |
| Render keepalive workflow | Public API | GitHub Actions | Scheduled/manual workflow | `.github/workflows/render-keepalive.yml` | Added, not run in this docs pass | Workflow file | Cold-start mitigation only; not uptime guarantee |
| Hosted preview API/WS smoke | PR preview/API | Hosted | Node/Playwright script | `BRASSTUNE_WEB_BASE_URL=https://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app ... npm run smoke:hosted` | Passed with protected-page skips: `15 passed`, `20 skipped`; health, CORS, and raw WebSocket upgrade passed | Terminal output | Page journeys require Vercel preview auth bypass or public preview access |
| Hosted WebSocket handshake | Web/API | Hosted | Node WebSocket | `wss://brasstune.onrender.com/ws/pitch` | Passed: opens and returns auth-required app message | Terminal output | Live authenticated WS requires credentials |
| Protected Vercel preview routes | Guest | Hosted preview | Playwright | `E2E_BASE_URL=... E2E_VERCEL_SHARE_URL=... npm run e2e:hosted -- --project=chromium` | Skipped by default without share URL because preview returns Vercel login `401`; API/CORS/WS tests still pass | Terminal output | Requires Vercel automation bypass or unprotected preview |
| GitHub Actions | PR #2 | Hosted CI | GitHub Actions | Backend, Frontend, Security, Swift, Vercel | Passed on PR head `91ca605b64a58e582b2e8f6b2d06c9f80ba3b6c7` | GitHub connector check: Backend, Frontend, Security, Swift completed success; Vercel commit status success | Re-check latest head if docs or code change before merge |
| Supabase clean baseline | Backend data | Live Supabase project | Supabase migrations | `20260616_brasstune_baseline`, `20260617_brasstune_production_readiness` | Passed: nine public app tables, RLS enabled, zero rows | Supabase MCP output | None for baseline |
| Supabase RPC drift | Backend data | Live Supabase project | Supabase migration/query | `20260618_lock_down_rls_auto_enable` | Passed: `anon_execute=false`, `authenticated_execute=false` | Supabase MCP output | None for that finding |
| Local secret scan | Repo history | Local | Gitleaks | `gitleaks detect --redact --verbose` | Not run in final local pass: tool unavailable | Terminal output | GitHub Security workflow passed |
| Backend security scans | Backend | Local | pip-audit/Bandit | `pip-audit ...`, `bandit -r app -x app/tests` | Not run in final local pass: tools unavailable | Terminal output | GitHub Security workflow passed |
| Live Supabase auth lifecycle | User | Hosted/live Supabase | Environment-gated tests | Not run | Blocked | `HUMAN_ACTIONS.md` | Requires credentials and disposable project/users |
| Live auth test plan | User | Hosted/live Supabase | Manual/env-gated | `docs/release-readiness/LIVE_AUTH_TEST_PLAN.md` | Added, not executed | Doc | Requires owner/provider setup |
| Closed-beta QA script | Beta testers | Hosted/native simulator | Manual | `docs/release-readiness/BETA_QA_GUIDE.md` | Added, not executed | Doc | Requires tester run evidence |
| Load/abuse smoke | Public web/API | Hosted | Manual low-volume smoke | `docs/release-readiness/LOAD_ABUSE_SMOKE.md` | Added, not executed | Doc | Owner-approved time window required |
| App Store archive/signing | iOS app | Apple Developer/App Store Connect | xcodebuild/archive | Not run | Blocked | `APP_STORE_CHECKLIST.md` | Requires Apple credentials |
| Physical audio quality | Brass players | Physical devices | Manual protocol | Not run | Blocked | `PHYSICAL_DEVICE_PROTOCOL.md` | Requires hardware and players |
