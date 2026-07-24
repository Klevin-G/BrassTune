# Security and Privacy Data Map

Updated: 2026-07-23. Candidate source revision: `7c12b15`.

## Current boundary

Local privacy/security work is implemented and locally tested. `428a123` fixes the duplicate-identity PII race and the full backend suite passed `246 passed, 4 skipped`. Three additive Supabase migrations remain pending; no migration, config push, or hosted deployment is claimed complete in this document.

## Data and controls

| Data | Purpose | Boundary/control |
|---|---|---|
| Account/profile | Authentication and identity | Supabase-backed auth; browser never receives service keys. |
| Practice metrics | Tuning, goals, progress, drills | Local-first for guests; authenticated cloud paths are scoped to the account. |
| Audio/score material | Optional practice playback/import | Local by default; cloud use is explicit and scoped. |
| Class membership | Ensembles and roles | Backend authorization and quotas; class reports are aggregate-only. |
| Class aggregates | Teacher/director feedback | Scope is cloud practice sessions since membership; no recordings, reflections, or raw session detail. |
| Deletion/export | User lifecycle | Privacy scrub/tombstone rollout plus a live disposable-account verification gate. |

## OAuth boundary

Web OAuth uses PKCE and a sanitized, session-scoped return path. iOS Google OAuth uses an ephemeral `ASWebAuthenticationSession`, PKCE, state validation, an exact custom callback, and Keychain storage. iOS Apple uses `SignInWithAppleButton` with a hashed nonce and Supabase token exchange. Never log provider tokens or secrets.

## Supabase rollout

The linked project has three pending additive migrations:

1. `20260716201825_audio_storage_jobs_and_upload_reservations.sql`
2. `20260723021828_account_deletion_privacy_tombstones.sql`
3. `20260723120000_reassert_backend_data_and_audio_privacy.sql`

Apply and verify these expand changes only after the final candidate is merged and the privacy-aware backend is ready. Then create, review, and apply the terminal contract migration in a separate change. Do not create/apply the contract early: its prerequisites are backend expand cleanup and retained privacy-aware rollback evidence.

## Remaining risks and gates

- Run exact-SHA self-hosted CI and independent review.
- Verify provider configuration, disposable auth/export/delete lifecycle, storage, and hosted WebSocket behavior live.
- Apple credentials, Services ID, signing, archive, and physical-device audio remain external gates.
