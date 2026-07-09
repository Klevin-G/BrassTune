# Current Branch Notice

2026-07-08 notice: this file is historical June web-beta evidence, not the current PR #7/PR #8 release decision. Current web/backend release status is tracked in `WEB_RECOVERY_FINDINGS.md`: PR #7 remains blocked on stale Render readiness/version routes, protected Vercel preview access, disabled deploy/smoke workflows, live Supabase acceptance, and remaining guest-first UX polish. Current native status is tracked in the native `TEST_MATRIX.md`: PR #8 remains simulator/sample-mode only and is blocked on live acoustic capture, physical-device validation, signing/archive, and TestFlight/App Store gates.

Updated: 2026-06-21T05:24:54Z for `arya/final-web-completion` at base SHA `a8ce933a8ccfdac75b4244fe1c1bb2630655d14b`.

Historical June evidence is maintained in `FINAL_REPORT.md`, `TEST_MATRIX.md`, `release-evidence.json`, `FINAL_WEB_SCOPE.md`, `WEB_CONTROL_MANIFEST.md`, and `WEB_PRODUCTION_COMPLETION_GATE.md`.

Older entries below are historical unless they are repeated in the current evidence files. Do not use older merged PR SHAs or deployment IDs below as evidence that this branch has been merged, deployed, or production-certified.

# Master Findings

Updated: 2026-06-21T04:22:00Z
Branch: `main`
Merged PR head: `ede7960fb0f543a8d0b329357199d782257a0d46`
Merged main SHA: `4bda5691a05988471e412519bbfdcf4078430ee0`

## Source Of Truth

Use this file, `LOCKED_RELEASE_SCOPE.md`, `release-evidence.json`, and `FAILURE_LOG.md` for the current state. Older reports are historical unless they name the current pass and validation commands below.

## Current Findings

| ID | Area | Severity | Status | Evidence | Release impact |
|---|---|---:|---|---|---|
| MF-001 | Pitch-frame trust boundary | P1 | Fixed/deployed | Backend now canonicalizes saved pitch samples from frequency, session instrument, and reference pitch; forged label regression passed. | Covered by exact-SHA CI and deployed backend. |
| MF-002 | Session instrument mismatch | P1 | Fixed/deployed | Sample endpoints reject frame instruments that differ from the session instrument. | Covered by exact-SHA CI and deployed backend. |
| MF-003 | Guest/local instrument ranges | P1 | Fixed locally | Frontend domain now enforces selected instrument frequency ranges; local pitch/music tests passed. | Guest practice remains backend-independent. |
| MF-004 | Account deletion durability/order | P1 | Fixed locally | Account deletion jobs record cleanup stage/status; local cleanup failure does not call external identity deletion; success calls external cleanup after local user deletion. | Live Supabase cleanup proof remains provider-gated. |
| MF-005 | Ensemble membership intervals | P1 | Fixed/deployed | Active-membership windows now reset on reactivation; removed-interval sessions are excluded from ensemble summaries. | Covered by exact-SHA CI and deployed backend. |
| MF-006 | Auth error safety | P1 | Fixed locally | Supabase/provider/env/URL/stack-like errors are mapped to concise product messages. | Live provider tests remain externally gated. |
| MF-007 | Microphone lifecycle | P1 | Fixed locally | Failed signed-in recording start stops an opened mic stream. | Physical microphone quality not claimed. |
| MF-008 | Score Practice PDF reader | P1 | Fixed locally | Iframe-only PDF preview replaced with lazy PDF.js canvas rendering, page navigation, zoom, and rotation. | Manual score practice only; printed-note comparison remains disabled until OMR/alignment is proven. |
| MF-009 | Metronome wording/live settings | P1 | Fixed locally | Running accent/ramp settings use refs; UI now labels queue stats instead of acoustic measurements. | Acoustic timing/bleed validation remains unproven. |
| MF-010 | Native parity | P1 | Red gate | Native audit found fixture-backed mic/practice and missing native metronome/score/auth parity. Swift package tests passed only for existing core fixtures. | Do not claim native production parity or App Store readiness. |
| MF-011 | Hosted production | P0 | Passed | `npm run smoke:hosted` against production passed root, health, CORS, browser-origin WS app response, query-token rejection, and bad-Origin rejection after Vercel/Render deployment. | Web/backend closed-beta production gate is green. |
| MF-012 | Exact-SHA CI/deploy | P0 | Passed for merge commit | GitHub connector verified Backend, Frontend, Security, Swift, and Vercel green for `ede7960`; PR #2 merged to `main` as `4bda5691`; Vercel and Render deployed the merge commit. | Re-check exact-SHA gates for future hotfix commits. |
| MF-013 | Artifact/secret hygiene | P1 | Clean tracked scope | `git diff --check` passed; tracked secret-pattern scan returned no matches; only expected ignored local env/data/test artifacts are present. | Stage explicit files only. |
| MF-014 | Signed-in audio upload auth | P1 | Fixed/deployed | Frontend API requests now merge upload headers without overwriting Authorization; regression test covers audio upload with auth. | Covered by exact-SHA CI and deployed frontend. |
| MF-015 | Score Practice PDF cap | P2 | Fixed/deployed | PDF page counts above the 64-page local budget mark the import unsupported and disable confirmation; unit coverage added. | Covered by exact-SHA CI and deployed frontend. |
| MF-016 | Ensemble list privacy | P1 | Fixed/deployed | Student group list responses now redact `director_user_id`; regression coverage added. | Covered by exact-SHA CI and deployed backend. |
| MF-017 | Backend abuse limits | P2 | Fixed locally | Backend now rejects oversized JSON requests before parsing and has configurable per-client path rate limiting; regression coverage added. | Tune env values in production as needed. |
| MF-018 | Vercel automation bypass support | P2 | Fixed locally | Hosted Playwright and root smoke scripts accept an approved automation bypass secret and send `x-vercel-protection-bypass` without printing it. | Requires owner-created secret in an approved secret store. |
| MF-019 | Swift RMS parity | P2 | Fixed locally | Swift Core silence threshold now matches the backend/frontend `rms < 0.01` rule; boundary tests added. | Native mic remains fixture-backed. |

