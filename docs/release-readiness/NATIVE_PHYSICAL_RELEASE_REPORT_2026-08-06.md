# BrassTune Build-3 Physical and App Store Readiness Report — 2026-08-06

Historical snapshot: build 3 was later rejected and replaced by build 5. See
`APP_REVIEW_RESPONSE_2026-08-14.md` for the newer App Store state.

## 1. Outcome

**SUBMITTED TO APP REVIEW; Waiting for Review, not yet released.**
Build `1.0.0 (3)` was archived, exported, uploaded, processed, assigned to the
internal QA group, selected for App Store version 1.0, and installed on the USB
iPhone through a release-testing export whose unsigned executable is
byte-identical to the uploaded archive executable.

After the owner completed Apple's passcode-protected **Enable UI Automation**
step, the recovery canary passed and an XCTest runner launched the exact
installed production bundle by bundle identifier without replacing it. The
candidate then passed the complete built-in-route audio crash-family matrix
three times: screen recording off, screen recording on with its microphone off,
and screen recording on with its microphone on. Each run exercised 20 Tuner
captures, 20 microphone Scale captures, 20 Metronome cycles, 20 Drone/reference
tone cycles, background/foreground recovery, and 50 rapid cross-feature
switches. A post-run device inventory contained no new BrassTune crash report,
and the exact original signature scan returned zero matches. This closes the
three build-2 crash families for the tested built-in microphone/speaker route
and the original screen-recording conditions.

The owner completed the Digital Services Act declaration in App Store Connect
as a non-trader while retaining EU distribution; App Store Connect reports the
requirement Active for all 27 EU countries/regions. The owner then directed the
release to proceed with the documented P1 validation gaps still open. Build 3
was added to a review submission and submitted to Apple; App Store Connect
reports **Waiting for Review** and says review may take up to 48 hours. The open
gaps remain residual risks, not silently converted to passed evidence.

The shipping archive correctly excludes the `PHYSICAL_INSTRUMENTATION`
self-test seam; binary-string inspection confirms its markers are absent.
Enabling that seam would create a different executable and therefore cannot be
used as a substitute for testing build 3.

## 2. Physical device

- Device: iPhone 15 Pro Max (`iPhone16,2`)
- OS: iOS 26.4.1 (`23E254`)
- Connection: USB/wired; paired, trusted, unlocked, and in Developer Mode
- Xcode: 26.6 (`17F113`)
- Stable device identifiers: retained only in private local evidence

## 3. Build configurations tested

- App Store archive: `com.aryasalem.BrassTune` `1.0.0 (3)`, Release,
  Apple Distribution, archive-time build-number override only.
- Uploaded App Store export: exact r2 archive IPA, accepted and processed by
  App Store Connect.
- Physical install: r2 archive re-exported with the team release-testing/Ad Hoc
  profile for the connected phone. Removing code signatures produces the same
  Mach-O bytes as the App Store archive.
- Supporting earlier device evidence: isolated `.dev` Debug and
  Release-equivalent builds from the same preserved native worktree lineage.
  Those results are supporting source evidence, not build-3 package evidence.

## 4. Tests performed

