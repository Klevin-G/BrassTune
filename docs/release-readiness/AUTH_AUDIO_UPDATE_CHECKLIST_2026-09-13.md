# Native auth and audio update — 13 September 2026

Project attribution: Kelvin Guo, Arya Salem.

## Outcome

Implemented on `arya/auth-audio-reliability-20260913`, based on `d3d2e31`. Changes are local and uncommitted. No update was uploaded or released. The updated development app (`com.aryasalem.BrassTune.dev`, 1.0.1 build 8) is installed and launches on the wired iPhone 15 Pro Max running iOS 26.6.2. The production app was not replaced. Version/build numbers still need to be advanced for an actual update.

The device required the owner to enter its passcode to enable XCTest UI Automation. After approval, tests ran over USB. Pre-test development practice state was backed up locally, restored after testing, and both original state files matched their SHA-256 hashes before normal relaunch. Private backups/recordings/test bundles remain outside Git.

## Fixes

| Reported issue | Change |
| --- | --- |
| Google/Apple sign-in unreliable or appears to do nothing | Provider errors now display even when email/password fields are empty. Cancellation remains cancellation; an empty Apple nonce fails before network transmission. Late profile/avatar responses cannot restore signed-out account UI. Local sign-out clears credentials before its network wait; late refresh cannot recreate them or late logout delete a new login. Duplicate sign-out is blocked. |
| Metronome glitches, wrong tempo, uneven or missing clicks | Removed per-click buffer interruption. First timer wake now uses the future audio anchor, including dense subdivisions. Stale asynchronous pulse requests are rejected. Rapid settings changes coalesce for 60 ms and count-in callbacks check the current run. |
| Tuner beat cues unclear | Added a persistent, high-contrast beat count and measure-progress cue. It follows the emitted beat, handles wrap/subdivisions, exposes an accessibility value, and avoids scaling under Reduce Motion. |
| Drone stops or makes noise when adjusting volume | Same-frequency volume changes retain the oscillator and audio session, preserving phase. A dedicated mixer ramps level over 30 ms instead of stopping/rebuilding the engine on every slider event. |

## Confirmed evidence

| Check | Result | Local evidence |
| --- | --- | --- |
| Native app unit tests in iPhone 17 Pro Simulator, iOS 26.5 | **290 passed, 0 failed, 0 skipped** | `/tmp/BrassTune-urgent-unit.xcresult` |
| Shared Swift domain tests | **12 passed** | `cd swift/BrassTuneCore && swift test` |
| USB: live provider discovery, Apple authorization sheet, Google system consent | **3 passed** | `/tmp/BrassTune-urgent-auth-live.xcresult` |
| USB: repeated metronome tempo changes/drone volume sweeps and Google cancel/retry with empty email fields | **2 passed** | `/tmp/BrassTune-urgent-device-regressions.xcresult` |
| USB: 120 BPM metronome held for 180 seconds and stopped normally | **1 passed** | `/tmp/BrassTune-urgent-metronome-sustained.xcresult` |
| Debug device build and Simulator build/run | Passed | `/tmp/BrassTune-urgent-device-build.log`; XcodeBuildMCP build/run log |
| Signed Release device build | **Passed** | `/tmp/BrassTune-urgent-release-build.log` |
| Localization, design tokens, auth release-configuration regression, whitespace | Passed | Commands below |
| Simulator visual inspection | Beat/progress changed on screen; increased text remained readable | Screenshot path below |

The phone tests exercised **15 tempo-up taps**, **8 drone volume changes**, and **2 Google cancellation/retry cycles**. These assert UI/control survival; the audio synthesis/session tests provide separate implementation coverage.

A supplementary Mac-microphone recording detected **40 clicks over 20 seconds**, with a median timestamped interval of **499.83 ms (~120.04 BPM)**. The host capture lost sample time, so raw WAV sample duration was rejected as a timing reference; analysis used preserved capture packet timestamps. Room acoustics, microphone processing, capture gaps, and unknown physical output volume prevent a calibrated distortion, loudness, or jitter claim. This does not close the listening checks below. Metrics: `/tmp/BrassTune-metronome-acoustic-summary.json`.

Simulator screenshot: `/var/folders/c7/_jc6_hn14psfbfyg5vmlrd380000gp/T/screenshot_optimized_62f8b097-2651-47e6-a0e5-8e3ec7e554fb.jpg`.

Initial UI automation failed before any test ran because the phone awaited its passcode. A subsequent run selected zero physical tests because the `PHYSICAL_RELEASE` compile condition was absent; that zero-test result is not counted. The later correctly compiled runs above executed and passed all selected tests.

## Before releasing the update

Record the candidate version/build, iOS version, output route and result for each row. Repeat these on the actual TestFlight candidate; this session tested a development build and compiled Release, not an uploaded candidate.

