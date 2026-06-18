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
| `xcodebuild test ... -only-testing:BrassTuneAppTests -only-testing:BrassTuneAppUITests/...testLaunchPracticeAndSettingsSurfaces` | Passed on dynamically selected iPhone simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`: `3 unit tests`, `1 UI test`; xcresult under Xcode DerivedData. |
| `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO clean build` | Passed on dynamically selected iPhone simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`; derived data `/tmp/brasstune-dd-debug-iphone-final`. |
| `xcodebuild ... -configuration Debug ... CODE_SIGNING_ALLOWED=NO clean build` | Passed on dynamically selected iPad simulator `C86B38C3-D50B-48F3-8E21-1FD7A44FCC81`; derived data `/tmp/brasstune-dd-debug-ipad-final`. |
| `xcodebuild ... -configuration Release ... CODE_SIGNING_ALLOWED=NO build` | Passed on dynamically selected iPhone simulator `4B4489C4-295C-4565-9544-30812B4EA0EB`. |
| Signed archive | Not run; blocked by Apple Developer credentials/signing profiles. |

## Simulator Notes

- Explicit `xcodebuild` commands were used with dynamically discovered simulator IDs.
- Dynamic simulator discovery is required in CI and is implemented in `.github/workflows/swift.yml`.

## Blockers

- No signed archive was produced because Apple Developer credentials/signing profiles are not available.
- Simulator testing does not validate physical microphone quality, route changes, Bluetooth/wired input, or real brass-room acoustics.
