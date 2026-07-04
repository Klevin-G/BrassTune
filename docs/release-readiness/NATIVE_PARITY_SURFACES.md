# Native Swift Parity Surfaces

Date: 2026-07-04

Branch: `arya/native-swift-parity-surfaces-20260628`

## Scope

This native branch carries SwiftUI surface parity work only. It does not certify the web production recovery gate, Render deployment state, Vercel deployment state, Supabase production migrations, or live auth/storage/account-deletion journeys.

Included native scope:

- Dark BrassTune visual system aligned with the web app.
- Native theme colors checked against `design/brasstune-tokens.json` by `swift/BrassTuneApp/scripts/verify_design_tokens.py`.
- Liquid Glass-gated panel styling where the active SDK supports it.
- Bento-style dashboard, onboarding, practice, analytics, coach, metronome, score practice, settings, sessions, and More hub surfaces.
- Native navigation separation for Home, Practice, Analytics, Coach, and More.
- Floating recording control bar with stop, metronome start/stop, tempo step, tap tempo, mute, BPM, meter, and score context.
- Native metronome state, visual pulse, audible click output, haptic pulse option, meter, subdivision, mute, volume, tap tempo, and headphone/click-bleed guidance.
- Local score assist for PDF, JPEG, PNG, HEIC, Photos data, synthetic sample scores, thumbnails, page selection, rotate/crop/enhance preview, local annotations, metadata export, and delete.
- Local session persistence, post-record summaries, score attachment, local export, and clear/delete local-data controls.
- UI smoke coverage for onboarding/guest entry, practice recording, floating metronome bar, Coach, More, Sessions, Settings, Metronome, and Score Practice sample import/rotate.
- Self-hosted Swift runner fallback through `BRASSTUNE_SWIFT_RUNNER`.

## Native Gate

Required evidence before calling native parity complete:

- `cd swift/BrassTuneCore && swift test`
- `python3 swift/BrassTuneApp/scripts/verify_design_tokens.py`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests/BrassTuneAppUITests/testLaunchPracticeAndSettingsSurfaces`

Use `xcrun simctl list devices available` to select an available simulator. Do not hard-code a device name without checking availability.

## Explicit Non-Claims

- No TestFlight or App Store readiness is claimed.
- No Apple Developer signing, App Store Connect validation, notarization, or archive upload is claimed.
- No physical-device microphone quality, brass-room acoustics, or click-bleed validation is claimed.
- Camera score capture is intentionally hidden until a real native camera flow and physical-device validation exist.
- Score assist is on-device/private and heuristic. It does not claim trained optical music recognition or network AI.
- Simulator tests cover deterministic sample/fixture flows, not live brass acoustic quality or Apple release certification.

## Runner Configuration

If GitHub-hosted macOS Actions remain blocked by billing or spending-limit status, configure a BrassTune-scoped macOS self-hosted runner and set:

```json
["self-hosted","brasstune","macos","xcode"]
```

as repository variable `BRASSTUNE_SWIFT_RUNNER`.

Do not run untrusted fork pull-request code on a self-hosted runner that has production secrets or broad repository access.