| Check | How to do it | Required result |
| --- | --- | --- |
| **1. Google account completion** | From Welcome → Sign in, complete Google with a test account. Repeat from More → Settings → Sign in. Test both first-time and returning users; complete profile setup if required. Force-quit/reopen, sign out/reopen, then sign in again. | Correct account and profile; valid session survives cold relaunch; logout stays logged out; no stuck sheet or spinner. **Actual account completion was not verified in this session.** |
| **2. Apple account completion** | Repeat row 1 with Apple, including Hide My Email if offered. Complete Face ID/passcode on the device. | Same session/profile behavior as Google; returning users are not forced through an unnecessary setup loop. **Actual account completion was not verified in this session.** |
| **3. Provider cancellation and network recovery** | Cancel each provider, then retry. With email/password fields empty, start sign-in offline; restore network and retry. While signed in, retry an unavailable profile and immediately sign out. | Clear recoverable notice, usable retry, no phantom sign-in or required profile screen after logout. Google system cancellation was verified twice; remaining cases need candidate verification. |
| **4. Metronome startup and tempo** | Practice → Metronome. At **40, 60, 120, 200 and 300 BPM**, start/stop 5 times, then listen for 30 seconds. Change tempo rapidly while playing and settle at 120. Also test the minimum 20 BPM and tap tempo. | Starts on the first tap, settles at the displayed tempo, no double clicks, missing beats, unwanted silence or stale tempo. Compare against an independent metronome/click track if available. |
| **5. Beat sound and meter** | At 120 BPM, turn **Accent first beat off** and listen for 1 minute, then enable it. Test subdivisions and a compound meter such as 6/8. Sweep metronome volume. | With accent off, beat level/timbre is consistent. With accent on, only configured group accents differ. No crackling or clipped beats; subdivisions and dotted-quarter compound timing are musically correct. |
| **6. Tuner visual cue** | Set 4/4, subdivisions and count-in in Practice → Metronome; open Tuner and start its floating metronome. Watch at 60, 120 and 200 BPM. Repeat with larger text and iOS Settings → Accessibility → Motion → Reduce Motion. | Beat count/progress stays clear and wraps correctly. Count-in hands off to the measure cleanly. Reduced-motion mode remains understandable without scaling. **Tuner microphone capture intentionally uses a visual-only metronome; silence here is expected.** |
| **7. Drone continuity** | Practice → Drone & intervals (also linked from Tuner). Start the tone; repeatedly drag volume minimum → maximum → minimum, then pause at intermediate values. Change note and test unison, fifth and octave. | Volume changes keep the tone on and alter loudness smoothly; no clicks/crackle/dropouts or overlapping stale tones. The selected note/interval remains correct; Stop silences output immediately. |
| **8. Routes and interruptions** | Repeat sound checks on the built-in speaker and available wired/Bluetooth headphones. During playback, connect/disconnect headphones, invoke Siri or receive a call, background/foreground, and move between Tuner/Metronome/Drone. | No crash, stuck transport or duplicate audio. Route/interruption stop notices are expected; one explicit restart restores correct output. Do not require automatic playback after a route interruption. |
| **9. Candidate identity** | Advance version/build, create the intended archive, install via TestFlight and run the rows above on that exact build. | Candidate contains these fixes; production Google redirect scheme and Apple entitlement/configuration work. Record results before submission. |

Do not mark account completion or acoustic quality passed based solely on unit tests, provider-sheet presentation, the uncalibrated recording, or a successful build. No web/backend, deployment, migration, App Store upload, or production infrastructure changes were required or performed.

## Reproducible checks and changed files

Commands run:

```sh
cd swift/BrassTuneCore && swift test
python3 swift/BrassTuneApp/scripts/verify_design_tokens.py
python3 swift/BrassTuneApp/scripts/verify_localization_coverage.py
sh swift/BrassTuneApp/scripts/test_release_auth_config.sh
git diff --check
```

Native app tests used the `BrassTuneApp` scheme with `-only-testing:BrassTuneAppTests` and iPhone 17 Pro Simulator. Physical UI tests used `BrassTuneAppUISmoke`, the dynamically verified USB UDID, and `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG PHYSICAL_RELEASE'`. Debug/Release builds used the existing Xcode project and signing configuration. Exact invocation lines are retained in the named build logs. A native file hash manifest is at `/tmp/BrassTune-urgent-source-manifest.json`.

Changed app files: `AppModel.swift`, `AppRootView.swift`, `AuthService.swift`, `NativeAudioEngine.swift`, `SettingsViews.swift`, `WelcomeAuthViews.swift`. Changed/added tests: `BrassTuneAppTests.swift`, `BrassTuneAppUITests.swift`, `AuthReliabilityTests.swift`, `AudioReliabilityTests.swift`, `TunerCueTests.swift`. Updated explicit test registration in `project.pbxproj` and both auth preflight scripts. This report is new; previously dirty release-readiness documents were preserved.

## Delegation and independent review

| Lane | Requested route | Reason |
| --- | --- | --- |
| Repository scout | Luna Medium | One shared map of native ownership and test seams |
| Auth implementation | Terra High | Async provider/credential correctness |
| Audio implementation | Terra High | Shared audio ownership and timing races |
| Tuner UI, isolated worktree | Terra Medium | Independent visual change without shared-file conflicts |
| Auth review | Sol High | Independent identity/session race review and regression design |
| Validation/review | Terra Medium | Independent audio/UI review, core tests and static checks |
| Checklist draft | Terra Medium | Independent acceptance checklist while device tests ran |

Effective child model/effort routing was not exposed by runtime metadata and is **unverified**. Children did not spawn grandchildren. The parent integrated changes, ran app/physical builds and tests, visually checked Simulator, captured supplementary acoustic evidence, and inspected final scope.
