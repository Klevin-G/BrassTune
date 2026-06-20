# Master Findings

Updated: 2026-06-20 UTC.

## Current Snapshot

- Branch: `arya/release-readiness-hardening`
- Local base commit before this run: `1013177ba7056fd8f3fa91b99b233d1adf51ff4c`
- Merge base with `origin/main`: `652a787c2e643542dfac5911820a2fed01885622`
- Production deploy state was not changed in this run.
- Production hosted smoke was reported green by the deployment scout for root, Render health, CORS, and raw WebSocket connectivity. It is not proof that production serves this uncommitted working tree.
- Final local validation in this run: backend pytest, frontend unit/build/audit, full local browser E2E, device simulation, Swift package tests, Bandit, diff whitespace, large-file scan, secret-name scan, and rendered in-app browser spot checks.

## Valid Findings Fixed In This Run

| Area | Severity | Finding | Change | Evidence |
|---|---:|---|---|---|
| Backend auth | P0 | Production could silently fall back to local dev auth if Supabase config was absent or local auth was explicitly allowed. | `APP_ENV` now defaults to production, production startup requires Supabase URL/key, and production rejects `BRASSTUNE_ALLOW_LOCAL_AUTH`. | `cd backend && .venv/bin/python -m pytest`: `53 passed`. |
| WebSocket security | P1 | Query-token auth and ungated origins made browser WebSocket sessions harder to constrain. | Query-token auth is disabled, first-message auth is required, and non-local origins must match explicit allowed origins. | Backend hardening tests cover query-token rejection, bad origin, first-message auth, and oversized frames. |
| Payload validation | P1 | Audio/pitch frames accepted broader unbounded input than necessary. | Pydantic schema constraints now cap strings, arrays, sample rates, numeric ranges, and finite PCM samples. | Backend hardening tests pass. |
| Guest auth UX | P2 | Auth-disabled builds could still show sign-up/reset links and dead-end topbar CTAs. | Guest-only surfaces now route to practice and hide auth-only switchers when providers are not configured. | `cd frontend && npm test`: `27 passed`; `cd frontend && npm run build`: passed. |
| Practice tools | P1 | No first-class metronome or score-practice flow existed on web. | Added `/metronome` and `/practice/score`, navigation entries, device simulation coverage, route smoke coverage, and unit tests. | Frontend unit/build passed; full E2E pending after docs sync. |
| Error states | P2 | Analytics/progress/coach/session-review flows could fail silently or stay in loading states. | Added explicit failure banners and session-not-found recovery. | Frontend unit/build passed. |
| Accessibility | P2 | Selection chips and mobile primary nav lacked complete pressed/label semantics. | Added `aria-pressed` and mobile nav label. | Frontend unit/build passed. |
| Mobile layout | P2 | The new metronome/score/settings surfaces could land primary actions under the fixed mobile tab bar on small screens. | Compact screen-scoped headers, mobile settings ordering, and smaller tiny-phone chrome. | `cd frontend && npm run simulate:devices`: passed. |

## Subagent Findings Kept As Blockers

- Native iOS practice, score capture, auth, analytics, and ensemble flows are not production-equivalent to the web app. Simulator evidence does not prove physical microphone or App Store readiness.
- Live Supabase email/password, Apple OAuth, reset email, token refresh, account export/delete, storage cleanup, and identity cleanup require disposable live credentials and owner-approved provider setup.
- Web score practice imports, previews, camera capture, and local IndexedDB confirmation now exist, but full PDF rendering, EXIF stripping, robust magic-byte validation, OMR, score following, crop/retake, and native VisionKit scanning are deferred.
- Metronome scheduling exists with domain tests and Web Audio lookahead, but no 10-minute measured timing run, physical-device audio bleed test, or recording alignment study was completed.
- Production CORS regex is not enough for WebSocket origin checks. `CORS_ALLOWED_ORIGINS` must explicitly include production and any owner-approved preview/share origins.
- The frontend bundle remains above Vite's default chunk warning threshold.
- `pip-audit` currently reports Starlette `0.49.3`, pytest `8.4.2`, and python-dotenv `1.2.1` advisories. Starlette fixes require versions outside the current FastAPI-compatible range; dependency remediation needs a framework/dependency upgrade pass.

## Release Decision

This working tree improves the closed-beta candidate, but it is not a final release or App Store-ready state. Before a merge/release claim, re-run full local gates, verify latest CI on the exact pushed SHA, run post-deploy production smoke, and close or explicitly accept the external provider/device/legal blockers.
