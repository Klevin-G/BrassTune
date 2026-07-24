# Security and Privacy Data Map

Updated: 2026-07-24. Candidate source revision: `PENDING_FINAL_SHA`.

## Current boundary

Local privacy/security work is implemented and independently reviewed with no P0-P2 source finding. The full backend suite passed `286 passed, 11 skipped`. The linked Supabase migration history matches through `20260724072904`; no hosted application deployment is claimed complete in this document.

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

The linked project reports matching local and remote migration history through `20260724072904_account_deletion_maintenance_heartbeats.sql`. That migration enables RLS and revokes public, `anon`, `authenticated`, and `service_role` access to the maintenance-heartbeat table; only the backend database role should use it. The earlier audio reservation, deletion tombstone, privacy reassertion, and terminal privacy-contract migrations also remain matched.

Application-level disposable-account export/delete verification still requires the exact deployed backend. The migration state alone does not prove that hosted lifecycle.

## Remaining risks and gates

- Commit the exact candidate and deploy it directly; GitHub Actions is disabled and must not be used.
- Verify provider configuration, disposable auth/export/delete lifecycle, storage, and hosted WebSocket behavior live.
- Apple credentials, Services ID, signing, archive, and physical-device audio remain external gates.
