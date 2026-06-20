# TestFlight Handoff

Updated: 2026-06-20 UTC.

## Current State

- Native project exists under `swift/BrassTuneApp`.
- Swift package parity tests pass locally.
- Earlier simulator build/unit/UI evidence is documented, but this run did not create a signed archive or upload to TestFlight.
- Native practice/auth/score/analytics/ensemble depth is not equivalent to the web app.

## Required Before TestFlight

1. Final bundle ID and Apple Team ID.
2. Signing certificates/profiles.
3. App Store Connect app record.
4. Marketing version/build number.
5. Final privacy manifest and required-reason API audit.
6. Sign in with Apple capability/provider setup if account access ships.
7. Native API/auth/audio scope decision: production paths or explicit beta/demo scope.
8. Signed archive/export validation.
9. Upload, processing, internal group assignment, and install evidence.

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
