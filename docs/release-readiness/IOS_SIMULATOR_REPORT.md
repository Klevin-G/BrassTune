# iOS Simulator Report

## Native App Added

Native SwiftUI app created under `swift/BrassTuneApp` with:

- Xcode project: `swift/BrassTuneApp/BrassTuneApp.xcodeproj`
- App target: `BrassTuneApp`
- Unit test target: `BrassTuneAppTests`
- UI test target: `BrassTuneAppUITests`
- Local package dependency: `../BrassTuneCore`
- Privacy manifest: `BrassTuneApp/Resources/PrivacyInfo.xcprivacy`

## Implemented Native Surfaces

- Launch and onboarding.
- Instrument/reference-pitch setup.
- Guest/demo mode.
- Home/dashboard.
- Practice tuner with no-lock/fixture states.
- Deterministic recording fixture and saved sessions.
- Session review, relisten fixture state, export/share, deletion surface.
- Analytics, progress, recommendations.
- Ensemble summary/student view fixture state.
- Settings, sign-in/sign-out surfaces, account deletion confirmation, data export link.
- Privacy Policy, Terms of Service, Support.
- Keychain-backed auth session storage with Supabase Auth REST request paths.
- AVAudioEngine permission/request path and deterministic audio fixture path.

## Commands And Results

| Check | Result |
|---|---|
| `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj` | Passed; schemes `BrassTuneApp`, `BrassTuneCore`. |
| Clean Debug build on iPhone 17 iOS 26.2 | Passed. |
| Clean Release build on iPhone 17 iOS 26.2 | Passed. |
| Clean Debug build on iPad Pro 11-inch (M5) iOS 26.2 | Passed. |
| `xcodebuild test ... -only-testing:BrassTuneAppTests` | Passed on iPhone 17 simulator: `3 tests`; xcresult `/tmp/brasstune-dd-unittest-final/Logs/Test/Test-BrassTuneApp-2026.06.18_13-46-20--0500.xcresult`. |
| `xcodebuild test ... -only-testing:BrassTuneAppUITests/...testLaunchPracticeAndSettingsSurfaces` | Passed on fresh temporary iPhone 17 simulator: `1 test`; xcresult `/tmp/brasstune-dd-uitest-final-fresh2/Logs/Test/Test-BrassTuneApp-2026.06.18_13-49-56--0500.xcresult`. |
| Combined `xcodebuild test` | Not used as a gate; it hit CoreSimulator `Busy` runner preflight when unit/UI runners launched back-to-back. The workflow runs unit and UI separately. |

## Simulator Notes

- XcodeBuildMCP was available but had no project/scheme/simulator defaults configured and no setter tool exposed in this thread; explicit `xcodebuild` commands were used.
- Temporary simulators were created for stable unit/UI evidence instead of erasing the user's default simulator.
- Dynamic simulator discovery is required in CI and is implemented in `.github/workflows/swift.yml`.

## Blockers

- No signed archive was produced because Apple Developer credentials/signing profiles are not available.
- Simulator testing does not validate physical microphone quality, route changes, Bluetooth/wired input, or real brass-room acoustics.
