# Focused metronome, smooth drone, and guest sign-in follow-up

Project attribution: Kelvin Guo, Arya Salem.

This report supersedes the first-pass audio/UI conclusions in `AUTH_AUDIO_UPDATE_CHECKLIST_2026-09-13.md` for the September 13 follow-up. Work remains local on `arya/auth-audio-reliability-20260913`; no commit, push, upload, or release was performed.

## Implemented

- **Click sound:** shortened, shaped PCM with zero-ended attack/release and peak headroom at or below 0.34. At dense subdivisions the clip is capped to half the active interval, avoiding the previous overlapping 36–48 ms tails. Tempo-dependent buffers update without stopping a same-format audio graph.
- **Focused metronome:** a large central pulse sphere and bottom tempo/start-stop/tap controls; rhythm, sound, precise one-BPM adjustment, and presets are in the Settings sheet. Text scales with Dynamic Type; Reduce Motion avoids sphere scaling. Accessibility groups retain separately addressable controls and readouts.
- **Optional tuner center:** starts passive microphone capture before joining audible metronome output. The sphere displays a stable note, cents, and tuning verdict. Saved takes/play-along retain their existing independent capture policy. Turning the mode off or leaving it releases its microphone ownership; permission cancellation preserves an already-running beat.
- **Click rejection:** original capture start/end host times travel alongside, not inside, persisted pitch frames. The readout rejects capture intervals overlapping scheduled clicks, requires two consistent clean frames, expires held readings, and rejects stale capture delivery and invalid host clocks. This is a conservative readout filter, not calibrated echo cancellation; dense subdivisions and room/accessory conditions may leave the tuner waiting for clean input.
- **Drone retuning:** old and new oscillator sources crossfade over 24 ms without resetting the session. Volume retains its separate gain ramp. Latest requested pitch is tracked independently from completed pitch so A→B→A changes cannot finish at stale B. Failed transitions preserve a truthful recovery state and notice.
- **Guest sign-in:** Settings, Classes and the gateway use one dedicated decision view with Merge, Keep separate, and Cancel. Other provider/email/settings controls are absent from the decision surface. Merge remains visible but disabled with an explanation where existing file-backed-data safety restrictions apply. Choice errors are visible. Cancel dismisses and clears pending Class navigation. Accepting the decision resumes any required account setup; the profile sheet cannot cover a pending guest decision.

## Verification

| Evidence | Result |
| --- | --- |
| Native app unit tests | **302 passed, 0 failed/skipped** — `/tmp/BrassTune-focus-unit-complete.xcresult` |
| Simulator: Settings/Classes/gateway decision-only screens, focused metronome, settings and repeated transport controls | **5 passed** — `/tmp/BrassTune-focus-ui-complete.xcresult` |
| Simulator: accepting Keep separate hands off to required profile setup | **1 passed** — `/tmp/BrassTune-focus-auth-acceptance.xcresult` |
| USB iPhone 15 Pro Max, iOS 26.6.2: audible-mode metronome plus microphone A440 reference, tuner off/on ownership and six drone pitch changes | **1 passed** — `/tmp/BrassTune-focus-device-v6.xcresult` |
| Simulator/device Debug builds | Passed; normal install build log `/tmp/BrassTune-focus-normal-final.log` |
| Signed Release build | **Passed**; log `/tmp/BrassTune-focus-release-final.log` |
| Localization and design checks, auth preflight, whitespace | Passed |

The physical test ran the metronome at 120 BPM and read a real Mac-speaker A440 reference as written **B4, 0 cents, in tune** for B-flat trumpet. The screenshot is `/tmp/BrassTune-focus-device-v6-attachments/ACED065B-122E-415F-BE0F-D41BCFE6B86F.png`. The test verifies this specific duplex display and transport/retune behavior, not calibrated distortion, latency, speaker/headphone equivalence, or universal click-bleed rejection.

The first command of this follow-up requested physical XCTest automation. iOS reused the existing approval and ran a provider-discovery test; no new passcode prompt was required. Earlier iteration failures included accessibility grouping/selector issues, a combined-mode startup notification race, and missing localized error copy; those were corrected before the passing receipts above. The physical tuner switch must target its native child control in XCTest, rather than tapping the empty center of its accessibility row.

