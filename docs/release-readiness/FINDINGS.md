# Release Findings

## Fixed In This Pass

| Severity | Finding | Evidence | Fix |
|---|---|---|---|
| High | WebSocket `stop_session` allowed stopping another user's session by guessed ID. | `backend/app/api/websocket.py`; regression in `test_websocket_stop_session_requires_owner_or_admin`. | Added write-ownership check before flush/stop. |
| High | Full JSON export could be used by any signed-in user with `id == 1`. | `backend/app/api/routes.py`; regression in `test_signed_in_student_cannot_use_full_json_export_bypass`. | Restricted full export to admin or local guest/demo users. |
| High | Account deletion did not exist across web/API. | `frontend/src/pages/SettingsPage.tsx`, `backend/app/api/routes.py`. | Added export-before-delete UI, confirmation, backend deletion endpoint, app-data deletion, and Supabase revoke/delete server path. |
| High | Supabase storage audio deletion/export did not cover object storage. | `backend/app/services/audio_storage.py`; regression in `test_supabase_audio_delete_is_called_before_metadata_is_cleared`. | Added storage object read/delete helpers and ZIP export inclusion. |
| Medium | Audio/body inputs could be accumulated without tight limits. | `backend/app/schemas/schemas.py`, `backend/app/api/routes.py`. | Added PCM frame cap, batch cap, and streaming upload body limit. |
| Medium | Production CORS default still included localhost when no env was configured. | `backend/app/main.py`. | Production default origins now empty unless configured. |
| Medium | Ensemble dashboard summary/report used implicit group selection. | `frontend/src/pages/EnsemblePage.tsx`. | Selection now drives group, summary, and report queries. |
| Medium | Auth UI had placeholder password reset and no Apple surface. | `frontend/src/pages/AuthPage.tsx`, `frontend/src/state/AuthContext.tsx`. | Added Supabase reset request/update flow and Apple OAuth callback/cancel/error surface. |
| Medium | Browser automation only proved routes, not journeys. | `frontend/e2e/release-journeys.spec.ts`, `frontend/playwright.config.ts`. | Added multi-browser journeys for routes, auth surfaces, recording/session review, settings export/delete, and server-side ensemble authorization. |
| Medium | Native SwiftUI app did not exist. | `swift/BrassTuneApp`. | Added native SwiftUI app, project, unit target, UI target, Keychain session storage, Supabase Auth REST wiring, deterministic audio fixture, legal/settings/account surfaces. |
| Low | Mobile/auth accessibility and layout had missing focus/live semantics. | Frontend component updates. | Added focus trap, safe-area padding, aria labels/live regions, meter/timer semantics. |

## Remaining Failed Or Blocked Gates

| Severity | Finding | Current Status | Required Owner/External Action |
|---|---|---|---|
| High | Hosted Render WebSocket route returns `404`. | Local backend has `/ws/pitch`; hosted smoke failed for `/ws/pitch` and `/api/ws/pitch`. | Authorized Render deployment/routing check and production WebSocket smoke with credentials. |
| High | Live Supabase email/password, Apple OAuth, reset callback, and identity deletion are not live-tested. | Local deterministic tests and UI surfaces exist; no disposable live credentials were provided. | Supabase test project credentials, redirect allowlist, Apple provider configuration, disposable test personas. |
| High | Apple signing/archive/App Store Connect validation not performed. | Simulator builds/tests pass; no signing credentials or App Store Connect access. | Apple Developer team, bundle IDs, profiles/certificates, App Store Connect app record. |
| High | Physical microphone quality cannot be proven in simulator. | Native audio fixture tests exist; simulator cannot validate brass microphone capture. | Physical iPhone/iPad protocol in `PHYSICAL_DEVICE_PROTOCOL.md`. |
| Medium | Combined `xcodebuild test` can fail with CoreSimulator `Busy` when unit/UI runners launch back-to-back. | Unit target and UI target pass separately on fresh temporary simulators; combined action failed with runner preflight Busy. | CI should run native unit and UI steps separately as in `.github/workflows/swift.yml`. |
| Medium | Legal metadata cannot be invented. | In-app privacy/terms/support surfaces exist without owner-specific legal identity. | Owner/legal counsel must provide legal controller, support URL/email, policy URL, and metadata. |

## Deferred Hardening

- Replace WebSocket query-string bearer tokens with a short-lived ticket or first-message auth to avoid token leakage in URL logs.
- Make backend account deletion external Supabase revocation/deletion transactional through an outbox/retry worker; current implementation deletes local data, then calls Supabase.
- Add live environment-gated Supabase integration tests once disposable project credentials are available.
- Add real native Supabase Swift client dependency and production API auth once bundle IDs and provider settings are chosen.
