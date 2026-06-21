# BrassTune Final Report

Updated: 2026-06-21T04:22:00Z
Branch: `main`
Merged PR head: `ede7960fb0f543a8d0b329357199d782257a0d46`
Merged main SHA: `4bda5691a05988471e412519bbfdcf4078430ee0`
Current state: PR #2 merged; Vercel production and Render backend deployed the merge commit; post-deploy hosted smoke passed after aligning Render `BRASSTUNE_AUTH_MODE=disabled` with `render.yaml` and fixing the smoke WebSocket app check to send the production `Origin` header.

## Summary

This pass preserved the prior release hardening and fixed additional bounded P1 issues found by the scout wave:

- Guest live microphone pitch detection no longer depends on Supabase, login, backend availability, or `/ws/pitch`; the browser now derives pitch frames locally from microphone PCM and guest recordings stay device-local.
- Live pitch and recording can share the active microphone stream, reducing duplicate permission/device contention.
- Backend Supabase identity sync no longer links a provider identity to a local account by email alone.
- Web Google OAuth is wired through Supabase with minimal `openid email profile` scopes and a visible provider action.
- Hosted smoke now fails stale Render deployments that still accept query-token WebSocket auth or unexpected origins.
- Ensemble aggregate summary/report endpoints now exclude sessions from before a student's active membership date.
- Deployed backend startup no longer seeds demo users/sessions by default; `BRASSTUNE_SEED_DEMO_DATA=1` is required for an intentional disposable demo environment.
- Ordinary student ensemble views now return only the caller's redacted membership instead of other students' identifiers.
- Guest audio is not marked saved until the guest session persistence path succeeds.
- Mission-style hosted smoke now maps `BRASSTUNE_WEB_ACCESS_URL` to the Playwright share URL variable.
- Score Practice focus mode is no longer a dead control; it toggles a focused preview state with accessible pressed state.
- Hosted-smoke page assertions now match the current Audio Lab copy.
- The fixed in-tune threshold in Settings no longer looks like an editable text field.
- Signed-in audio upload now preserves Authorization while adding audio content/duration headers.
- Score Practice PDF imports now enforce the 64-page local budget after PDF.js reads the page count.
- Student ensemble group lists now redact `director_user_id`.
- Account deletion now blocks Supabase user re-creation while external identity cleanup remains queued.
- Backend JSON body size and per-client path rate limits are now explicit configurable controls.
- Hosted Playwright/root smoke can use Vercel's `x-vercel-protection-bypass` automation header from an approved secret.
- Production hosted smoke now verifies the browser-origin WebSocket path plus query-token and bad-origin rejection.
- Swift Core now matches the backend/frontend RMS silence threshold.

PR #2 was merged. No release tag or GitHub Release was created in this pass.

## Current Evidence

See `TEST_MATRIX.md` and `release-evidence.json` for the full command matrix. Current highlights:

- Frontend unit tests: `40 passed`.
- Frontend build/typecheck: passed.
- Local Playwright journeys/accessibility: `75 passed`.
- Device simulation: skipped after a silent Chromium hang; partial screenshot churn was restored.
- Backend full suite: `73 passed`.
- Backend targeted hardening regression: `57 passed`.
- `npm audit --omit=dev`: `0 vulnerabilities`.
- Python 3.12 resolved `pip_audit --no-deps --disable-pip`: no known vulnerabilities.
- Requirements-file audit: the direct `.venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt` command crashed before vulnerability analysis while creating a temporary resolver venv; equivalent Python 3.12 evidence passed by resolving `requirements-dev.txt` with `uv pip compile --python ...` and auditing the resolved file with `pip-audit --no-deps --disable-pip`.
- Bandit: passed.
- Swift package: `3 passed`.
- App unit tests on iPhone 17 Pro simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`: `7 passed`.
- App UI smoke on iPhone 17 Pro simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`: command exited `0`.
- Release simulator build on iPhone 17 Pro simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`: passed.

GitHub connector checks verified PR #2 was open, mergeable, non-draft, and green on Backend, Frontend, Security, Swift, and Vercel for `ede7960fb0f543a8d0b329357199d782257a0d46`. The PR was merged into `main` as `4bda5691a05988471e412519bbfdcf4078430ee0`.

## Hosted Status

Production connectivity is green for the web/backend closed-beta path:

- Vercel production deployment `dpl_5jR3Qnv71v58YfWN77VxrLihYPk9` is READY for merge commit `4bda5691a05988471e412519bbfdcf4078430ee0`.
- Render backend deploy `dep-d8rmafreo5us73di4as0` is live for merge commit `4bda5691a05988471e412519bbfdcf4078430ee0`.
- `npm run smoke:hosted` passed with web root, Render health, CORS, WebSocket app-level response, query-token rejection, and bad-origin rejection all green.
- Render production required setting `BRASSTUNE_AUTH_MODE=disabled`; this matches the checked-in `render.yaml` closed-beta guest-practice configuration.

## Remaining Blockers

Repository-actionable before broad public/App Store release:

- Automated account deletion outbox/retry worker.
- Full Score Practice reader workflow with timeline, flags, review/export, crop/reorder, and native parity.
- Measured metronome timing, click-bleed rejection, and native metronome parity.
- Native real audio capture, native Score Practice, native provider parity, and broader Swift domain parity.
- Keep exact-SHA CI, Vercel/Render deploy evidence, and hosted smoke green for any follow-up hotfix commits.

External or owner-gated:

- Supabase/Google/Apple provider credentials, callback allowlists, disposable live auth users, and provider lifecycle tests.
- Apple Developer team, bundle ID, signing profiles, App Store Connect/TestFlight, public privacy/support/legal URLs, and review metadata.
- Physical iPhone/iPad microphone and real brass validation.
- Owner approval for switching production auth from disabled guest practice to live Supabase provider mode.

## Release Decision

Current status: `web/backend closed-beta production path deployed and smoke-passed; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not call this App Store/TestFlight ready. Web/backend closed beta can proceed in guest/auth-disabled mode, while live Supabase auth, native real-audio parity, Apple signing/TestFlight, and physical-device brass validation remain separate gates.
