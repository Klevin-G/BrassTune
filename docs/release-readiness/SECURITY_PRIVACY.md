# Security and Privacy Data Map

Updated: 2026-07-24. This document describes the current source-tree contract; it does not establish a deployed revision.

## Current boundary

Privacy/security work has source-level safeguards and documented release gates. Validation and deployment evidence must be recorded against the final merged revision; this document does not claim a current hosted result.

## Data and controls

| Data | Purpose | Boundary/control |
|---|---|---|
| Account/profile | Authentication and identity | Supabase-backed auth; browser never receives service keys. |
| Practice metrics | Tuning, goals, progress, drills | Local-first for guests; authenticated cloud paths are scoped to the account. |
| Web audio | Optional practice playback | Guest audio is browser-local. Signed-in web audio uploads automatically when the user stops a recorded take, through the authenticated backend/Supabase path. |
| Native audio | Pitch analysis and optional listen-back | A recorded take is retained app-locally until deletion, local-data clearing, or explicit export/share; it is not uploaded automatically. |
| Score material | Practice import | Analyzed locally by current web score practice; not uploaded by BrassTune. |
| Class membership | Ensembles and roles | Backend authorization and quotas; class reports are aggregate-only. |
| Class aggregates | Teacher/director feedback | Class-report scope is cloud practice totals since membership; no recordings, reflections, or raw session detail. |
| Deletion/export | User lifecycle | Privacy scrub/tombstone rollout plus a live disposable-account verification gate. |

## Native privacy and encryption declaration

The iOS privacy manifest declares linked email address, account identifier, and account-linked user content solely for app functionality; it does not declare audio data. Native microphone capture supports local pitch analysis and, when a person records a take, app-local listen-back. That audio is not uploaded automatically or retained as account data; it remains on-device until deletion, local-data clearing, or explicit export/share. Imported scores and local practice content remain on-device unless a person explicitly shares or exports them. App Store Connect privacy answers must be reconciled against the final signed build and live cloud paths.

Class directors and class-report surfaces see aggregate cloud practice totals from membership onward. They do not receive recordings, reflection text, or private session detail. A limited set of authorized BrassTune service administrators may access account/session/audio data only for security, support, abuse investigation, or service operation.

`ITSAppUsesNonExemptEncryption` is `false` for this build: it uses Apple-provided HTTPS/TLS transport and platform security services, with no proprietary encryption implementation. Revisit this declaration before shipment if custom cryptography or a non-exempt encryption feature is added.

## OAuth boundary

Web OAuth uses PKCE and a sanitized, session-scoped return path. Native Google and Apple implementations remain in source for future dual-provider work, but neither third-party OAuth control is presented in the Apple-deferred native build. Never log provider tokens or secrets.

## Supabase rollout

The linked project reports matching local and remote migration history through `20260724072904_account_deletion_maintenance_heartbeats.sql`. That migration enables RLS and revokes public, `anon`, `authenticated`, and `service_role` access to the maintenance-heartbeat table; only the backend database role should use it. The earlier audio reservation, deletion tombstone, privacy reassertion, and terminal privacy-contract migrations also remain matched.

Application-level disposable-account export/delete verification, signed-in recording upload/deletion, and class-privacy behavior still require the exact deployed backend. Migration state alone does not prove those hosted lifecycles.

## Remaining risks and gates

- Verify disposable auth/export/delete lifecycle, signed-in recording upload/deletion, and storage cleanup with non-personal test accounts.
- Keep GitHub Actions disabled; direct provider deployment and hosted smoke are the release path.
- Apple credentials, Services ID, signing, archive, App Store Connect privacy answers, and physical-device audio remain external gates.
