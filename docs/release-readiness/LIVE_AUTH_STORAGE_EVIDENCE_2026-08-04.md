# Live auth and storage evidence — 2026-08-04

> Local-only evidence registry. It contains no credentials or raw identity data,
> but user-home paths must be normalized before external publication.

## Outcome

**BLOCKED.** This is the publishable, sanitized record for the live-auth and
private-audio lifecycle work. It does not replace the existing physical audio
crash-family closure or establish App Store readiness.

## Evidence scope and provenance

- Physical lane: wired iPhone 15 Pro Max on iOS 26.4.1, Developer Mode enabled,
  with Xcode 26.6. Production TestFlight `com.aryasalem.BrassTune` `1.0.0 (2)`
  remained installed; its installation URL was unchanged after the Google,
  Apple, and restored optimized `.dev` exercises.
- The restored optimized Release `.dev` binary is production-environment
  configured, uses the `.dev` callback, is development-signed with
  `get-task-allow=true`, and has SHA-256
  `b5a3fe82dbd2fa298a339f4ea6f187cfb13d85a7734b271d7cd334408e4a7130`.
  It was restored and launched after the UI runner.
- Hosted lane: backend PR 26 merged as
  `1cd195ed75dee61420d497438f4a4b54c07be25f`; Render deployment
  `dep-d9p5j97avr4c73amdkjg` serves that exact revision. Frontend PR 27 merged
  as `288d83091616acc0d906869bb6389721ac3a6017`; Vercel production deployment
  `Do4tBvgN2svvYtQACwgzrxXZE5PK` is Ready at that exact revision. The final
  five-browser hosted matrix completed 45 passed and 5 intentional skips,
  including enabled Google, Apple, and email entry points from fresh storage.
- Raw native result material contains identity-bearing diagnostics and is
  private/quarantined. Do not publish it, quote it, or add a result-bundle path
  to release documentation. This Markdown file is the sanitized citation path.

## Native provider evidence

| Scenario | Result | Boundary |
|---|---|---|
| Google native physical R7 | `1/1` PASS | A real provider completion, app callback, generic signed-in state, cold restore, sign-out, and signed-out relaunch were exercised. |
| Apple native physical R8 | `1/1` PASS | A real provider completion, app callback, generic signed-in state, cold restore, sign-out, and signed-out relaunch were exercised. R7 completed authorization but falsely failed because the test expected Practice after a Settings-presented auth sheet; the narrow Settings-first probe repair was rebuilt before R8. |
| Apple authorized-session cleanup and signed-out preflight R8 | `1/1` PASS each | Confirms R7's authorized `.dev` session was signed out and R8 began from a controlled signed-out state. |
| Current live-provider discovery | `1/1` PASS | The wired Debug `.dev` app rendered both provider controls after a read-only request to the production Supabase provider-settings endpoint. It did not create or persist a session. |
| Current Apple native consent surface | `2/2` PASS | Two consecutive physical repetitions launched Apple's native AuthKit authorization action and stopped before Continue, passcode, biometric authorization, token exchange, or callback. The UI probe now treats Apple's stable `SIWA_CONTINUE_BUTTON` identifier as authoritative across iOS 26 label changes. |
| Current attended Apple native lifecycle repeat | `1/1` PASS | On the wired iPhone 15 Pro Max, the Debug `.dev` app completed Apple authorization, callback, generic signed-in state, cold restore, sign-out, and signed-out cold relaunch in 203.336 seconds. Raw identity-bearing XCTest material remains private/quarantined. |
| Current Google native consent surface | `1/1` PASS | The physical `.dev` app presented the BrassTune-specific system web-auth consent alert and stopped before Continue, account selection, token exchange, or callback. |
| Current simulator auth regressions | `2/2` PASS | Exact nonce/token forwarding plus development-only auth-persistence bypass passed on iPhone 17 Pro / iOS 26.5. This is not physical-provider completion evidence. |

## Hosted signed-in private-audio evidence

An authorized ordinary-student Google session restored. One synthetic Demo WAV
was uploaded and its session metadata persisted; the owner-visible row passed.
Playback and export both failed on the earlier deployed revision.

