# BrassTune Native Physical Release Report — 2026-08-05

## 1. Outcome

**BLOCKED for App Store release.** The current native worktree has enough
evidence to enter internal-candidate preparation once its intended source is
reconciled and bound to an exact commit. The next internal candidate and App
Store submission are separate gates: a signed candidate must exist before its
exact installed behavior can receive final physical acceptance.

The three TestFlight build-2 crash families remain closed for the exercised
built-in microphone/speaker route. A real media-services reset also passed.
The AirPlay runs are retained as instrumented route-selection survival tests,
not as audible production-route proof.

## 2. Physical device

- Device: iPhone 15 Pro Max (`iPhone16,2`)
- OS: iOS 26.4.1 (`23E254`)
- Connection: USB/wired; paired, trusted, unlocked, and in Developer Mode
- Xcode: 26.6 (`17F113`)
- Stable device identifiers: retained only in private local evidence

## 3. Build configurations tested

- Physical functional/instrumentation: signed Debug
  `com.aryasalem.BrassTune.dev` `1.0.0 (2)`, compiled with the
  `PHYSICAL_RELEASE` UI-test condition.
- Production distribution check: a fresh no-install Release build of
  `com.aryasalem.BrassTune` `1.0.0 (2)` was distribution-signed before the
  compile-gated route-picker test seam was added.
- Later normal-source compile: generic-device Release, code signing disabled,
  no `PHYSICAL_RELEASE` condition. It is an unsigned compile, not a candidate,
  archive, install, export, or upload.
- Simulator substitutes: iPhone 17 Pro and iPad Pro 13-inch (M5), iOS 26.5.
- Production TestFlight build 2 remained separately installed and untouched.

## 4. Tests performed

| Test | Result |
|---|---|
| Swift Core | `12/12` passed |
| Simulator native units | `240/240` passed |
| Preserved simulator native UI | `22/22` passed |
| Localization | 844 static keys; zero automated failures |
| Physical targeted UI | `6/6` passed in 648.783 seconds |
| Physical audio cycles | 20 each for Tuner, microphone Scale, Metronome, reference tone, and Drone; passed |
| Physical cross-feature stress | 50 switches plus background/foreground; passed |
| Real media-services reset | `1/1` passed in 53.665 seconds |
| Instrumented AirPlay route-selection survival | Reference tone `1/1` in 81.858 seconds; Metronome `1/1` in 92.685 seconds |
| Sustained physical Metronome | `1/1` passed in 210.067 seconds; no crash |
| Sustained physical A440 display stability | `1/1` passed in 49.796 seconds; 40/40 stable samples |
| Simulator Increase Contrast + accessibility XXXL + RTL/strict audit | `2/2` passed |
| Simulator iPhone orientation regression | `1/1` passed after a landscape-coordinate harness repair |
| Simulator iPad current-source navigation + orientation | `2/2` passed |
| Simulator system Reduce Motion warm-up + Metronome flows | `2/2` passed |
| Focused Files/Photos/persistence model tests | `9/9` passed; the separate simulator UI journey was infrastructure-interrupted and is not counted |
| Current-source focused native journeys | `5/5` passed in 156.8 seconds: More routes, score viewer/actions, guided all-notes score practice, three-octave visual timing, and Drone -> Progress -> Practice reset |
| Production Release build/signing | Passed without archive, install, export, or upload |
| Later normal Release compile | Passed; unsigned and not exact-candidate evidence |

The initial orientation regression correctly exposed that app-level XCTest
swipes follow device coordinates in landscape. The app remained scrollable;
the harness now drives the actual destination ScrollView and passes on both
iPhone and iPad simulators.

## 5. Evidence paths

Evidence root:

`<user-home>/Library/Application Support/BrassTune/ReleaseEvidence/NativeIOSContinuation-2026-08-05`

Principal results:

