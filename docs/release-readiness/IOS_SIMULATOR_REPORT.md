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
- Practice tuner with live, sample, no-lock, and unstable states.
- AVAudioEngine live microphone path, deterministic sample recording path, and saved sessions.
- Session review, relisten fixture state, export/share, deletion surface.
- Analytics, progress, recommendations.
- Ensemble summary/student view fixture state.
- Settings, sign-in/sign-out surfaces, account deletion confirmation, data export link.
- Privacy Policy, Terms of Service, Support.
- Keychain-backed auth session storage with Supabase Auth REST request paths.
- AVAudioEngine permission/request path, PCM input tap path, local pitch detector, and deterministic audio fixture path.

## Commands And Results

| Check | Result |
|---|---|
| `xcodebuild -version` | Xcode 26.2, Build version 17C52. |
| `swift --version` | Apple Swift version 6.2.3. |
| `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj` | Passed; schemes `BrassTuneApp`, `BrassTuneAppUISmoke`, `BrassTuneCore`. |
| `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift Testing tests. |
| Current app unit tests | `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination 'platform=iOS Simulator,id=F05D449A-5102-489A-913A-8CD9BB37EF5E' -only-testing:BrassTuneAppTests CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO` passed: `18` XCTest cases. |
| Current app UI smoke execution | Blocked before app launch by CoreSimulator `SBMainWorkspace`/preflight `Busy` after the UI test labels were updated for the current sample/live wording. |
| Current Release simulator build | `xcodebuild build -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination 'platform=iOS Simulator,id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO` passed. |
| iPhone Debug build | Passed on simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`; derived data `/tmp/brasstune-dd-debug-iphone-handoff-final`. |
| iPhone Release build | Passed on simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`; derived data `/tmp/brasstune-dd-release-iphone-handoff-final`. |
| iPad Debug build | Passed on simulator `CEC7E3E1-8B2E-4C6B-8E8E-486657046FCE`; derived data default. |
| App UI execution | Current UI smoke attempts are blocked by CoreSimulator preflight `Busy`; previous UI passes are historical and must be rerun before being used as current release evidence. |
| Signed archive | Not run; blocked by Apple Developer credentials/signing profiles. |

## Simulator Notes

- Explicit `xcodebuild` commands were used with dynamically discovered simulator IDs.
- Dynamic simulator discovery and explicit simulator boot/wait are required in CI and are implemented in `.github/workflows/swift.yml`.
- Xcode emitted non-blocking `[MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.` warnings; builds/tests still passed.
- The iPhone compact tab bar collapses Settings under `More`; the UI test now follows that route and the Settings Data section is first so export/delete controls are immediately discoverable.
- The practice tuner now observes nested `NativeAudioEngine` state directly, so recording/ready transitions are visible to users and deterministic for UI smoke assertions.
- Current UI smoke attempts failed before the test body completed with CoreSimulator `Busy` runner preflight errors.
- Release build settings still show unsigned local simulator execution only: `CODE_SIGNING_ALLOWED=NO`, empty `DEVELOPMENT_TEAM`, and bundle id `com.brasstune.BrassTuneApp.dev`.

## Blockers

- No signed archive was produced because Apple Developer credentials/signing profiles are not available.
- Simulator testing does not validate physical microphone quality, route changes, Bluetooth/wired input, or real brass-room acoustics.
- The live audio path is implemented locally but remains unvalidated on physical hardware; simulator/sample evidence is not a native closed-beta or Apple-release readiness claim.
