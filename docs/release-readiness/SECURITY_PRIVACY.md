# Security and Privacy Data Map
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. This document distinguishes observed production behavior from local-only source changes; it does not establish a deployed revision for local-only work.

## Current boundary

Privacy/security work has source-level safeguards and documented release gates.
The profile display-name/avatar implementation and its private-storage migration
are local-only at this writing; they are not proof of a deployed backend or an
updated App Store Connect record. Validation and deployment evidence must be
recorded against the final merged revision.

## Data and controls

| Data | Purpose | Boundary/control |
|---|---|---|
| Account/profile and display name | Authentication, identity, and account-profile completion | Supabase-backed auth; browser never receives service keys. The display name is account-linked and is not used for ads or tracking. |
| Optional profile photo | Signed-in account profile | Local source/migration is designed for a private `profile-avatars` Storage bucket accessed through authenticated backend routes only. `GET /api/users/me/avatar` has its own per-client read budget, configured by `BRASSTUNE_AVATAR_READ_RATE_LIMIT_PER_MINUTE` (default `30`); `PUT` remains under the existing expensive account-mutation limit. Replacement/removal and account deletion are designed to queue cleanup. Backend lifecycle validation and deployment evidence remain pending. |
| Practice metrics | Tuning, goals, progress, drills | Local-first for guests; authenticated cloud paths are scoped to the account. |
| Passive microphone input and pitch frames | Live tuner and microphone-assisted practice feedback | Raw passive mic frames are processed locally during the active listening feature and are not uploaded. Derived practice metrics follow the account/guest session boundary. |
| Explicit web recorded-take audio | Optional practice playback | Guest audio is browser-local. A signed-in explicit take uploads through the authenticated application/storage path when the person stops it. A prior synthetic signed-in recording/session persisted there; playback and export then failed when the backend redirected to cross-origin Storage: the privacy-safe followed fetch raised `TypeError`, and a manual request encountered an opaque redirect. One synthetic recording remains. |
| Explicit native recorded-take audio | Pitch analysis and optional listen-back | A recorded take is retained app-locally until deletion, local-data clearing, or explicit export/share; it is not uploaded automatically. |
| Score material | Practice import | Analyzed locally by current web score practice; not uploaded by BrassTune. |
| Class membership | Ensembles and roles | Backend authorization and quotas; class reports are aggregate-only. |
| Class aggregates | Teacher/director feedback | Class-report scope is cloud practice totals since membership; no recordings, reflections, or raw session detail. |
| Deletion/export | User lifecycle | A signed-in **Delete saved audio** source and backend same-origin proxy repair exist locally only and are not deployed. The local avatar export contract includes `account.json` profile metadata plus the current avatar only as `profile/avatar.jpg` and bounded `profile/avatar.json`; it omits raw storage keys/paths and has no avatar entries when absent. Live deletion, final object absence, account deletion, export contents, and cross-user denial remain unverified. |

## Native privacy and encryption declaration

The checked-in iOS privacy manifest declares linked email address, account
identifier, Name, Photos or Videos, and other user content solely for app
functionality, with tracking disabled; it does not declare audio data. Confirm
that this mapping remains in the final signed binary. Native microphone capture
supports local pitch analysis and, when a person records a take, app-local
listen-back. That audio is not uploaded automatically or retained as account
data; it remains on-device until deletion, local-data clearing, or explicit
export/share. Imported scores and local practice content remain on-device unless
a person explicitly shares or exports them. App Store Connect privacy answers
must be reconciled against the final signed build and live cloud paths.

For the profile feature, the prepared App Privacy mapping is **Name** and
**Photos or Videos**, each linked to the user, not used for tracking, and used
for **App Functionality**. The implementation does not use profile data for ads,
marketing, ad measurement, or data-broker sharing. Apple defines these data
types and its tracking boundary in [App Privacy
Details](https://developer.apple.com/app-store/app-privacy-details/). This
mapping is not an App Store Connect update.

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
- Deploy and verify private profile-avatar storage, authenticated read/write
  boundaries, replacement/removal cleanup, account-deletion cleanup, and
  account-export metadata with a disposable account before any privacy claim.
- Verify that the final signed privacy manifest retains linked/nontracking Name
  and Photos or Videos for App Functionality only, then save the corresponding
  App Store Connect App Privacy questionnaire. The questionnaire remains
  unsaved at this writing.
- Keep GitHub Actions disabled; direct provider deployment and hosted smoke are the release path.
- Apple web Services ID/rotating secret, native Apple Face ID completion/callback/session, signing, archive, App Store Connect privacy answers, and physical-device audio remain external gates.
