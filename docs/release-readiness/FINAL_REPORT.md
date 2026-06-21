# BrassTune Final Report

Updated: 2026-06-21T03:55:22Z
Branch: `arya/release-readiness-hardening`
Remote PR head at start of this pass: `4957cea963670be6b56f0dc5b6311e8bf684a166`
Current state: local follow-up fixes on top of green PR head `4957cea963670be6b56f0dc5b6311e8bf684a166`; commit/push, exact-SHA CI, exact-SHA Vercel preview, Render deployment, and hosted smoke are still required.

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
- Swift Core now matches the backend/frontend RMS silence threshold.

No production deploy, merge, or tag was performed in this pass.

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

GitHub connector checks verified PR #2 was open, mergeable, non-draft, and green on Backend, Frontend, Security, and Swift for `4957cea963670be6b56f0dc5b6311e8bf684a166`. Remote CI and preview evidence do not cover the local changes from this pass until they are committed, pushed, and CI/deployment complete on the exact new SHA.

## Hosted Status

Production connectivity is healthy but stale:

- `https://brass-tune.vercel.app` root loaded.
- `https://brasstune.onrender.com/api/health` passed.
- CORS preflights for `/api/health` and `/api/sessions/start` passed.
- Basic `/ws/pitch` app-level response passed.
- WS hardening checks failed:
  - `wss://brasstune.onrender.com/ws/pitch?token=dev-user-1` returned `Invalid or expired Supabase token` instead of `WebSocket query-token auth is disabled.`
  - A forged `Origin: https://evil.example` did not produce the current branch's explicit origin rejection before timeout.

This means production Render is not serving the current WebSocket hardening. The local backend tests pass and include query-token and unapproved-origin WebSocket rejection coverage, so this hosted failure is classified as an expected stale-production deployment gate, not a local code failure. Owner-approved backend deployment and post-deploy hosted smoke are required before beta claims.

## Remaining Blockers

Repository-actionable before broad public/App Store release:

- Automated account deletion outbox/retry worker.
- Full Score Practice reader workflow with timeline, flags, review/export, crop/reorder, and native parity.
- Measured metronome timing, click-bleed rejection, and native metronome parity.
- Native real audio capture, native Score Practice, native provider parity, and broader Swift domain parity.
- Exact-SHA CI and Vercel/Render preview/deploy evidence for the latest pushed PR head.
- Reliable protected-preview browser access for exact-SHA Playwright smoke, or an approved Vercel bypass path that works in local/CI browser automation.

External or owner-gated:

- Supabase/Google/Apple provider credentials, callback allowlists, disposable live auth users, and provider lifecycle tests.
- Apple Developer team, bundle ID, signing profiles, App Store Connect/TestFlight, public privacy/support/legal URLs, and review metadata.
- Physical iPhone/iPad microphone and real brass validation.
- Owner-approved production deployment.

## Release Decision

Current status: `local web closed-beta candidate patch pending commit/push, exact-SHA CI, exact-SHA preview, owner-approved Render/Vercel deployment, and final hosted smoke; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not call this release-ready and do not merge/deploy until the changes are committed, pushed, CI is green on the exact new SHA, an exact-SHA preview is verified, and hosted smoke passes after owner-approved production backend/frontend deployment.
