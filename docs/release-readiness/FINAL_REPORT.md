# BrassTune Final Report

Updated: 2026-06-20T19:39:44Z
Branch: `arya/release-readiness-hardening`
Remote PR head at start of this pass: `26de9a223b64b7bbde3c3b4aacd963c17dad0dbd`
Current state: local follow-up fixes on top of green PR head `26de9a223b64b7bbde3c3b4aacd963c17dad0dbd`; commit/push, exact-SHA CI, exact-SHA Vercel preview, Render deployment, and hosted smoke are still required.

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

No production deploy, merge, or tag was performed in this pass.

## Current Evidence

See `TEST_MATRIX.md` and `release-evidence.json` for the full command matrix. Current highlights:

- Frontend unit tests: `36 passed`.
- Frontend build/typecheck: passed.
- Local Playwright journeys/accessibility: `75 passed`.
- Device simulation: passed and refreshed tracked screenshots/report.
- Backend full suite: `64 passed`.
- Backend targeted seeding/roster privacy regression: `6 passed`.
- `npm audit --omit=dev`: `0 vulnerabilities`.
- Python 3.12 resolved `pip_audit --no-deps --disable-pip`: no known vulnerabilities.
- Requirements-file audit: the exact `.venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt` command is blocked because `.venv` is Python 3.9.6 and the backend dependency floor is Python 3.10+; equivalent Python 3.12 evidence passed by resolving `requirements-dev.txt` with `uv pip compile --python ...` and auditing the resolved file with `pip-audit --no-deps --disable-pip`.
- Bandit: passed.
- Swift package: `3 passed`.
- XcodeBuildMCP app unit tests on booted iPhone 16e simulator: `7 passed`.
- XcodeBuildMCP UI smoke on booted iPhone 16e simulator: `1 passed`.
- Hosted-smoke spec local sanity: `1 passed`, `6` hosted-only checks skipped as expected.

Authenticated GitHub API checks verified PR #2 was open, mergeable clean, non-draft, and green on Backend, Frontend, Security, and Swift for `26de9a223b64b7bbde3c3b4aacd963c17dad0dbd`. Vercel deployment listing showed the exact branch preview `dpl_2pTQ98czTPCTaB2PeDnz2iEVMBEh` is READY for `26de9a223b64b7bbde3c3b4aacd963c17dad0dbd`. Remote CI and preview evidence do not cover the local changes from this pass until they are committed, pushed, and CI/deployment complete on the exact new SHA.

## Hosted Status

Production connectivity is healthy but stale:

- `https://brass-tune.vercel.app` root loaded.
- `https://brasstune.onrender.com/api/health` passed.
- CORS preflights for `/api/health` and `/api/sessions/start` passed.
- Basic `/ws/pitch` app-level response passed.
- New WS hardening checks failed:
  - `wss://brasstune.onrender.com/ws/pitch?token=dev-user-1` returned `Invalid or expired Supabase token` instead of `WebSocket query-token auth is disabled.`
  - A forged `Origin: https://evil.example` did not produce the current branch's explicit origin rejection before timeout.

This means production Render is not serving the current WebSocket hardening. The local backend tests pass and include query-token and unapproved-origin WebSocket rejection coverage, so this hosted failure is classified as an expected stale-production deployment gate, not a local code failure. Owner-approved backend deployment and post-deploy hosted smoke are required before beta claims.

## Remaining Blockers

Repository-actionable before broad public/App Store release:

- Durable account deletion tombstone/outbox/retry workflow.
- Full Score Practice reader workflow with PDF.js/page model, timeline, flags, review/export, crop/reorder, and native parity.
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

Current status: `local web closed-beta candidate branch pending exact-SHA CI, exact-SHA preview, owner-approved Render deployment, and final hosted smoke; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not call this release-ready and do not merge/deploy until the changes are committed, pushed, CI is green on the exact new SHA, an exact-SHA preview is verified, and hosted smoke passes after owner-approved production backend/frontend deployment.