Auth UI tests use an explicitly gated development fixture for the pending guest decision. Unit tests exercise actual model merge/separate/cancel transitions and credential/namespace behavior with controlled networking. These do **not** constitute real Google/Apple account authorization receipts. Previously completed provider-sheet probes remain entry-point evidence only.

## Before releasing the update

Use the actual next TestFlight version/build and record outcomes, iOS version, and audio route. The installed development build retains the existing version/build numbering; increment it for a real update.

| Check | Steps and pass condition |
| --- | --- |
| **Settings sign-in** | Create some guest practice, then More → Settings → Apple/Google. Complete each real provider login. The next page must show only the guest decision. Try Merge and Keep separate; each must finish in the intended account and offer required setup when necessary. Force-quit/reopen and confirm the account remains correct. |
| **Classes sign-in and cancellation** | As a guest, open Classes and sign in. Check the same decision-only page. Cancel must return to guest practice; a later Settings sign-in must not unexpectedly jump to Classes. Finish the other choices and confirm class access after required setup. |
| **Clear click sound** | Practice → Metronome. With accents off, listen at 40, 60, 120, 200 and 300 BPM for 30 seconds each. Start/stop repeatedly and change tempo rapidly. Beats should be distinct, evenly spaced and free of crackle/dropouts. Then enable accents and subdivisions; only intentional accents should differ. Include low and high device volume. |
| **Large sphere and rhythm** | Check the central beat count, wraparound, count-in, quarter/subdivided/compound meters, bottom controls and Settings sheet. Repeat with larger text and iOS Reduce Motion. The primary pulse/readout and controls must remain readable/reachable. |
| **Metronome plus tuner** | Turn Tuner on and play sustained low/middle/high notes while the beat runs. Check note, cents and verdict in the sphere. Stop playing: clicks alone should not establish a note. Start with quarter beats; use headphones or a slower/less dense beat if clean frames are unavailable. Turn Tuner off while playing and verify the metronome continues; leave the combined screen and confirm microphone capture stops. |
| **Drone pitch and volume** | Start Drone & intervals, sweep volume, move notes repeatedly, rapidly go A→B→A, and change unison/fifth/octave. Listen specifically at transition boundaries: no pop, crackle, unexpected silence, or stale final pitch. Stop must silence the drone. |
| **Routes and interruptions** | Repeat listening checks on built-in speaker and available wired/Bluetooth routes. Test Siri/call interruptions, background/foreground and switching tools. A clear stopped/restart state is acceptable; stuck controls, doubled streams, wrong final pitch, or hidden recording are not. |

Real account completion and cross-route listening remain candidate acceptance checks. No web/backend deployment, migration, App Store upload, or production app replacement was performed.

## Changed areas and reproducibility

App sources: `AppModel.swift`, `AppRootView.swift`, `NativeAudioEngine.swift`, `PracticeFeatures.swift`, `SettingsViews.swift`, `WelcomeAuthViews.swift`. Tests: `AudioReliabilityTests.swift`, `BrassTuneAppTests.swift`, `BrassTuneAppUITests.swift`; existing first-pass test registration is retained. The design-token verifier now checks the focused sphere and semantic bottom-dock typography rather than the removed large BPM card. This report is new; unrelated pre-existing documentation edits were preserved.

Commands: `xcodebuild` with `BrassTuneApp` for Debug/Release and unit tests; `BrassTuneAppUISmoke` for UI tests. Physical tests use the verified USB device and `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG PHYSICAL_RELEASE`; normal installed development builds do not enable that physical-test condition. Also ran `verify_localization_coverage.py`, `verify_design_tokens.py`, `test_release_auth_config.sh`, and `git diff --check`. Exact invocations and intermediate failures are retained in the named logs/result bundles.

The phone's development practice state and Documents were backed up to `/tmp/BrassTune-focus-before-tests` before destructive test-fixture resets; state is restored before the normal app relaunch. Keychain persistence was disabled for the physical fixture runs. Generated audio, screenshots, backups and result bundles remain outside Git.

## Delegation

Audio and auth implementation: requested Terra High. Focused UI in an isolated worktree: Terra Medium. Duplex architecture and auth review: Sol High. Independent final result/diff verification: Terra Medium. Existing agents were reused with disjoint ownership; no grandchildren. Effective model/effort routing was not exposed by runtime metadata and remains unverified. The independent validator confirmed the 302/5/1 result counts directly from the result bundles; the additional acceptance UI test passed afterward.