| Test | Result |
|---|---|
| r2 production archive | Passed; zero errors and zero warnings |
| Strict archive signature and entitlements | Passed; `get-task-allow=false`, `beta-reports-active=true`, Sign in with Apple `Default` |
| Privacy manifest | Passed; UserDefaults `CA92.1` and System Boot Time `35F9.1` |
| App/dSYM UUID match | Passed: `A2BFB5CF-B1A2-36DB-A1FE-2A891C4133A1` |
| App Store export and upload | Passed; exact r2 IPA accepted |
| TestFlight processing | Passed; build 3 is Ready to Submit |
| Internal QA assignment | Passed; build 3 assigned to BrassTune Internal QA |
| App Store version build selection | Passed; build 3 selected for version 1.0 |
| Release-testing executable comparison | Passed; unsigned archive and installed-export Mach-O are byte-identical |
| Physical install and launch | Passed; production bundle reports `1.0.0 (3)` |
| Physical launch stress | `20/20` terminate-and-relaunch operations succeeded |
| Post-launch device crash inventory | Passed for absence of a new report; newest matching retained reports predate this run |
| XCTest automation recovery | Passed; `TestFlightInspect-r7.xcresult` executed `1/1` after the secure device authorization |
| Exact-candidate baseline audio stress | Passed `1/1` in 454.672 seconds: 20 Tuner, 20 microphone Scale, 20 Metronome, 20 Drone/reference tone, background/foreground recovery, and 50 feature switches |
| Exact-candidate screen recording, microphone off | Passed `1/1` in 457.460 seconds with the same full matrix |
| Exact-candidate screen recording, microphone on | Passed `1/1` in 459.360 seconds with the same full matrix under the original discovery condition |
| Exact-candidate sustained A440 display | Passed `1/1`; 40/40 stable samples, 439.9–440.1 Hz, 0 cents, 1,133.4 ms already-present-tone acquisition |
| Exact-candidate sustained 120-BPM Metronome | Three 180-second runs passed `1/1` each; the final maximum-volume run passed in 213.718 test seconds with continuous 48 kHz/24-bit PCM capture |
| Exact-candidate audible-jitter acceptance | Failed closed; the continuous maximum-volume capture resolved only 210/356 expected pulse bins at the lowest threshold and retained 834 extra candidates, so no numerical jitter is claimed |
| Exact-signature scan | Passed; zero matches for the three original assertion/trap signatures in candidate execution logs |
| Final post-matrix device crash inventory | Passed; zero new BrassTune reports since the candidate matrix began |
| Swift domain package postflight | Passed `12/12` |
| Final clean UI-runner source compile | Passed; temporary production-bundle and volume-control bindings are absent from source |
| Prior current-source physical targeted UI/audio | `7/7` passed, including 20 Tuner, 20 microphone Scale, 20 Metronome, 20 reference-tone cycles and 50 switches; not build-3 package closure |
| App Store product metadata | Saved: screenshots, copy, URLs, review notes/contact, guest review, and manual release |
| App privacy disclosure | Published: linked Email Address, User ID, and Other User Content for App Functionality; no tracking |
| Age/content/pricing/availability | Saved: 4+, no third-party content, free, 175 regions, iPhone/iPad storefront scope |
| App Store submission | Passed for this dated snapshot; build 3 was submitted and reported Waiting for Review |

## 5. Evidence paths

Primary private evidence root:

`<user-home>/Library/Application Support/BrassTune/ReleaseEvidence/AppStoreCandidate-2026-08-06-Build3`

Principal artifacts:

- `README.md`
- `BrassTune-1.0.0-3-r2.xcarchive`
- `ArchiveBuild3-r2.xcresult`
- `ExportedAppStore-r2/BrassTuneApp.ipa`
- `ExportedReleaseTesting-r2/BrassTuneApp.ipa`
- `PhysicalLaunchStress/launch-01.json` through `launch-20.json`
- `PhysicalLaunchStress/crash-log-inventory.json`
- `PhysicalLaunchStress/installed-app.json`
- `TestFlightInspect.xcresult`
- `TestFlightInspect-r2.xcresult`
- `TestFlightInspect-r3.xcresult`
- `TestFlightInspect-r7.xcresult`
- `CandidatePhysicalAudioBaseline.xcresult`
- `CandidatePhysicalAudio-ScreenRecordingMicOff.xcresult`
- `CandidatePhysicalAudio-ScreenRecordingMicOn.xcresult`
- `CandidatePhysicalTunerA440.xcresult`
- `CandidatePhysicalTunerA440-attachments/`
- `CandidatePhysicalMetronome120-Max-SoX.xcresult`
- `CandidatePhysicalMetronome120-Max-SoX.wav`
- `CandidatePhysicalMetronome120-Max-SoX-verdict.txt`
- `PhysicalCandidate-original-signature-scan-clean.txt`
- `PhysicalCandidateCrashLogs-final-post-jitter.json`
- `PhysicalCandidateCrashLogs-final-post-jitter-summary.txt`
- `PhysicalCandidateInstalledApp-final.json`
- `PhysicalCandidateInstalledApp-post-matrix.json`
- `PhysicalCandidateInstalledApp-final-post-jitter.json`
- `SwiftCore-final-post-matrix.log`
- `CandidatePhysicalRunner-final-source-clean-build.log`
- `PhysicalCandidate-final-test-summaries.tsv`
- `PhysicalCandidate-final-manifest.sha256`

