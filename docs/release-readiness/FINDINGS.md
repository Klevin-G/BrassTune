# Release Findings

## Fixed In This Pass

| Severity | Finding | Evidence | Fix |
|---|---|---|---|
| High | WebSocket `stop_session` allowed stopping another user's session by guessed ID. | `backend/app/api/websocket.py`; regression in `test_websocket_stop_session_requires_owner_or_admin`. | Added write-ownership check before flush/stop. |
| High | Full JSON export could be used by any signed-in user with `id == 1`. | `backend/app/api/routes.py`; regression in `test_signed_in_student_cannot_use_full_json_export_bypass`. | Restricted full export to admin or local guest/demo users. |
| High | Account deletion did not exist across web/API. | `frontend/src/pages/SettingsPage.tsx`, `backend/app/api/routes.py`. | Added export-before-delete UI, confirmation, backend deletion endpoint, app-data deletion, and Supabase revoke/delete server path. |
| High | Supabase email fallback could preserve a privileged unlinked local role. | `backend/app/api/auth.py`; regression in `test_email_linked_supabase_user_does_not_inherit_privileged_local_role`. | Email-only linking without app metadata now demotes privileged local rows to `student`. |
| High | WebSocket bearer tokens were placed in URLs. | `frontend/src/api/client.ts`, `backend/app/api/websocket.py`; regression in `client.test.ts` and WebSocket tests. | WebSocket URL no longer includes tokens; authenticated clients send a first `authenticate` message. |
| High | Recording start/stop could be duplicated during async transitions. | `useSessionRecorder`, `useAudioRecorder`, `SessionControls`, Playwright recording journey. | Added explicit states, busy controls, and idempotent in-flight promises. |
| High | Supabase storage audio deletion/export did not cover object storage. | `backend/app/services/audio_storage.py`; regression in `test_supabase_audio_delete_is_called_before_metadata_is_cleared`. | Added storage object read/delete helpers and ZIP export inclusion. |
| Medium | Account export missed profile, memberships, invitations, and recommendations. | `backend/app/api/routes.py`; regression in `test_account_export_contains_profile_and_lifecycle_data`. | `/api/users/me/export.zip` now writes scoped account/lifecycle JSON files. |
| Medium | Admin/demo clear paths could orphan audio objects. | `backend/app/db/maintenance.py`; regression in `test_clear_practice_data_deletes_audio_before_bulk_rows`. | `clear_practice_data` deletes audio before bulk row deletion. |
| Medium | Audio/body inputs could be accumulated without tight limits. | `backend/app/schemas/schemas.py`, `backend/app/api/routes.py`. | Added PCM frame cap, batch cap, and streaming upload body limit. |
| Medium | Production CORS default still included localhost when no env was configured. | `backend/app/main.py`. | Production default origins now empty unless configured. |
| Medium | Render config trusted all `*.vercel.app` origins. | `render.yaml`. | Removed broad default regex; owner must configure exact origins. |
| Medium | Ensemble dashboard summary/report used implicit group selection. | `frontend/src/pages/EnsemblePage.tsx`. | Selection now drives group, summary, and report queries. |
| Medium | Active students could read aggregate ensemble reports. | `backend/app/api/routes.py`; regression in `test_ensemble_aggregate_reports_are_manager_only`. | Summary/report endpoints now require group manager. |
| Medium | Auth UI had placeholder password reset and no Apple surface. | `frontend/src/pages/AuthPage.tsx`, `frontend/src/state/AuthContext.tsx`. | Added Supabase reset request/update flow and Apple OAuth callback/cancel/error surface. |
| Medium | Browser automation only proved routes, not journeys. | `frontend/e2e/release-journeys.spec.ts`, `frontend/playwright.config.ts`. | Added multi-browser journeys for routes, auth surfaces, recording/session review, settings export/delete, and server-side ensemble authorization. |
| Medium | Local media import decoded before validation and had no cancel path. | `LocalMediaImportPanel.tsx`, `localMediaAnalysis.ts`; Vitest validation coverage. | Added type/size preflight, cancel control, and best-effort partial cleanup. |
| Medium | Session audio playback fetched every visible recording eagerly. | `SessionAudioPlayer.tsx`. | Playback now lazy-loads on user action and revokes object URLs. |
| Medium | GitHub Security failed because Gitleaks action could not read PR commits. | `.github/workflows/security.yml`, `FAILURE_LOG.md`. | Added `pull-requests: read`; local Gitleaks scan found no leaks. |
| Medium | Frontend CI lacked bounded runtime and failure artifacts. | `.github/workflows/frontend.yml`. | Added timeouts and Playwright artifact upload. |
| Medium | Native SwiftUI app did not exist. | `swift/BrassTuneApp`. | Added native SwiftUI app, project, unit target, UI target, Keychain session storage, Supabase Auth REST wiring, deterministic audio fixture, legal/settings/account surfaces. |
| Low | Mobile/auth accessibility and layout had missing focus/live semantics. | Frontend component updates. | Added focus trap, safe-area padding, aria labels/live regions, meter/timer semantics. |

## Remaining Failed Or Blocked Gates

| Severity | Finding | Current Status | Required Owner/External Action |
|---|---|---|---|
| High | Hosted Render WebSocket route returns `404`. | Local backend has `/ws/pitch`; hosted smoke failed for `/ws/pitch` and `/api/ws/pitch`. | Authorized Render deployment/routing check and production WebSocket smoke with credentials. |
| High | Live Supabase project advisor reports public `SECURITY DEFINER` RPC drift. | Supabase advisor found `public.rls_auto_enable()` executable by `anon`/`authenticated`. | Owner-approved Supabase migration/config change to revoke execute or move/change function. |
| High | Supabase migration is not clean-database safe by itself. | Existing migration references `public.groups`/`public.users` before a full baseline schema migration. | Add full baseline schema migration or enforce backend schema creation before migration. |
| High | Live Supabase email/password, Apple OAuth, reset callback, and identity deletion are not live-tested. | Local deterministic tests and UI surfaces exist; no disposable live credentials were provided. | Supabase test project credentials, redirect allowlist, Apple provider configuration, disposable test personas. |
| High | Apple signing/archive/App Store Connect validation not performed. | Simulator builds/tests pass; no signing credentials or App Store Connect access. | Apple Developer team, bundle IDs, profiles/certificates, App Store Connect app record. |
| High | Physical microphone quality cannot be proven in simulator. | Native audio fixture tests exist; simulator cannot validate brass microphone capture. | Physical iPhone/iPad protocol in `PHYSICAL_DEVICE_PROTOCOL.md`. |
| Medium | Combined `xcodebuild test` can fail with CoreSimulator `Busy` when unit/UI runners launch back-to-back. | Unit target and UI target pass separately on fresh temporary simulators; combined action failed with runner preflight Busy. | CI should run native unit and UI steps separately as in `.github/workflows/swift.yml`. |
| Medium | Legal metadata cannot be invented. | In-app privacy/terms/support surfaces exist without owner-specific legal identity. | Owner/legal counsel must provide legal controller, support URL/email, policy URL, and metadata. |

## Deferred Hardening

- Consider short-lived WebSocket tickets after live auth exists; first-message auth currently removes bearer tokens from URLs.
- Make backend account deletion external Supabase revocation/deletion transactional through an outbox/retry worker; current implementation preflights Supabase before local deletion but is not a durable saga.
- Add live environment-gated Supabase integration tests once disposable project credentials are available.
- Add real native Supabase Swift client dependency and production API auth once bundle IDs and provider settings are chosen.
