# Release Test Matrix

Updated: 2026-07-10

Current native boundary: the redesigned Swift source now implements the four-tab Play-Along/Tuner/Progress/Settings app, live-microphone-only shipping behavior, UI-test-only fixtures, audible metronome defaults, adaptive light/dark surfaces, and scoped iOS 26 Liquid Glass. `BrassTuneCore` executed successfully (`3/3`), and the native design check passed. The `35` app unit tests and `2` UI tests were source/typecheck-validated but were **not executed** here because the sandbox blocks `xcodebuild`/CoreSimulator. No current simulator build or test pass is claimed.

## Native Swift Local Gates

| Gate | Command or evidence | Result | Notes |
|---|---|---|---|
| BrassTuneCore Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3/3` Swift Testing tests | Pitch math, transposition, and confidence semantics executed locally. |
| Native design tokens and glass scope | `python3 swift/BrassTuneApp/scripts/verify_design_tokens.py` | Passed | Verified `15` adaptive Swift theme colors, `3` shared brand anchors, and the centralized glass fallback. |
| Four-tab information architecture | Source/typecheck validation of `AppRootView.swift` | Validated; not simulator-executed | The only tabs are Play-Along, Tuner, Progress, and Settings. Home, Practice, Analytics, Coach, and More are removed from the tab bar. |
| Native app unit tests | `BrassTuneAppTests/BrassTuneAppTests.swift` test inventory | `35` tests source/typecheck-validated; not executed | Includes live-only shipping defaults, fixture guards/quarantine, audible metronome migration, Play-Along grading, persistence, score cleanup, analytics, transposition, and native pitch detector cases. `xcodebuild test` could not run in this sandbox. |
| Native UI test suite | `BrassTuneAppUITests/BrassTuneAppUITests.swift` test inventory | `2` tests compiled/source-validated; not executed | Covers beginner onboarding plus the four-tab, Play-Along, Tuner, Progress, Settings, advanced A4, legal, metronome, fixture isolation, and destructive-alert journey. CoreSimulator launch is unavailable in this sandbox. |
| Play-Along live grader | Source/typecheck validation plus unexecuted unit/UI coverage | Implemented; device execution unverified | Uses `NativeAudioEngine` pitch frames, written-pitch-class matching, sustained holds, median cents, per-note ratings, percentage, and stars. Normal launches use the real microphone; deterministic frames require a UI-test launch flag. |
| Real-microphone shipping boundary | Source audit of `NativeTestFixtures`, `PracticeSessionSource.allCases`, `NativeAudioEngine`, and restore filtering | Implemented; physical validation blocked | Normal launches expose only `.live`; sample recording/score/ensemble fixtures require `UITEST_FIXTURES` or legacy `UITEST_DEMO`. Legacy sample persistence is filtered from normal restores. |
| Metronome defaults | Source/typecheck validation plus unexecuted unit coverage | Implemented | Defaults are sound on, not visual-only, volume `0.6`; effective output is muted only during an active live recording. |
| Adaptive design / Liquid Glass | Source audit plus design verification script | Implemented; visual device QA pending | System light/dark appearance is respected. Content uses solid adaptive surfaces. Custom glass is centralized and limited to floating transports, primary Start/Record actions, and the score viewer top controls, with iOS 17–25 fallbacks. |
| iPhone/iPad Debug and Release simulator builds | `xcodebuild ... -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build` | Not executed / blocked | `xcodebuild` and CoreSimulator services are unavailable under the current sandbox. Previous simulator evidence does not validate this redesign. |
| Physical iPhone/iPad validation | `xcrun devicectl list devices` / `xcrun xctrace list devices` | Blocked | No authorized physical-device run was available. Microphone, real brass input, route changes, interruptions, haptics, Files/Photos, thermals, timing, and speaker/headphone bleed remain unverified. |
| Apple signing/archive/TestFlight | Xcode project/signing audit | Blocked | The bundle ID remains development-scoped, `DEVELOPMENT_TEAM` is empty, project signing is disabled, and no App Store Connect/TestFlight authorization was available. |
| Diff hygiene | `git diff --check -- docs/release-readiness/NATIVE_PARITY_SURFACES.md docs/release-readiness/TEST_MATRIX.md docs/release-readiness/APP_STORE_CHECKLIST.md` | Passed | No whitespace errors in the native documentation update. |

## Required Unrestricted-Xcode Rerun

Discover simulator identifiers with `xcrun simctl list devices available`, then run all of the following on the same working-tree revision:

- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests`

Do not convert source/typecheck validation into a simulator-pass claim until those commands execute successfully on the current revision.

## Web Production Gates

These rows are retained as historical evidence only. They were not rerun for this native redesign and do not validate the current native working tree.

| Gate | Historical result | Notes |
|---|---|---|
| Backend full suite | Passed: `77 passed` | Historical web evidence; warnings were existing datetime/TestClient deprecations. |
| Backend hardening | Passed: `61 passed` | Historical authorization, payload, header, account, and ensemble coverage. |
| Backend Bandit | Passed | Historical source scan. |
| Backend dependency audit | Passed via clean `uv` Python 3.12 fallback | Historical; the direct resolver environment had failed before the fallback. |
| Frontend unit tests | Passed: `9` files, `40` tests | Historical web evidence. |
| Frontend build/typecheck | Passed | Historical Vite production build. |
| Frontend production dependency audit | Passed: `0 vulnerabilities` | Historical web evidence. |
| Local E2E/accessibility | Passed: `80 passed` | Historical browser/device matrix. |
| Hosted production smoke | Passed: `7/7` | Historical hosted evidence; not a native-app gate. |

## Remaining External Gates

| Gate | Status | Reason |
|---|---|---|
| Native simulator execution on current redesign | Blocked in this environment | Requires unrestricted `xcodebuild` and CoreSimulator access. |
| Native physical-device validation | Blocked | Requires a real iPhone/iPad and live brass input for microphone quality, acoustics, route/interruption behavior, haptics, timing, bleed, Files/Photos, performance, and accessibility checks. |
| Live Supabase/account lifecycle | Owner-gated | Requires production native configuration and disposable provider users; no provider behavior is inferred from local guest mode. |
| Google/Apple provider lifecycle | Owner-gated | Provider configuration, redirects, entitlements, and disposable users are external. |
| Signed archive/TestFlight/App Store | External | Requires Apple Team/signing assets, App Store Connect authorization, a successful archive/export/upload, TestFlight validation, approved metadata, and App Review. |
| Camera score capture | Future native feature | Camera import remains absent and no camera permission is declared until a real flow is implemented and device-tested. |