Artifact identities:

- App Store IPA SHA-256:
  `995eac30b0be666e1768c4de0fee081e33f35208ff005beb8b3991d02ce19076`
- Archive app binary SHA-256:
  `85f057e04f803d6bd5c568a3b563c8bc9cfd14a10879138b73f0b12647fd4408`
- Native content-tree SHA-256:
  `7aaf3d6cc418926580a986d490a21847111ce66813b461d3517970c4deb32f68`
- Native diff SHA-256 relative to HEAD:
  `607bdbe03b15f3a40f1af871210a96d0927e5207f18e7aee52a9be5559a5e47b`

## 6. Original crash-family status

- A — `NativeMetronomeOutput.playTick` / `ScheduleBuffer` SIGABRT:
  **Closed for build 3 on the built-in speaker route.** All three exact-candidate
  matrices completed 20 Metronome cycles plus the cross-feature sequence, with
  no matching log signature or new BrassTune crash report.
- B — live input-tap frame delivery / `dispatch_assert_queue` SIGTRAP:
  **Closed for build 3 on the built-in microphone route.** All three matrices
  completed 20 Tuner and 20 microphone Scale captures plus cross-feature
  switching, with no matching log signature or new BrassTune report.
- C — `configureAndStartLiveEngine` / `InstallTapOnNode` SIGABRT:
  **Closed for build 3 on the built-in microphone route.** Repeated capture
  installation/teardown completed under all three recording conditions, with
  no matching log signature or new BrassTune report.

Bluetooth HFP input and wired input remain untested route classes. No closure
is inferred for unavailable hardware.

## 7. Tuner accuracy and latency

The exact installed build-3 candidate was tested with a continuous digitally
generated 440 Hz sine from the Mac speaker into the phone microphone. It
displayed written B4 for 40/40 half-second samples, 439.9–440.1 Hz, and 0 cents.
Already-present-tone to stable-display acquisition was 1,133.4 ms. This is not
source-onset latency and was not independently calibrated.

Earlier low/middle/high consumer-sine observations remain D4 at 261.6 Hz, B4 at
440.0 Hz, and A5 at 784.0 Hz. No real-brass or absolute calibrated accuracy
claim is made.

## 8. Metronome jitter

The exact build-3 candidate completed three additional 180-second 120-BPM runs
without a crash. The first AVFoundation capture again delivered only 169.08
seconds of samples over 214 seconds of wall time and was rejected. A CoreAudio
SoX workaround then produced continuous 48 kHz/24-bit PCM, including a final
219.52-second maximum-volume capture bound to a `213.718`-second passing XCTest.

The uninterrupted clock fixed the packet-gap defect, but the physical acoustic
signal remained too close to room noise: at the lowest detector threshold only
210 of 356 expected pulse bins were resolved, with 146 missing bins and 834
extra candidates. That coverage is not sufficient for a defensible jitter
statistic, so the analyzer fails closed and no numerical jitter result is
reported. The sustained-output/no-crash result is accepted; audible timing
quality remains P1.

## 9. Routes, interruptions, and screen recording

- Build 3: install, foreground launch, and 20 relaunch cycles passed.
- Built-in microphone/speaker: exact-candidate repeated-cycle and 50-switch
  stress passed three times; exact-candidate sustained A440 also passed.
- Screen recording off, on without narration microphone, and on with narration
  microphone: the exact candidate passed the complete matrix in all three
  conditions. Control Center preparation and stop tests also passed.
- Media-services reset: passed earlier against the same repaired source in the
  isolated `.dev` bundle; it was not destructively repeated against build 3.
- AirPlay: prior instrumented route-selection survival only; audible production
  route remains open.
- Bluetooth HFP/A2DP and wired accessories: unavailable and untested.

## 10. CPU, memory, energy, and hangs

