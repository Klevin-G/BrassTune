# BrassTune Final Release Report

Status: closed-beta candidate pending final GitHub Actions success on the post-fix PR head; external provider/App Store/device gates remaining.

## Summary

The hosted beta pass fixed the Render WebSocket blocker, added repeatable hosted smoke coverage, corrected Vercel-hosted API/WebSocket fallbacks, removed user-facing env-var copy, added a clean Supabase baseline migration, and remediated the live public `SECURITY DEFINER` helper RPC grant drift.

PR #2 head `d05fe773499393ad50af15c59322f66adeb98c11` is open, non-draft, and mergeable but was not merge-ready: Backend, Frontend, and Security Actions were green, while Swift failed at `Native app UI smoke test`. This follow-up pass fixes the current Swift UI smoke root cause locally by making `PracticeView` observe nested audio-engine state, resetting UI-test app state, using stable accessibility identifiers, and isolating the UI smoke simulator install. Do not merge PR #2 until the post-fix pushed head has green Backend, Frontend, Security, and Swift Actions.

## Hosted Results

- Render service `BrassTune` (`srv-d8pgo3ok1i2s73f3k740`) is a Python web service in Oregon, root directory `backend`, public URL `https://brasstune.onrender.com`, health path `/api/health`.
- Render remains configured on branch `main`, but the backend was safely deployed through the Render API by exact commit.
- Render live deploy `dep-d8q7296gvqtc73a0djm0` is `live` for commit `395a9d29870b25a7aadf161dc1d69c988bdaa841`, trigger `api`, finished `2026-06-18T22:30:13Z`.
- Root cause: hosted Render installed `uvicorn` without a WebSocket protocol implementation, producing Uvicorn warnings and `404` on WebSocket upgrades. `backend/requirements.txt` now installs `uvicorn[standard]`.
- Direct hosted checks passed: `/api/health` `200`, CORS preflight for the Vercel preview origin `200`, and `wss://brasstune.onrender.com/ws/pitch` opens and returns `{"type":"error","message":"Authenticate before sending pitch frames."}` for unauthenticated ping.
- `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` passed for production root, API health, CORS, and WebSocket.
- The same hosted smoke against the PR branch preview passed with protected-page skips: health, CORS, and raw WebSocket upgrade passed across browser projects; preview page journeys and page-derived WebSocket URL checks were skipped because Vercel Authentication protects the preview without a share URL or automation bypass.
- Vercel created earlier preview deployment `dpl_Gspk8kPcVCDcBX5G9WDUByxLrEpr` for commit `81285b653bc5e357f79fe41f04b51e93418f541d`; refresh preview evidence after the latest CI-fix head deploys. Protected preview routes are fetchable through the Vercel connector, but local Playwright still receives `401` due Vercel Authentication.

## Supabase Results

- Before remediation, public schema had no app tables and `public.rls_auto_enable()` was `SECURITY DEFINER` executable by `anon` and `authenticated`.
- Applied migrations through Supabase MCP:
  - `20260616_brasstune_baseline`
  - `20260617_brasstune_production_readiness`
  - `20260618_lock_down_rls_auto_enable`
- Verification showed nine public app tables with RLS enabled and zero rows: `users`, `instrument_profiles`, `practice_sessions`, `pitch_samples`, `note_events`, `groups`, `group_members`, `invitations`, `recommendations`.
- Verification showed `rls_auto_enable()` still exists but `anon_execute=false` and `authenticated_execute=false`.

## Local Validation

- Backend: `cd backend && .venv/bin/python -m pytest` passed, `48 passed`.
- Frontend unit: `cd frontend && npm test` passed, `16 passed`.
- Frontend build: `cd frontend && npm run build` passed with existing chunk-size warning.
- Frontend audit: `cd frontend && npm audit --omit=dev` passed, `0 vulnerabilities`.
- Browser E2E local: `cd frontend && CI=true npm run e2e:local` now runs only local release journeys and passed, `30 passed`; hosted smoke remains explicit through `npm run e2e:hosted` / `npm run smoke:hosted`.
- Hosted preview smoke: `BRASSTUNE_WEB_BASE_URL=https://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` passed with `15 passed`, `20 skipped` for protected preview page journeys.
- Device simulation: `cd frontend && npm run simulate:devices` passed and refreshed `docs/device-simulation-report.md`.
- Swift package: `cd swift/BrassTuneCore && swift test` passed, `3` Swift Testing tests.
- Xcode/native previously passed clean iPhone Debug (`/tmp/brasstune-dd-debug-iphone-handoff-final`), clean iPhone Release (`/tmp/brasstune-dd-release-iphone-handoff-final`), clean iPad Debug (`/tmp/brasstune-dd-debug-ipad-handoff-final`), app unit tests (`3` tests), and UI smoke (`1` XCUITest) on dynamically discovered simulators with unsigned simulator builds. Current local post-fix native unit tests pass, and the focused `BrassTuneAppUISmoke` XCUITest passes against simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`; verify the latest Swift Action before merging.
- Native Settings now surfaces Data/export/delete controls first, and the iPhone UI smoke follows the compact `More` tab path to Settings.

## Not Verified

- Protected Vercel preview Playwright page journeys remain blocked by Vercel Authentication returning `401` outside the connector.
- Live Supabase email/password, reset email delivery, Apple OAuth, token refresh, account deletion, storage cleanup, and identity cleanup were not run without disposable live test credentials/provider setup.
- Native SwiftUI app remains fixture-backed for practice/audio/analytics/ensemble depth. Simulator builds/tests passed, but this is not a production native feature-complete claim.
- Signed archive, App Store Connect upload, App Store metadata, Apple legal identity, and signing profiles are not available.
- Physical iPhone/iPad microphone quality with real brass input was not tested.

## Current Status

Hosted web/backend can be treated as a closed-beta candidate for owner-controlled testing after the post-fix PR head has green required Actions, with external provider/App Store/device gates remaining. Do not describe the full product as complete until the live-provider, App Store, physical-device, and native production-depth gates have real evidence.
