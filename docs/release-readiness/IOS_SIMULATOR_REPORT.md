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
| `xcodebuild -version` | Xcode 26.2, Build version 17C52. |
| `swift --version` | Apple Swift version 6.2.3. |
| `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj` | Passed; schemes `BrassTuneApp`, `BrassTuneAppUISmoke`, `BrassTuneCore`. |
| `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift Testing tests. |
| iPhone Debug build | Passed on simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`; derived data `/tmp/brasstune-dd-debug-iphone-handoff-final`. |
| iPhone Release build | Passed on simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`; derived data `/tmp/brasstune-dd-release-iphone-handoff-final`. |
| iPad Debug build | Passed on simulator `C86B38C3-D50B-48F3-8E21-1FD7A44FCC81`; derived data `/tmp/brasstune-dd-debug-ipad-handoff-final`. |
| App unit tests | Prior local pass on iPhone Air simulator `2582DE9B-57B8-41F1-8A17-49CDD5F6D8ED`; latest CI repair passes locally against an explicit simulator ID with `3` XCTest cases. PR head `fc7ee5d` failed before the scheme/actor/active-arch fixes. |
| App UI tests | Prior local pass on iPhone Air simulator `2582DE9B-57B8-41F1-8A17-49CDD5F6D8ED`; latest CI repair passes the split `BrassTuneAppUISmoke` scheme with `1` XCUITest against an explicit simulator ID. |
| Signed archive | Not run; blocked by Apple Developer credentials/signing profiles. |

## Simulator Notes

- Explicit `xcodebuild` commands were used with dynamically discovered simulator IDs.
- Dynamic simulator discovery and explicit simulator boot/wait are required in CI and are implemented in `.github/workflows/swift.yml`.
- Xcode emitted non-blocking `[MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.` warnings; builds/tests still passed.
- The iPhone compact tab bar collapses Settings under `More`; the UI test now follows that route and the Settings Data section is first so export/delete controls are immediately discoverable.
- Two intermediate UI attempts failed before the test body completed with CoreSimulator `Busy` runner preflight errors. Restarting CoreSimulator and running on a fresh iPhone Air simulator produced the passing UI result above.
- Release build settings still show unsigned local simulator execution only: `CODE_SIGNING_ALLOWED=NO`, empty `DEVELOPMENT_TEAM`, and bundle id `com.brasstune.BrassTuneApp.dev`.

## Blockers

- No signed archive was produced because Apple Developer credentials/signing profiles are not available.
- Simulator testing does not validate physical microphone quality, route changes, Bluetooth/wired input, or real brass-room acoustics.
- Several native product flows remain deterministic fixture surfaces rather than production API/audio-backed implementations; simulator pass is not a native closed-beta readiness claim.