Build 3 received the three long-running audio stress matrices and sustained
A440 UI sampling, but not a new accepted Instruments measurement. No XCTest
hang or app crash occurred. The
preserved Release-equivalent current-source observation remains mean CPU
14.744%, p95 33.073%, peak 40.163%; real memory 60.875–67.953 MiB; peak 18
threads; Nominal thermal state; warm foreground launches 643.064/507.547 ms;
and zero >=250 ms potential hangs. It is one device and workload, not a
population result or final TestFlight-thinned measurement.

## 11. Files, Photos, and accessibility

Prior physical Photos PNG and iCloud Files PNG journeys passed import,
persistence, and confirmed local deletion without changing provider originals.
Focused current-source simulator journeys passed score action cleanup, guided
all-notes practice, three-octave visual practice, and the Practice-tab reset.
Those journeys were not repeated on build 3; they remain P1 acceptance gaps,
not evidence against the now-closed audio crash families.

VoiceOver is owner-reported passed. Physical maximum Dynamic Type/RTL and
simulator Increase Contrast, Reduce Motion, Light/Dark, iPhone orientation, and
iPad navigation/orientation evidence remain preserved. App Store accessibility
nutrition labels were left undeclared because the exact build-3 candidate did
not receive the full Apple-criteria evaluation.

## 12. Source changes in this pass

- `PrivacyInfo.xcprivacy`: added
  `NSPrivacyAccessedAPICategorySystemBootTime` reason `35F9.1` for shipping use
  of monotonic elapsed-time APIs; retained UserDefaults reason `CA92.1`.
- Project build number was not edited; build `3` was supplied only as an
  archive-time setting override.
- Temporary UI-test bindings that targeted the installed production bundle were
  compiled into the external runner, used only for the exact-candidate matrix,
  and removed after evidence capture; they leave no final source change.
- `NATIVE_MASTER_ISSUE_REGISTER.md`, `TEST_MATRIX.md`, and this report were
  updated with build-3 evidence and release boundaries.
- SoX was installed through Homebrew as a local QA-only CoreAudio recorder after
  AVFoundation again produced discontinuous acoustic samples. No package or
  generated audio file was added to the repository.

The large pre-existing dirty worktree was preserved. No reset, clean, stash,
rebase, discard, commit, push, or history rewrite occurred.

## 13. Remaining issues

- P0: none remaining for the three original build-2 audio crash families on the
  tested built-in route and screen-recording conditions. The separate production
  private-audio owner/delete/cross-user acceptance item remains open in the
  web/backend lane and was not mutated during this native-only pass.
- P1: exact-candidate Bluetooth/wired/AirPlay acceptance where hardware is
  available; calibrated source-onset latency and metronome jitter; accepted
  Instruments performance; Files/Photos, full accessibility, and
  provider-lifecycle acceptance; dirty uncommitted source binding.
- P2: broader device-family/accessory coverage, physical iPad usability,
  Voice Control, alert-focus restoration, and additional import/share formats.

## 14. External systems

App Store Connect was intentionally mutated: build 3 was uploaded, processed,
assigned to internal QA, selected for version 1.0, and the prepared metadata,
screenshots, privacy, age-rating, content-rights, price, availability, and
review fields were saved. The privacy disclosure was published. On 2026-08-06,
the owner confirmed the DSA non-trader declaration with EU distribution; the
Business compliance page reports Digital Services Act Active for 27 countries
or regions and says all current regulatory requirements are complete.

Supabase, Render, Vercel, the production database, Storage, Auth provider
configuration, redirect policy, and backend deployment were not mutated in this
pass.

## 15. Release restriction confirmation

Build 3 was uploaded under the owner's later explicit release-readiness
authorization, superseding the earlier no-build-3 instruction. On 2026-08-06,
the owner directed the release to proceed and build 3 was submitted to App
Review. It is **Waiting for Review** and is not released. Manual release remains
selected. No `Release/BrassTune-v1.0/` folder, release tag, commit, or push was
created. Build 2 remains preserved in App Store Connect as diagnostic evidence.

## 16. Exact next owner action

Monitor App Store Connect for Apple's review decision. If approved and the app
enters Pending Developer Release, use the configured manual-release control to
release version 1.0; if rejected, preserve the exact review message before any
new build or metadata change.
