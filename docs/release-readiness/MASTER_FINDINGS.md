# Master Findings

Updated: 2026-06-20T18:29:25Z
Branch: `arya/release-readiness-hardening`
Remote PR head at start of this pass: `36b29c8cff85f3364648763fd36d6472fb1ef8a3`
Current evidence state: local edits on top of `36b29c8cff85f3364648763fd36d6472fb1ef8a3`; commit, push, exact-SHA CI, and exact-SHA Vercel preview are still required.

## Source Of Truth

Use this file plus `release-evidence.json` for the current pass. Older status tables in `BASELINE.md`, `FINAL_REPORT.md`, `WEB_E2E_REPORT.md`, `IOS_SIMULATOR_REPORT.md`, and earlier handoff docs are historical unless they name this current local evidence state.

## Current Findings

| ID | Area | Severity | Status | Evidence | Release impact |
|---|---|---:|---|---|---|
| MF-001 | PR/CI baseline | P0 | PR #2 is open, mergeable clean, non-draft, with Backend, Frontend, Security, and Swift green on `36b29c8cff85f3364648763fd36d6472fb1ef8a3`. | Authenticated GitHub REST API using the local Git credential helper. | CI is green only for the remote head. Local fixes in this pass still need commit, push, and exact-SHA CI. |
| MF-002 | Guest live microphone | P0 | Improved locally. Guest microphone pitch detection now runs in the browser using local PCM autocorrelation instead of requiring `/ws/pitch`, Supabase, or backend availability. | `frontend/src/domain/localPitchDetection.ts`; `npm test` passed `34`; `CI=true npm run e2e:local` passed `75`. | Physical microphone quality and WebKit fake-media coverage still need device/browser-specific validation. |
| MF-003 | Duplicate microphone streams | P1 | Improved locally. The recorder can reuse the active pitch stream for `MediaRecorder` when live mic is already running. | `frontend/src/hooks/useAudioRecorder.ts`, `frontend/src/pages/PracticePage.tsx`; frontend tests/build passed. | Safari/iOS MIME behavior still needs real-device validation. |
| MF-004 | Supabase identity linking | P1 | Improved locally. Backend no longer links a Supabase identity to an existing local account solely by matching email. | `backend/app/api/auth.py`; `backend/app/tests/test_hardening.py`; targeted hardening `44 passed`, full backend `60 passed`. | Explicit account-linking ceremony and provider edge-case tests remain future work. |
| MF-005 | Google web sign-in path | P1 | Improved locally. Web Supabase OAuth now exposes `signInWithGoogle` with minimal `openid email profile` scopes and a visible Google provider action. | `frontend/src/state/AuthContext.tsx`, `frontend/src/pages/AuthPage.tsx`; frontend tests/build passed. | Live Google provider credentials, redirect allowlist, and cancellation/error tests remain externally blocked. |
| MF-006 | Hosted WebSocket hardening | P0 | Local code is hardened, but production Render is stale. Enhanced hosted smoke passed root/health/CORS/basic WS but failed query-token rejection and bad-Origin rejection against production. | `backend/app/tests/test_hardening.py` covers query-token and unapproved-origin rejection locally; production `npm run smoke:hosted` failed two WS-hardening checks. | Commit/push and let CI validate the branch; do not claim production current or hardened until owner-approved deploy and hosted smoke pass. |
| MF-007 | Account deletion durability | P1 | Still incomplete. Deletion remains inline rather than a tombstone/outbox/retry workflow. | Backend/security scout and `DELETE /api/users/me` review. | Repository-actionable before broad public/App Store release; live provider cleanup proof remains externally blocked. |
| MF-008 | Score Practice | P1 | Still a web foundation, not the full mission scope. | Static review plus existing docs. | PDF.js page model, timeline, flags, review/export, crop/reorder, and native parity remain incomplete. |
| MF-009 | Metronome | P1 | Web scheduler exists; measured timing/bleed/native parity remain incomplete. | Existing tests and docs. | Do not claim professional timing or mic-bleed validation. |
| MF-010 | Native parity | P1 | Simulator gates pass, but native remains fixture-backed for practice/audio and lacks native metronome/score/provider parity. | XcodeBuildMCP Debug build succeeded; unit tests `7 passed`; UI smoke `1 passed`; Swift package `3 passed`. | Status remains `native engineering parity in progress`, not TestFlight/App Store ready. |
| MF-011 | Artifact/secret hygiene | P1 | No tracked secret or large-file issue found. Ignored local env files and local recordings exist and must not be staged. | Artifact scout, `git status`, ignored-file review. | Stage explicit files only; never stage `.env*`, `.vercel/`, `backend/data/`, traces, or Xcode results. |
| MF-012 | Chrome connector | P2 | Blocked by tool runtime failure before browser control. | `node_repl/js` failed with missing `sandboxPolicy` metadata even for a trivial command. | Chrome-specific smoke was not possible in this environment; Playwright and Simulator evidence were used instead. |
| MF-013 | Ensemble aggregate privacy | P1 | Fixed locally. Director/admin summary and report endpoints now include only active-member sessions on or after membership creation, preventing pre-membership practice history from leaking into ensemble aggregates. | `backend/app/api/routes.py`; `backend/app/tests/test_hardening.py`; targeted hardening `44 passed`, full backend `60 passed`. | Needs exact-SHA CI after commit/push before merge. |
| MF-014 | Score Practice focus control | P1 | Fixed locally. The focus button now toggles a focused preview state with `aria-pressed` and explicit exit text instead of being a dead control. | `frontend/src/pages/ScorePracticePage.tsx`; frontend tests/build and local E2E passed. | Full Score Practice scope remains incomplete. |