## Current Validation

- `cd backend && PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest app/tests/test_hardening.py -q`: passed, `57` tests.
- `cd backend && PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest -q`: passed, `73` tests.
- `cd backend && .venv/bin/python -m bandit -r app -x app/tests`: passed, no issues.
- `cd backend && .venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt`: blocked locally by a `pip-audit` temporary `ensurepip` SIGABRT under the bundled Python resolver; the vulnerability result below is the passing audit evidence.
- `cd backend && uv pip compile --python /Users/aryasalem/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 requirements-dev.txt -o /tmp/brasstune-pip-audit-requirements.txt && .venv/bin/python -m pip_audit --no-deps --disable-pip -r /tmp/brasstune-pip-audit-requirements.txt`: passed, no known vulnerabilities.
- `cd frontend && npm test`: passed, `40` tests.
- `cd frontend && npm run build`: passed.
- `cd frontend && npm audit --omit=dev`: passed, `0 vulnerabilities`.
- `cd frontend && CI=true npm run e2e:local`: passed, `75` tests.
- `cd swift/BrassTuneCore && swift test`: passed, `3` Swift tests.
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination 'id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`: passed, `7` XCTest cases.
- `xcodebuild test -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination 'id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests/BrassTuneAppUITests/testLaunchPracticeAndSettingsSurfaces -resultBundlePath /tmp/BrassTuneAppUISmoke.xcresult`: exited `0`.
- `xcodebuild build -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination 'id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO`: passed.
- `cd frontend && npm run simulate:devices`: stopped after about six minutes because Chromium hung silently and partially rewrote screenshot artifacts; generated artifact churn was restored. Treat device simulation as skipped for this patch.
- `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_WEB_ACCESS_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted`: passed, `7` checks after Vercel production deploy `dpl_5jR3Qnv71v58YfWN77VxrLihYPk9`, Render deploy `dep-d8rmafreo5us73di4as0`, and the origin-aware smoke script fix.
- `git diff --check`: passed.
- Tracked high-confidence secret-pattern scan: no matches.

## Release Decision

Current status: web/backend closed-beta production path is deployed and smoke-passed in guest/auth-disabled mode. Do not claim native production parity, TestFlight/App Store readiness, live Supabase provider readiness, or physical-device microphone quality until those separate gates are completed.