- `PhysicalTargetedUI-r3.xcresult`
- `PhysicalPostSpringBoardRecovery.xcresult`
- `PhysicalMediaServicesReset.xcresult`
- `PhysicalActiveReferenceToneAirPlayRoundTrip-r10.xcresult`
- `PhysicalActiveMetronomeAirPlayRoundTrip-r11.xcresult`
- `ProductionReleaseBuild.xcresult`
- `ProductionReleaseCompile-final-source.xcresult`
- `SimulatorUnit.xcresult`
- `SimulatorUI.xcresult`
- `MacIPhoneWorkarounds/PhysicalMetronomeSustained120BPM-r2.xcresult`
- `MacIPhoneWorkarounds/metronome-120-iphone-speaker-mac-mic-r2.nut`
- `MacIPhoneWorkarounds/PhysicalTunerSustainedA440DisplayStability.xcresult`
- `MacIPhoneWorkarounds/PhysicalTunerSustainedA440DisplayStability-attachments/`
- `MacIPhoneWorkarounds/SimulatorAccessibilityIncreasedContrastXXXL.xcresult`
- `MacIPhoneWorkarounds/SimulatorOrientation-iPhone17Pro-r3.xcresult`
- `MacIPhoneWorkarounds/SimulatorCurrentSource-iPadPro13.xcresult`
- `MacIPhoneWorkarounds/SimulatorSystemReduceMotionFlows.xcresult`
- `MacIPhoneWorkarounds/SimulatorCurrentSourceFocusedNativeJourneys.xcresult`
- `MacIPhoneWorkarounds/CurrentSource-PracticeHome.jpg`
- `MacIPhoneWorkarounds/CurrentSource-More.jpg`
- `MacIPhoneWorkarounds/CurrentSource-SettingsAuthProviders.jpg`
- `MacIPhoneWorkarounds/CurrentSource-ThreeOctaveTubaD.jpg`
- `MacIPhoneWorkarounds/CurrentSource-ThreeOctaveVisualPracticePaused.jpg`

## 6. Original crash-family status

- A — `NativeMetronomeOutput.playTick` / `ScheduleBuffer` SIGABRT:
  **Closed for the built-in speaker route.** Repeated cycles, 50 switches,
  media reset, and the new 180-second sustained run completed without an
  equivalent report. The AirPlay seam is corroborating survival evidence only.
- B — live input-tap frame delivery / `dispatch_assert_queue` SIGTRAP:
  **Closed for the built-in microphone route.** Repeated capture, stress, and
  real media reset passed without stale publication or an equivalent report.
- C — `configureAndStartLiveEngine` / `InstallTapOnNode` SIGABRT:
  **Closed for the built-in microphone route.** Repeated Tuner/Scale capture,
  permission recovery, stress, and media reset passed without an equivalent
  report.

Bluetooth HFP input and wired input remain separate untested route classes; no
closure is inferred for unavailable hardware.

## 7. Tuner accuracy and latency

The new sustained A440 run used a continuous digitally generated 440 Hz sine
through the Mac built-in speaker into the USB iPhone's built-in microphone.
The B-flat trumpet profile displayed written B4 for 40/40 half-second samples.
Observed frequency was 439.9–440.2 Hz and displayed cents were -1 to +2. The
steady-source-to-stable-display acquisition was 1,143.1 ms.

This is strong functional stability for one phone, source, room, level, and
geometry. The source existed before measurement, so 1,143.1 ms is not
source-onset latency. The Mac speaker, room, distance, iPhone processing, and
clocks were not independently calibrated; no absolute calibrated accuracy,
real-brass result, or professional-instrument claim is made.

Earlier low/middle/high consumer-sine observations remain D4 at 261.6 Hz, B4
at 440.0 Hz, and A5 at 784.0 Hz. They share the same limitation.

## 8. Metronome jitter

The USB iPhone completed a new 180-second 120-BPM built-in-speaker run while
the Mac built-in microphone recorded raw 48 kHz, 24-bit mono NUT audio. The app
test passed with no crash, and the capture contains audible 1,320 Hz click
energy.

The raw stream contains 190.586667 seconds of samples across a 230.000-second
timestamp span: 3,691 positive packet gaps totaling 39.412040 seconds, including
34.238878 seconds in the broad test window. A timeline-corrected WAV is retained
for listening/exploration only. Without a separate pilot, packet-complete click
channel, calibration runs, and scheduler/signpost binding, no audible-jitter
number is valid or accepted. The timing gate remains open.

## 9. Routes, interruptions, and screen recording

- Built-in microphone/speaker: repeated-cycle, stress, media-reset, sustained
  A440, and sustained Metronome runs passed.
- AirPlay: a `PHYSICAL_RELEASE`-only route picker and scene-lifecycle exception
  kept an instrumented Debug `.dev` graph alive through Speaker -> HomePod ->
  Speaker selection. UI/audio-owner controls remained responsive and no matching
  crash report appeared. The tests did not independently verify audible HomePod
  output, app-observed `AVAudioSession.currentRoute`, or normal Release scene
  handling. AirPlay production-route acceptance therefore remains open.
