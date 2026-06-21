# Workstream Ownership

## 2026-06-21 Post-Merge Deploy Addendum

Branch: `main`
Merged main SHA: `4bda5691a05988471e412519bbfdcf4078430ee0`

| Workstream | Owner/source | Scope | Outcome |
|---|---|---|---|
| Merge/release gate | Coordinator plus GitHub connector | Exact-SHA CI, PR state, merge guard | PR #2 merged after Backend, Frontend, Security, Swift, and Vercel were green for `ede7960fb0f543a8d0b329357199d782257a0d46`. |
| Production deploy | Coordinator plus Vercel/Render APIs | Vercel production deploy, Render env/deploy hook, hosted smoke | Vercel production is READY on `4bda5691...`; Render deploy `dep-d8rmafreo5us73di4as0` is live after setting `BRASSTUNE_AUTH_MODE=disabled`; hosted smoke passed. |
| Smoke hotfix | Coordinator | Node hosted-smoke WebSocket Origin behavior | `scripts/hosted-smoke.mjs` now uses the raw WebSocket probe for the normal app-level check so the production web Origin is sent. |

## 2026-06-21 Final Stabilization Addendum

Branch: `arya/release-readiness-hardening`
Base SHA for this pass: `eef7f865085859d877703c7652b941aaf6815134`

| Workstream | Owner/source | Scope | Outcome |
|---|---|---|---|
| Coordination/release gate | Coordinator plus read-only release/deployment agents | Scope lock, validation matrix, hosted smoke, merge decision | Local repository hardening passed; production hosted smoke failed, so merge/release remained blocked. |
| Backend/security | Backend security audit plus coordinator implementation | Canonical pitch samples, account deletion jobs/order, ensemble reactivation windows, migration | Fixed locally with backend regression tests; full backend suite passed `69`. |
| Frontend/audio/auth/score | Web/auth and audio findings plus coordinator implementation | Friendly auth errors, mic cleanup, instrument ranges, PDF.js reader, metronome live refs/wording | Fixed locally; frontend unit/build/audit and local E2E passed. |
| Documentation/evidence | Coordinator | Locked release scope, interaction matrix, release evidence, failure log | Added current source-of-truth docs and moved non-blocking ideas to backlog. |
| Native | Native iOS read-only audit | Simulator and parity gap review | No native code changed in this pass; Swift core tests passed, native production parity remains a red gate. |
| Artifact/security hygiene | Artifact hygiene audit plus coordinator checks | Ignored artifacts, tracked secrets, whitespace, dependency/SAST checks | No tracked secret pattern found; Bandit and resolved pip-audit passed. |

---

Date: 2026-06-20
Branch: `arya/release-readiness-hardening`
Remote PR head at start of this pass: `36b29c8cff85f3364648763fd36d6472fb1ef8a3`
Current state: pushed branch follow-up; exact-SHA CI/preview pending on the latest PR head.

## Agent Wave

| Workstream | Agent/source | Scope | Outcome |
|---|---|---|---|
| Repo/CI/deploy scout | Repo scout and deployment smoke agent | Branch state, CI pathways, workflows, Vercel/Render/Supabase config, hosted smoke | PR baseline verified through GitHub connector by coordinator; hosted production found stale for WS hardening. |
| Documentation scout | Docs writer agent | Markdown inventory, canonical/historical split, stale SHAs/test counts | Confirmed missing `release-evidence.json` and stale docs; canonical docs refreshed in this pass. |
| Audio/metronome/score scout | Audio pipeline reviewer | Guest mic, recorder, score, metronome, native audio gaps | Confirmed P0 guest mic backend dependency and duplicate mic streams; local browser detector and shared stream path implemented. |
| Web/auth scout | Web auth agent | Auth providers, guest/private separation, account linking/deletion, persona flows | Confirmed email-only linking and missing Google web provider; local no-email-link and Google OAuth path implemented. |
| Backend/security scout | Backend security agent | Auth, WebSocket, deletion, request/upload limits, hosted behavior | Confirmed stale production WS hardening and durable deletion gap; enhanced hosted smoke implemented. |
| Native iOS scout | Native iOS agent plus XcodeBuildMCP | Swift package/app, simulator readiness, native parity gaps | Simulator Debug build, app unit tests, UI smoke, and Swift package tests passed; native parity remains incomplete. |
| Artifact hygiene scout | Artifact hygiene reviewer | Secrets, ignored artifacts, local data, large files | No tracked secret/large-file issue found; local env/data artifacts remain ignored and must not be staged. |
| Browser/Chrome/Simulator tools | Coordinator | Requested plugin surfaces | Simulator state inspected with Computer Use; Chrome connector blocked by runtime metadata error; Playwright used for browser validation. |

## Implementation Ownership

| Area | Files | Change |
|---|---|---|
| Guest microphone | `frontend/src/domain/localPitchDetection.ts`, `frontend/src/hooks/usePitchStream.ts`, `frontend/src/pages/PracticePage.tsx`, `frontend/src/pages/AudioLabPage.tsx` | Added browser-local pitch detection and removed guest mic dependency on `/ws/pitch`. |
| Recorder stream reuse | `frontend/src/hooks/useAudioRecorder.ts`, `frontend/src/pages/PracticePage.tsx` | Allows `MediaRecorder` to reuse the live pitch stream and negotiates supported MIME types. |
| Auth safety/providers | `backend/app/api/auth.py`, `backend/app/tests/test_hardening.py`, `frontend/src/state/AuthContext.tsx`, `frontend/src/pages/AuthPage.tsx`, `frontend/src/styles/components.css` | Blocks same-email provider takeover and adds Google OAuth path/UI. |
| Hosted smoke | `scripts/hosted-smoke.mjs` | Adds WS query-token and bad-Origin negative probes. |
| Ensemble aggregate privacy | `backend/app/api/routes.py`, `backend/app/tests/test_hardening.py` | Limits ensemble summary/report sessions to active members' post-membership practice history. |
| Score Practice and settings affordances | `frontend/src/pages/ScorePracticePage.tsx`, `frontend/src/pages/SettingsPage.tsx`, `frontend/src/styles/components.css` | Makes focus preview functional and removes editable styling from fixed threshold copy. |
| Hosted smoke copy alignment | `frontend/e2e/hosted-smoke.spec.ts`, `frontend/src/pages/AudioLabPage.tsx` | Keeps hosted route assertions aligned with current Audio Lab user-facing copy. |
| Evidence/docs | `docs/release-readiness/*`, `docs/deployment.md`, `docs/device-simulation-report.md`, `docs/assets/device-simulation/*` | Updates canonical evidence, current local matrix, and generated device screenshots. |

## Review Rules

- Do not stage ignored env files, `.vercel/`, `backend/data/`, Playwright traces, Xcode result bundles, or local databases.
- Do not claim production is current until an owner-approved Render/Vercel deploy passes the enhanced hosted smoke.
- Do not claim native parity complete; current evidence is simulator shell/readiness plus fixture-backed app tests.
- Do not claim final PR readiness until the latest pushed SHA is green on exact-SHA CI and preview checks.
