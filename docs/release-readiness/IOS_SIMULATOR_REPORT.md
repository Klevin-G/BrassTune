# iOS Simulator Report

Updated: 2026-06-21T06:30:28Z

Branch: `arya/final-swift-completion`
Base main SHA: `1c998d5480f52b5fcf0e2c143f5078893caead66`

## Native App Status

Native SwiftUI app location: `swift/BrassTuneApp`

- Xcode project: `swift/BrassTuneApp/BrassTuneApp.xcodeproj`
- App target: `BrassTuneApp`
- Unit test target: `BrassTuneAppTests`
- UI test target: `BrassTuneAppUITests`
- Local package dependency: `../BrassTuneCore`
- Privacy manifest: `BrassTuneApp/Resources/PrivacyInfo.xcprivacy`

## Implemented Native Surfaces

- Auth-first launch with session restoration, gateway, Continue as guest, and sign-out return to gateway.
- Shared BrassTune themes from generated tokens: System, Brass Night, Brass Day, Liquid Clear, Liquid Tinted, High Contrast.
- iOS 26 Liquid Glass wrapper with reduced-transparency and solid fallback.
- Five-tab iPhone shell: Home, Practice, Score, Sessions, More.
- iPad `NavigationSplitView` shell with the full feature list.
- Home, Practice, Score Practice, Sessions, Metronome, Analytics, Progress, Coach, Ensemble, Settings, Privacy, Terms, and Support surfaces.
- Real normal-path native microphone recording through `AVAudioSession` and `AVAudioEngine`; deterministic pitch generation is limited to UI-test injection.
- Local recording playback, text export, deletion, and persisted session metadata.
- Native metronome scheduler and click engine with persisted tempo/meter/subdivision/mute/accent settings.
- Native Score Practice local file import, PDF page counting, image/photo import, VisionKit scanner flow, local source metadata, markers, and delete.
- Keychain-backed auth session storage with Supabase Auth REST request paths.

## Commands And Results

| Check | Result |
|---|---|
| `xcodebuild -version` | Xcode 26.2, Build version 17C52. |
| `swift --version` | Apple Swift version 6.2.3. |
| `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj` | Passed; schemes `BrassTuneApp`, `BrassTuneAppUISmoke`, `BrassTuneCore`. |
| `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift Testing tests. |
| Debug simulator build | XcodeBuildMCP `build_sim`, scheme `BrassTuneApp`, Debug, iPhone 17 iOS 26.2 `F05D449A-5102-489A-913A-8CD9BB37EF5E`: passed, no warnings. |
| App unit tests | XcodeBuildMCP `test_sim`, `-only-testing:BrassTuneAppTests`: passed, `9` XCTest cases. |
| App UI smoke | XcodeBuildMCP `test_sim`, scheme `BrassTuneAppUISmoke`, focused first-launch/practice/session/settings journey: passed, `1` XCUITest. |
| Release simulator build | XcodeBuildMCP `build_sim`, scheme `BrassTuneApp`, Release: passed, no warnings. |
| Screenshot | `docs/release-readiness/native-screenshots/iphone-home-tabs-2026-06-21.jpg` captured from iPhone 17 simulator and visually inspected. |
| Signed archive | Not run; blocked by Apple Developer credentials/signing profiles. |

## Simulator Notes

- UI smoke runs through guest mode with deterministic test injection; normal app recording path uses the microphone engine.
- The compact iPhone tab bar now has exactly five primary tabs and the screenshot shows no visible Home content behind the floating tab surface.
- Score Practice camera scanning reports unavailable on devices/simulators that do not support `VNDocumentCameraViewController`.
- Simulator evidence does not prove physical microphone quality, Bluetooth/wired routing, brass-room acoustics, or App Store signing.

## External Blockers

- No signed archive was produced because Apple Developer credentials/signing profiles are not available.
- Physical microphone/brass validation remains hardware-gated.
- Live Supabase, Google, and Apple provider lifecycle validation remains owner-credential-gated.