- System-timer interruption/recovery: prior physical pass.
- Screen recording off, on with narration microphone off, and on with narration
  microphone enabled: prior physical passes matching the build-2 conditions.
- Bluetooth HFP/A2DP and wired accessories: unavailable and untested. Mac/iPhone
  playback cannot emulate their route, codec, or session behavior.

## 10. CPU, memory, energy, and hangs

No new performance claim was derived from these Debug workaround tests. The
preserved Release-equivalent observation remains: mean CPU 14.744%, p95
33.073%, peak 40.163%; real memory 60.875–67.953 MiB; peak 18 threads; Nominal
thermal state; warm foreground launches 643.064/507.547 ms; and zero >=250 ms
potential hangs in the later bound Time Profiler run. This is one workload on
one phone, not a population result or final-archive measurement.

## 11. Files, Photos, and accessibility

Earlier real physical Photos PNG and iCloud Files PNG journeys passed import,
local persistence across relaunch, and confirmed local deletion without
altering provider originals; Photos also passed delete-cancel. Focused model
tests additionally passed deterministic export, rename/persistence,
delete/relaunch, failed-photo cleanup, PNG/JPEG preservation, restore, and
truthful manual guided-session persistence. Real PDF/JPEG/HEIC picker import,
Share Sheet delivery, export destination, corruption recovery, and additional
providers remain open.

A fresh current-source simulator replacement for the previously interrupted
broad journey passed `5/5` in 156.8 seconds. It verified the uncluttered score
action menu and delete-cancel behavior, the explicit all-notes guided-practice
entry and active manual timer, useful More routes, a playable Tuba D-major
three-octave visual-timing sequence, and the Drone -> Progress -> Practice-home
reset. Computer Use independently repeated the last navigation path against the
rendered simulator UI. These checks do not replace the real picker/provider and
Share Sheet gates above.

VoiceOver is owner-reported passed. On simulator, Increase Contrast plus
accessibility XXXL/RTL and strict Light/Dark structure passed `2/2`; system
Reduce Motion warm-up/Metronome flows passed `2/2`; current-source iPhone
orientation passed `1/1`; and iPad navigation/orientation passed `2/2`.
Simulator substitutes do not close physical Voice Control, system-setting
perception, alert-focus restoration, physical iPad, or uncoached usability.

## 12. Source changes in this continuation

- `BrassTuneAppUITests.swift`: added physical-only media-services reset,
  route-selection, sustained Metronome, and sustained A440 regressions; added a
  current-source orientation regression and landscape ScrollView harness.
- `AppRootView.swift`: earlier in this continuation, added a
  `PHYSICAL_RELEASE`-only route-picker/lifecycle seam. It is compiled out of
  normal candidate builds.
- `NATIVE_MASTER_ISSUE_REGISTER.md`, `TEST_MATRIX.md`, and this report: updated
  evidence and release boundaries.

No shipping app behavior was changed in this final workaround segment; its new
Swift edits are UI-test target code only.

## 13. Remaining issues

- P0: none of the three preserved build-2 crash families remains open for the
  exercised built-in route.
- P1: exact committed candidate binding; signed candidate install/retest;
  Bluetooth HFP/A2DP; wired input/output; audible production AirPlay proof;
  calibrated real-brass tuner accuracy/latency; accepted audible Metronome
  jitter; remaining real Files/Photos/share flows; physical Voice Control,
  system-setting, iPad, alert-focus, and usability checks; legal/privacy and
  App Store metadata.
- P2: SpringBoard/XCTest detachment crash with successful recovery; additional
  warm-up/accessibility breadth; environment/tooling instability during one
  simulator UI journey.

Unavailable hardware gates may be explicitly waived as accepted residual risk;
they must not be renamed as passed.

## 14. External systems

Supabase, Render, Vercel, Apple Developer, and App Store Connect were not
accessed or mutated in this native-only continuation.

## 15. Release restriction confirmation

No build was uploaded. No build 3, archive, export, release tag, commit, push,
or `Release/BrassTune-v1.0/` folder was created. Production TestFlight build 2
was not replaced or uninstalled.

## 16. Exact next owner action

Create a clean internal-candidate worktree from current `origin/main`, apply
only the intended native changes, and record the resulting commit SHA before
signing the next unused internal build.
