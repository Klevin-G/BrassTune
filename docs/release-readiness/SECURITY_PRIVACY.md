# Security and Privacy Data Map

Updated: 2026-08-04. This document distinguishes observed production behavior from local-only source changes; it does not establish a deployed revision for local-only work.

## Current boundary

Privacy/security work has source-level safeguards and documented release gates. Production web Google lifecycle behavior was observed, while the new signed-in audio deletion UI and same-origin storage proxy repair are local-only and not deployed. Validation and deployment evidence must be recorded against the final merged revision.

## Data and controls

| Data | Purpose | Boundary/control |
|---|---|---|
| Account/profile | Authentication and identity | Supabase-backed auth; browser never receives service keys. |
| Practice metrics | Tuning, goals, progress, drills | Local-first for guests; authenticated cloud paths are scoped to the account. |
| Web audio | Optional practice playback | Guest audio is browser-local. A synthetic signed-in recording/session persisted through the authenticated application/storage path. Playback and export then failed when the backend redirected to cross-origin Storage: the privacy-safe followed fetch raised `TypeError`, and a manual request encountered an opaque redirect. One synthetic recording remains. |
| Native audio | Pitch analysis and optional listen-back | A recorded take is retained app-locally until deletion, local-data clearing, or explicit export/share; it is not uploaded automatically. |
| Score material | Practice import | Analyzed locally by current web score practice; not uploaded by BrassTune. |
| Class membership | Ensembles and roles | Backend authorization and quotas; class reports are aggregate-only. |
| Class aggregates | Teacher/director feedback | Class-report scope is cloud practice totals since membership; no recordings, reflections, or raw session detail. |
| Deletion/export | User lifecycle | A signed-in **Delete saved audio** source and backend same-origin proxy repair exist locally only and are not deployed. Live deletion, final object absence, account deletion, and cross-user denial remain unverified. |

## Native privacy and encryption declaration

The iOS privacy manifest declares linked email address, account identifier, and account-linked user content solely for app functionality; it does not declare audio data. Native microphone capture supports local pitch analysis and, when a person records a take, app-local listen-back. That audio is not uploaded automatically or retained as account data; it remains on-device until deletion, local-data clearing, or explicit export/share. Imported scores and local practice content remain on-device unless a person explicitly shares or exports them. App Store Connect privacy answers must be reconciled against the final signed build and live cloud paths.

Class directors and class-report surfaces see aggregate cloud practice totals from membership onward. They do not receive recordings, reflection text, or private session detail. A limited set of authorized BrassTune service administrators may access account/session/audio data only for security, support, abuse investigation, or service operation.

`ITSAppUsesNonExemptEncryption` is `false` for this build: it uses Apple-provided HTTPS/TLS transport and platform security services, with no proprietary encryption implementation. Revisit this declaration before shipment if custom cryptography or a non-exempt encryption feature is added.

## OAuth boundary

Web OAuth uses PKCE and a sanitized, session-scoped return path. Native Apple
and Google controls are enabled. Native Google completed once on physical
`.dev` with callback, cold restore, sign-out, and signed-out relaunch. An
attended native Apple lifecycle and a fresh Safari Apple web lifecycle also
completed callback, restore, sign-out, and signed-out reload. The Apple web
Services ID is first in the provider client-ID list; its rotating secret is
stored outside Git. Never log or commit provider tokens, `.p8` material, or
generated client secrets.

## Supabase rollout

The linked project reports matching local and remote migration history through `20260724072904_account_deletion_maintenance_heartbeats.sql`. That migration enables RLS and revokes public, `anon`, `authenticated`, and `service_role` access to the maintenance-heartbeat table; only the backend database role should use it. The earlier audio reservation, deletion tombstone, privacy reassertion, and terminal privacy-contract migrations also remain matched.

Normal auth/session/application/storage test data was created during validation, without provider configuration/schema/credential changes. The deployed backend has not received the local audio deletion/proxy repair. Application-level disposal/export verification, playback/export through the final storage path, signed-in recording deletion and final object absence, account deletion, live cross-user denial, and class-privacy behavior still require the exact deployed backend. Migration state alone does not prove those hosted lifecycles.

## Remaining risks and gates

- Deploy and verify the signed-in audio deletion UI plus same-origin proxy repair before treating playback/export or deletion as fixed.
- Verify disposal/export lifecycle, signed-in recording deletion and final storage-object absence, account deletion, and live cross-user denial with non-personal test accounts.
- Keep GitHub Actions disabled; direct provider deployment and hosted smoke are the release path.
- Apple web Services ID/rotating secret, native Apple Face ID completion/callback/session, signing, archive, App Store Connect privacy answers, and physical-device audio remain external gates.