## Current Validation

- `cd frontend && npm test`: passed, `34` tests.
- `cd frontend && npm run build`: passed, main JS `382.62 kB` minified, large Recharts chunk remains route-split.
- `cd frontend && CI=true npm run e2e:local`: passed, `75` tests across Chromium, Firefox, WebKit, mobile Chromium, and mobile WebKit.
- `cd frontend && npm run simulate:devices`: passed; refreshed `docs/device-simulation-report.md` and tracked screenshots.
- `cd frontend && npm audit --omit=dev`: passed, `0 vulnerabilities`.
- `cd backend && .venv/bin/python -m pytest app/tests/test_hardening.py -q`: passed, `44` tests, including query-token WebSocket auth rejection, unapproved-origin rejection, same-email Supabase no-link regression, and ensemble pre-membership report scoping.
- `cd backend && .venv/bin/python -m pytest -q`: passed, `60` tests.
- `cd backend && .venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt`: blocked by local Python 3.9.6 dependency-floor mismatch; backend requirements now require Python 3.10+.
- `cd backend && uv pip compile --python /Users/aryasalem/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 requirements-dev.txt -o /tmp/... && .venv-audit/bin/python -m pip_audit --no-deps --disable-pip -r /tmp/...`: passed, no known vulnerabilities.
- `cd backend && .venv/bin/python -m bandit -r app -x app/tests`: passed.
- `cd swift/BrassTuneCore && swift test`: passed, `3` Swift tests.
- XcodeBuildMCP `test_sim` for `BrassTuneAppTests` on iPhone 16e / iOS 26.2 / Xcode 26.2: passed, `7` tests.
- XcodeBuildMCP `test_sim` for `BrassTuneAppUISmoke` on iPhone 16e / iOS 26.2 / Xcode 26.2: passed, `1` UI test.
- `cd frontend && npx playwright test e2e/hosted-smoke.spec.ts --project=chromium`: passed locally with `1` passed and `6` hosted-only checks skipped.
- Hosted production smoke with enhanced WS hardening: failed as expected because production Render is stale for query-token and bad-Origin rejection; this is a deployment gate, not a blocker to committing the PR branch.

## Release Decision

Current status: `local web closed-beta candidate worktree pending commit/push, exact-SHA CI, exact-SHA preview, owner-approved Render deployment, and final hosted smoke; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not merge, tag, deploy, or invite beta testers until the changes are committed, pushed, CI is green on the exact new SHA, Vercel preview/deploy evidence is current, and hosted smoke passes after an owner-approved Render/Vercel deployment.
