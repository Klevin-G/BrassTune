# Security and Privacy Data Map
Project attribution: Kelvin Guo, Arya Salem.

## Current local Classes MVP privacy addendum

The local Classes MVP permits role-scoped sharing of aggregate practice
participation and timing/pitch progress after the applicable consent flow. It
does not share raw audio, recordings, reflection text, imported-score content,
note events, or private per-session detail with a class owner or assistant.
Legacy members must re-consent before their data participates in this updated
class-sharing flow. These are source/local boundaries: the new Classes
migration `20260824031433` is applied/read back with its five constraints, UUID
default, RLS, and anon/auth direct-SELECT boundary validated. Live consent
enforcement and cross-account denial still need disposable acceptance testing.

Updated: 2026-08-23. This document distinguishes deployed implementation `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0` from native archive source `d371100`; it does not turn remaining unattended lifecycle checks into passes.

## Current boundary

Profile display-name/avatar safeguards and their private-storage migration are
deployed with release implementation `98fd1d9`. The published App Store privacy
declaration includes the corresponding Name and Photos or Videos entries. Live
configuration and deployed behavior do not replace disposable-account lifecycle
acceptance for replacement/removal, export, deletion, and cross-user denial.

## Data and controls

| Data | Purpose | Boundary/control |
|---|---|---|
| Account/profile and display name | Authentication, identity, and account-profile completion | Supabase-backed auth; browser never receives service keys. The display name is account-linked and is not used for ads or tracking. |
| Optional profile photo | Signed-in account profile | Deployed private `profile-avatars` Storage bucket accessed through authenticated backend routes only. `GET /api/users/me/avatar` has its own per-client read budget, configured by `BRASSTUNE_AVATAR_READ_RATE_LIMIT_PER_MINUTE` (default `30`); `PUT` remains under the existing expensive account-mutation limit. Replacement/removal and account deletion queue cleanup. Disposable-account lifecycle acceptance remains pending. |
| Practice metrics | Tuning, goals, progress, drills | Local-first for guests; authenticated cloud paths are scoped to the account. |
| Passive microphone input and pitch frames | Live tuner and microphone-assisted practice feedback | Raw passive mic frames are processed locally during the active listening feature and are not uploaded. Derived practice metrics follow the account/guest session boundary. |
| Explicit web recorded-take audio | Optional practice playback | Guest audio is browser-local. A signed-in explicit take uploads through the authenticated application/storage path when the person stops it. The deployed same-origin proxy/delete repair is covered by hosted strict Playwright; disposable-account playback/export/deletion and final object-absence acceptance remain pending. |
| Explicit native recorded-take audio | Pitch analysis and optional listen-back | A recorded take is retained app-locally until deletion, local-data clearing, or explicit export/share; it is not uploaded automatically. |
| Score material | Practice import | Analyzed locally by current web score practice; not uploaded by BrassTune. |
| Class membership | Ensembles and roles | Backend authorization and quotas; class reports are aggregate-only. |
| Class aggregates | Teacher/director feedback | Class-report scope is cloud practice totals since membership; no recordings, reflections, or raw session detail. |
| Deletion/export | User lifecycle | Deployed signed-in **Delete saved audio** and backend same-origin proxy repair. The avatar export contract includes `account.json` profile metadata plus the current avatar only as `profile/avatar.jpg` and bounded `profile/avatar.json`; it omits raw storage keys/paths and has no avatar entries when absent. Live deletion, final object absence, account deletion, export contents, and cross-user denial remain unverified. |

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
are published for submitted build 7 and must be reconciled against future signed
builds and live cloud paths.

For the profile feature, the prepared App Privacy mapping is **Name** and
**Photos or Videos**, each linked to the user, not used for tracking, and used
for **App Functionality**. The implementation does not use profile data for ads,
marketing, ad measurement, or data-broker sharing. Apple defines these data
types and its tracking boundary in [App Privacy
Details](https://developer.apple.com/app-store/app-privacy-details/). This
mapping is published in App Store Connect for the submitted build-7 version;
it is not a substitute for lifecycle acceptance evidence.

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

The linked project includes the applied private-avatar migration as well as the
earlier account-deletion/privacy migrations. Live schema/storage configuration
is verified; migration state alone does not prove lifecycle behavior.

The deployed backend includes the audio deletion/proxy repair. Application-level
disposal/export verification, signed-in recording deletion and final object
absence, account deletion, live cross-user denial, and class-privacy behavior
still require disposable-account acceptance. Migration state and hosted strict
browser coverage do not prove those lifecycles.

## Remaining risks and gates

- Verify disposal/export lifecycle, signed-in recording deletion and final storage-object absence, account deletion, and live cross-user denial with non-personal test accounts.
- Verify private-profile authenticated read/write boundaries, replacement/removal
  cleanup, account-deletion cleanup, and account-export metadata with a
  disposable account.
- Reconcile published Name/Photos-or-Videos nontracking App Privacy answers
  with future signed builds and production behavior.
- Keep provider deployment and hosted smoke evidence tied to the exact deployed
  SHA; GitHub Actions status is not a substitute for that evidence.
- Native/web provider configuration is deployed. Live provider lifecycle,
  signed-in storage lifecycle, and attended physical-device audio remain
  separate gates.
