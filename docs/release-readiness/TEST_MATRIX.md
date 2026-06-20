# Release Test Matrix

Updated: 2026-06-20T16:12:23Z
Branch: `arya/release-readiness-hardening`
Baseline SHA: `9b3766bc4241843c52b2a703c7ec923b4105f540`
Evidence state: local commit-ready worktree on top of the baseline SHA; exact-SHA CI must rerun after push.

## Current Local Gates

| Gate | Command | Result | Notes |
|---|---|---|---|
| Frontend unit tests | `cd frontend && npm test` | Passed: `9` files, `34` tests | Includes browser-local pitch detector coverage. |
| Frontend build/typecheck | `cd frontend && npm run build` | Passed | Main JS `382.62 kB`; large Recharts chunk remains split. |
| Frontend dependency audit | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities` | Dev dependencies excluded. |
| Local browser journeys/accessibility | `cd frontend && CI=true npm run e2e:local` | Passed: `75 passed` | Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit. |
| Device simulation | `cd frontend && npm run simulate:devices` | Passed | Refreshed `docs/device-simulation-report.md` and tracked screenshots. |
| Backend hardening target | `cd backend && .venv/bin/python -m pytest app/tests/test_hardening.py -q` | Passed: `43 passed` | Covers same-email Supabase identity no-link regression plus local query-token and unapproved-origin WebSocket rejection. |
| Backend full suite | `cd backend && .venv/bin/python -m pytest -q` | Passed: `59 passed` | Local `.venv` is Python 3.9.6, below the repo floor. |
| Backend requirements audit | `cd backend && uv pip compile --python /Users/aryasalem/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 requirements-dev.txt -o /tmp/... && .venv-audit/bin/python -m pip_audit --no-deps --disable-pip -r /tmp/...` | Passed: no known vulnerabilities | Exact `.venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt` is blocked because `.venv` is Python 3.9.6 and current backend requirements need Python 3.10+. |
| Backend Bandit | `cd backend && .venv/bin/python -m bandit -r app -x app/tests` | Passed | No issues reported. |
| Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift tests | Domain parity smoke only. |
| iOS simulator build | XcodeBuildMCP `build_sim` with `BrassTuneApp`, iPhone 17, iOS 26.2, `CODE_SIGNING_ALLOWED=NO` | Passed | Xcode 26.2, Debug simulator build. |
| iOS app unit tests | XcodeBuildMCP `test_sim` with `-only-testing:BrassTuneAppTests` | Passed: `7 passed` | Simulator-only. |
| iOS UI smoke | XcodeBuildMCP `test_sim` with `BrassTuneAppUISmoke/.../testLaunchPracticeAndSettingsSurfaces` | Passed: `1 passed` | Simulator-only, `UITEST_DEMO=1`, `UITEST_RESET_STATE=1`. |
| Hosted production smoke | `env BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_WEB_ACCESS_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` | Failed: 2 WS hardening checks | Root, health, CORS, and basic WS response passed; query-token rejection and bad-Origin rejection failed because production Render is stale. This is an expected deployment gate, not a local code failure. |
| Smoke script syntax | `node --check scripts/hosted-smoke.mjs` | Passed | Validates the enhanced hosted-smoke script parses. |

## Remote Baseline

The GitHub connector verified PR #2 at `9b3766bc4241843c52b2a703c7ec923b4105f540` before local edits:

| Remote gate | Result |
|---|---|
| PR #2 metadata | Open, mergeable, non-draft; base `main`, head `arya/release-readiness-hardening`. |
| Backend workflow | Completed success. |
| Frontend workflow | Completed success. |
| Security workflow | Completed success. |
| Swift workflow | Completed success. |
| Vercel status | Success for the baseline SHA. |

Remote CI must be rerun after these local changes are committed and pushed. Do not use the baseline SHA as proof for this local worktree.

## Blocked Or Scoped

| Gate | Status | Reason |
|---|---|---|
| Chrome plugin smoke | Blocked | Chrome connector runtime failed before browser commands with missing `sandboxPolicy` metadata. |
| Exact `.venv` requirements audit | Blocked | The repo `.venv` is Python 3.9.6 and cannot resolve the Python 3.10+ FastAPI floor. Use the Python 3.12 uv-resolved audit above plus Security workflow on the exact pushed SHA. |
| Live Supabase auth/provider lifecycle | Blocked | Requires owner-issued Supabase, Google, and Apple provider configuration plus disposable live users. |
| Production exact-SHA smoke | Blocked | Requires owner-approved deploy of the new commit to Vercel/Render. |
| App Store/TestFlight signing | Blocked | Requires Apple Developer team, bundle ID, signing, App Store Connect, and review metadata. |
| Physical microphone/device validation | Blocked | Requires iPhone/iPad hardware and real brass input. |
