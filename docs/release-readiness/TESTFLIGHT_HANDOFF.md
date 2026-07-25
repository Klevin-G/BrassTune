# TestFlight Handoff

Updated: 2026-07-24 UTC.

## Current State

- Native project exists under `swift/BrassTuneApp`.
- Swift package parity tests pass locally.
- Earlier simulator build/unit/UI evidence is documented, but this run did not create a signed archive, export an IPA, or upload to TestFlight.
- `scripts/ios/build-testflight.sh` now fails closed until a valid Apple Team ID, registered bundle ID, production Supabase HTTPS URL, and public publishable key are supplied; it invokes `CODE_SIGNING_ALLOWED=YES` for archives.
- The Apple entitlement and both native third-party OAuth controls are deferred. Guest practice plus first-party email/password remain available.
- Privacy/legal links are native HTTPS links to `https://brasstune.vercel.app/privacy`, `/terms`, and `/support`; the support page carries the support contact.
- Native practice/auth/score/analytics/ensemble depth is not equivalent to the web app.

## Required Before TestFlight

1. Final bundle ID and Apple Team ID.
2. Signing certificates/profiles.
3. App Store Connect app record.
4. Marketing version/build number.
5. Final privacy manifest and required-reason API audit.
6. Decide and verify the production third-party auth posture. Re-enable both Apple entitlement/control and native Google presentation only after Apple provider/capability setup and live dual-provider testing.
7. Native API/auth/audio scope decision: production paths or explicit beta/demo scope.
8. Signed archive/export validation.
9. Upload, processing, internal group assignment, and install evidence.
10. Reconcile App Store Connect privacy answers with the final signed build: linked email, user ID, and account-linked user content for app functionality; no raw microphone audio collection. Reconfirm the exempt-encryption declaration if cryptography changes.

## Suggested Internal Test Scope

- Launch and onboarding.
- Practice tuner demo/mic behavior.
- Settings, legal, export/delete entry points.
- Account flow only after provider setup.
- Score scanner only after native VisionKit/Photos/file importer implementation.
- Accessibility smoke with Dynamic Type and VoiceOver.
- Physical-device microphone protocol from `PHYSICAL_DEVICE_PROTOCOL.md`.

## Do Not Claim

- App Store readiness.
- Physical microphone quality.
- Production native parity.
- Score scanner parity.
- Account-provider readiness.
