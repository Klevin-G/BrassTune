# Release Test Matrix

Updated: 2026-06-21T04:22:00Z
Branch: `main`
Merged PR head: `ede7960fb0f543a8d0b329357199d782257a0d46`
Merged main SHA: `4bda5691a05988471e412519bbfdcf4078430ee0`
Evidence state: PR #2 merged; production Vercel and Render deployed the merge commit; hosted production smoke passed. Remaining native/provider/device gates are outside the web/backend closed-beta pass.

## Current Local Gates

| Gate | Command | Result | Notes |
|---|---|---|---|
| Frontend unit tests | `cd frontend && npm test` | Passed: `9` files, `40` tests | Includes API header merge and score page-cap coverage. |
| Frontend build/typecheck | `cd frontend && npm run build` | Passed | Main JS `382.76 kB`; large Recharts chunk remains split. |
| Frontend dependency audit | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities` | Dev dependencies excluded. |
| Local browser journeys/accessibility | `cd frontend && CI=true npm run e2e:local` | Passed: `75 passed` | Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit. |
| Device simulation | `cd frontend && npm run simulate:devices` | Skipped after hang | Chromium stayed active silently for about six minutes; partial screenshot churn was restored. |
| Backend hardening target | `cd backend && .venv/bin/python -m pytest app/tests/test_hardening.py -q` | Passed: `57 passed` | Adds account deletion re-creation block, ensemble list redaction, JSON body limit, and configurable rate-limit coverage. |
| Backend full suite | `cd backend && .venv/bin/python -m pytest -q` | Passed: `73 passed` | Fresh backend `.venv` is Python 3.12.13. |
| Backend requirements audit | `cd backend && uv pip compile --python /Users/aryasalem/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 requirements-dev.txt -o /tmp/brasstune-pip-audit-requirements.txt && .venv/bin/python -m pip_audit --no-deps --disable-pip -r /tmp/brasstune-pip-audit-requirements.txt` | Passed: no known vulnerabilities | Direct requirements-file audit crashed before vulnerability analysis while creating a temporary resolver venv. |
| Backend Bandit | `cd backend && .venv/bin/python -m bandit -r app -x app/tests` | Passed | No issues reported. |
| Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift tests | Domain parity smoke only. |
| iOS app unit tests | `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination 'id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests` | Passed: `7 passed` | Simulator-only. |
| iOS UI smoke | `xcodebuild test -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination 'id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests/BrassTuneAppUITests/testLaunchPracticeAndSettingsSurfaces -resultBundlePath /tmp/BrassTuneAppUISmoke.xcresult` | Passed: exit `0` | Simulator-only. |
| iOS Release simulator build | `xcodebuild build -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination 'id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO` | Passed | Unsigned simulator build only. |
| Hosted-smoke spec local sanity | `cd frontend && npx playwright test e2e/hosted-smoke.spec.ts --project=chromium` | Passed: `1 passed`, `6 skipped` | Hosted-only checks correctly skip without hosted env vars; route-content assertion matches current Audio Lab copy. |
| Exact-SHA protected preview smoke | `cd frontend && E2E_START_LOCAL_SERVERS=0 E2E_BASE_URL=https://brass-tune-7es12gogt-aryaswebsites.vercel.app E2E_VERCEL_SHARE_URL=... E2E_API_BASE_URL=https://brasstune.onrender.com E2E_WS_BASE_URL=wss://brasstune.onrender.com npm run e2e:hosted -- --project=chromium` | Failed before guest-fetch fix: `5 passed`, `1 failed`, `1 skipped` | Vercel preview for `72bb5a4` was READY and app/API/WS checks passed, but guest route visits logged protected backend `401` calls. The current local fix gates protected cloud fetches for guests and requires a new exact-SHA preview rerun. |
| Hosted production smoke | `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_WEB_ACCESS_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` | Passed: `7` checks | Root, Render health, CORS, browser-origin WS app response, query-token rejection, and bad-Origin rejection passed after Vercel/Render deploy. |
| Smoke script syntax | `node --check scripts/hosted-smoke.mjs` | Passed | Validates the enhanced hosted-smoke script parses. |

## Remote Baseline

GitHub connector checks verified PR #2 at `ede7960fb0f543a8d0b329357199d782257a0d46` before merge:

| Remote gate | Result |
|---|---|
| PR #2 metadata | Open, mergeable, non-draft before merge; merged into `main` as `4bda5691a05988471e412519bbfdcf4078430ee0`. |
| Backend workflow | Completed success. |
| Frontend workflow | Completed success. |
| Security workflow | Completed success. |
| Swift workflow | Completed success. |
| Vercel status | Commit status context `Vercel` succeeded for `ede7960`; production deployment `dpl_5jR3Qnv71v58YfWN77VxrLihYPk9` is READY for the merge commit. |
| Render status | Deploy `dep-d8rmafreo5us73di4as0` is live for the merge commit after setting `BRASSTUNE_AUTH_MODE=disabled`. |

Any future hotfix commit must get its own exact-SHA CI/deploy evidence.

## Blocked Or Scoped

| Gate | Status | Reason |
|---|---|---|
| Chrome plugin smoke | Blocked | Chrome connector runtime failed before browser commands with missing `sandboxPolicy` metadata. |
| Direct requirements-file `pip-audit` | Blocked | Local `pip-audit` crashed while creating its temporary resolver venv. Use the Python 3.12 uv-resolved audit above plus Security workflow on the exact pushed SHA. |
| Live Supabase auth/provider lifecycle | Blocked | Requires owner-issued Supabase, Google, and Apple provider configuration plus disposable live users. |
| Production exact-SHA smoke | Passed for merge commit | Re-run after any follow-up commit or production env change. |
| App Store/TestFlight signing | Blocked | Requires Apple Developer team, bundle ID, signing, App Store Connect, and review metadata. |
| Physical microphone/device validation | Blocked | Requires iPhone/iPad hardware and real brass input. |