A privacy-safe in-page probe observed a followed fetch `TypeError` and a
`redirect: manual` response with status `0` and type `opaqueredirect`. This
isolates a cross-origin redirect/data-plane failure. The reviewed same-origin
proxy and signed-in delete control were subsequently deployed at
`1cd195ed75dee61420d497438f4a4b54c07be25f`; the earlier redirect failure is
preserved as reproduction evidence and is no longer an accurate description of
source availability. Signed-out playback and export now return HTTP `401` with
`Cache-Control: no-store`. Authenticated owner responses have not yet been
verified for `private, no-store` handling. Web sign-out and signed-out reload passed. Owner
playback/export/delete, cross-user denial, final Storage absence, and account
deletion have not yet been repeated against the deployed repair.

The production Apple web button is compiled as enabled at frontend SHA
`288d83091616acc0d906869bb6389721ac3a6017`. Apple Developer now has Sign in
with Apple enabled for Services ID `com.aryasalem.BrassTune.web`, with the
production App ID as primary, the production Supabase domain, and its exact
callback URL. A dedicated Sign in with Apple key was created and retained only
outside the repository. The production Supabase Apple provider now contains the
web Services ID first, followed by the production and `.dev` native App IDs,
and a masked saved client secret. A fresh Safari Apple authorization completed,
created a production Apple social-auth identity, returned through the Supabase
callback to BrassTune, restored the signed-in session after reload, signed out,
and remained signed out after another reload. The provider dashboard independently
showed the new identity as Apple-backed. An older preconfiguration authorization
tab still retains its historical `Unsupported provider: missing OAuth secret`
response; the refreshed provider form remains enabled with the ordered client IDs
and masked secret, and the fresh flow is the current result. Native Apple R8 and
the current attended physical repeat remain valid and separate. The current
physical Google probe also reached its consent alert and stopped before account
choice.

## Production data and configuration boundary

This follow-up changed only Apple Developer Sign in with Apple configuration
and the production Supabase Auth Apple provider: the Services ID web
configuration, dedicated key, ordered client IDs, and client secret were saved.
No Supabase database schema, migration, table, row, Storage bucket, object,
redirect policy, or RLS/grant setting was changed by this configuration pass.
The secret and private key were not printed, added to the repository, or stored
in browser password storage. The non-secret GitHub Production variable and
Vercel Production environment variable `VITE_AUTH_APPLE_ENABLED` were set to
`true`; Vercel then performed a full no-cache production rebuild. The
authorized sign-in/upload and the fresh Apple web sign-in created normal
production Auth, session, application, and Storage test data. The fresh Apple
session was signed out but its ordinary Auth identity remains. The synthetic recording remains
because authenticated deletion has not yet been exercised against the deployed
control. Therefore this work must not be described as zero Supabase data
mutation.

No live cross-user/BOLA denial, live audio deletion, account deletion, or
final Storage-absence verification was performed. App Store Connect was
untouched; no build 3, archive, upload, or release folder was created.

## Current regression context

- Exact candidate frontend: `269` passed; focused deletion `30/30`, independent
  focused audit `34/34`, TypeScript, production/PWA/locale build, and guest-audio
  Playwright `20/20` passed.
- Exact candidate backend: complete suite `305` passed and `11` skipped;
  focused proxy `4/4`, final resource-close `1/1`, independent
  proxy/header/delete `11/11`, and audio hardening `35/35` passed.
- Frontend focused regressions: `30` passed; the full local frontend run
  remains `275/275` passed.
- Swift Core: `12/12` passed.
- Exact signed generic-device `PHYSICAL_RELEASE` runner compile passed.
- XcodeBuildMCP simulator build passed. Its wrapper test call exceeded the
  600-second wait window, while the retained `xcodebuild` log later recorded
  `22/22` passed with zero failures in 598.950 test seconds / 609.114 elapsed.
- Device simulation passed all 13 configured viewports after isolating a stale
  local server and reusing the repository Python environment.
- Final crash-log listing found no new BrassTune report after 12:16 PM and
  none from the current 15:xx runs.

## Next steps

Complete owner playback/export/delete, cross-user denial, final Storage
absence, and disposable
account deletion against the exact deployed revisions. Outcome remains
**BLOCKED** until those checks and the other documented release gates pass.
