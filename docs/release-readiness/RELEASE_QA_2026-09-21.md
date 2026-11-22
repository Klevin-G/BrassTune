# BrassTune 1.0.3 release QA — September 21–22, 2026

Project attribution: Kelvin Guo, Arya Salem.

## Release status

Final candidate: **1.0.3 (11)**. Signed archive/export and Apple upload succeeded.
Apple processing completed; Safari confirmed **1 Item Submitted** and
**1.0.3 Waiting for Review**. Automatic release after approval is saved.
This update is submitted, not yet publicly released.

The App Store Connect receipt is stored with the owner’s release evidence.

Receipt verified: `2026-09-22T00:28:50-05:00` (America/Chicago).
Build 10 is superseded and was detached from the draft after a real iPad touch-target
issue was found and fixed. Automatic release after Apple approval is selected.
Submission, approval, and public availability are separate states.

Public Swift repository: https://github.com/aryasalem09/BrassTune-iOS
Final source commit: `987fcb2` (initial export `eb98391`). The repository is public,
contains the app, shared Swift package, tests, required fixtures and archive helper,
and has a short README crediting Kelvin Guo and Arya Salem. No new source license
was invented; bundled font license is retained. Exported app files match the final
archive source manifest. The original monorepo's pre-existing dirty work is preserved;
no monorepo commit/push was made.

## Fixed and verified

- **Google callback errors:** live Supabase PKCE error callbacks mirror errors in
  query and fragment and include empty `sb`. The old native parser rejected every
  fragment before classifying cancellation/provider errors. The new parser accepts
  only exact mirrored error fields, retaining origin, state, duplicate-field,
  token-field, and success-fragment rejection. Independent review accepted it.
- **Google production setup:** completed existing public homepage/privacy/terms
  branding links and authorized domain; published the exact active Google OAuth
  client configuration. Chrome verified In production. Testing mode alone was not
  a proven root cause because basic openid/email/profile sign-in is exempt from
  Google's test-user restrictions. No scopes or client credentials were changed.
- **Tuner guidance:** dense audible metronome subdivisions can leave no clean
  microphone capture between click rejection windows. New localized guidance uses
  observed frame duration and recommends visual/haptic mode or slower/sparser clicks.
  Audible cadence and rejection protections remain unchanged; this is honest guidance,
  not an acoustic cancellation algorithm. Cached haptics are prepared before future pulses.
- **iPad navigation:** actual edge-tap testing confirmed the native floating tab
  control's 43-point region failed a 44-point target probe at maximum Dynamic Type
  in Arabic. The app now uses native bottom tabs while restoring the real size class
  inside every destination. All five strict >=44-point native checks now pass.
- **Test reliability:** Settings scrolling now brings both haptics and language
  controls into view. iPad queries recognize native floating controls where present.
  Physical identity probes distinguish actual phone-account identity from assumed
  accounts and retain private diagnostics outside Git.

## Executed evidence

| Surface | Result | Evidence |
| --- | --- | --- |
| Shared domain | 12 passed in source; 12 passed from public export | `/tmp/BrassTune-publication-core-tests.log` |
| Final build 11 native units | 313 passed, zero failures/skips | `/tmp/BrassTune-build11-units-20260922.xcresult` |
| Broad iPhone UI baseline | 35 passed; one scrolling test failed, then corrected and passed | `/tmp/BrassTune-sim-scout-20260921-ui-final.xcresult` |
| Latest denied/estimating/stable tuner UI | 3 passed; unrelated Settings scrolling failed before its final correction | `/tmp/BrassTune-targeted-ui-final.xcresult` |
| Corrected Settings + focused metronome | 2 passed, zero failures/skips | `/tmp/BrassTune-final-settings-metronome-20260922.xcresult` |
| Build 11 iPhone navigation/metronome/44pt | 3 passed, zero failures/skips | `/tmp/BrassTune-build11-iphone-ui.xcresult` |
| iPad core baseline | 5 passed, zero failures/skips | `/tmp/BrassTune-ipad-qa-20260921.xcresult` |
| Build 11 iPad navigation/44pt/orientations | 3 passed, zero failures/skips | `/tmp/BrassTune-ipad-build11-20260922.xcresult` |
| USB Google end-to-end | Passed, zero failures/skips: sign-in, signed-in state, cold restore, sign-out, cold signed-out state | `/tmp/BrassTune-google-roundtrip-20260922.xcresult` |
| USB audio stress | Passed in about 515 seconds; 20 tuner restarts, 3 takes, 20 scales, 20 metronome and 20 drone cycles, 50 tab switches | `/tmp/BrassTune-final-physical-stress-20260922.xcresult` |
| USB provider/cancel/audio controls | Baseline 4 passed; candidate 3 passed, signed-out precondition failed because phone account was signed in; resolved by identified-account round trip | physical lane xcresults under `/tmp/BrassTuneCandidate103PhysicalDerivedData` |
| Static checks | Localization, design tokens, release auth positive/negative preflight, Swift parse, git diff whitespace passed | commands below |

USB hardware: iPhone 15 Pro Max / iOS 26.6.2. Simulator coverage includes
compact iPhone SE, iPhone 17 Pro, and iPad Pro 13-inch M5 / iOS 26.5.
Physical auth/audio evidence is from candidate build 10; build 11 changes only
native navigation presentation/version, with final iPhone/iPad UI and unit rechecks.
Earlier zero-test authorization runs, a tool-timeout UI run, and interrupted physical
runs are not counted as passes. Early identity mismatches compared different expected
accounts; final verification used the account actually present on the phone.
The already-granted microphone prevented a fresh physical deny/grant prompt test;
simulator permission-recovery UI was separately verified.

## Apple analytics and crash review

Safari confirmed the existing store version 1.0.2 (9) Ready for Distribution.
Analytics June 23–September 20, 2026: 50 first-time downloads, 426 impressions,
104 product-page views, 19.2% displayed daily-average conversion; opted-in sessions
were 1 (1.0), 40 (1.0.1), 15 (1.0.2). Crash metrics were Not Enough Data, not zero.
Retention detail also lacked sufficient data.

Five TestFlight crash feedback records from July 28/build 1.0.0 (2) cover
metronome scheduleBuffer assertions, capture callback executor assertions, and
tap-installation assertions. Current serialization/generation/actor-hop mitigations
and the physical repeated-start stress were reviewed. No new-version crash-free
population claim follows from these sparse analytics.

Canonical Supabase read-only logs: 4 recent PKCE exchanges returned HTTP 200;
all 6 observed token requests returned 200. No database/provider-exchange failure
category matched. Consumed-state events were consistent with a retried desktop
single-use diagnostic. Browser dashboard credentials accessed a legacy project;
configured CLI credentials correctly accessed the canonical project. Only sanitized
aggregates were retained. This does not identify every possible account-specific
Google Workspace restriction or prove the cause of every historical report.

## Candidate provenance and device restoration

Evidence directory:
`~/Library/Application Support/BrassTune/ReleaseEvidence/AppStoreCandidate-2026-09-22-1.0.3-11`

- Bundle: `com.aryasalem.BrassTune`, version 1.0.3, build 11.
- Strict archive/export signatures verified; distribution `get-task-allow=false`,
  `beta-reports-active=true`; final app source manifest matches.
- Matching app/dSYM UUID: `CDB6D15B-1B6E-3846-B2C1-908C038C0E51`.
- IPA SHA-256: `343fd05f29d48c31ca7f83dc6d31176c5ca09d1ba4d0725dcc3317d0f651e502`.
- Upload succeeded September 22 at approximately 00:15 America/Chicago.
- Installed the normal non-PHYSICAL_RELEASE `.dev` build 11 after testing.
  Both original practice-state JSON files were restored individually and verified
  byte-identical by readback. Original empty Documents restored. Private pre/post-test
  backups remain outside Git. Directory restoration initially failed verification;
  individual-file restoration corrected it. Cache/window-state backup files remain
  available locally; caches may regenerate. Normal development-app launch succeeded.
- Production app on the phone was untouched (installed version 1.0.0 build 5).
  Phone ownership was explicitly handed to the user's parallel RelayAid task afterward.

## Platforms and limits

The app already supports iPad; this release improves its navigation accessibility.
`UIRequiresFullScreen` remains and true resizable multitasking is not claimed.
Apple Watch has no target. A foreground, locally timed haptic metronome with Crown
controls and settings sync is a viable separate project; no physical Watch was
confirmed for wrist timing, inactivity, or battery tests, so no Watch binary was
implemented or released. Background/wrist-down haptics are not promised.

Dense audible metronome+tuner acoustic rejection remains a documented limitation
with an explicit visual/haptic alternative. No calibrated instrument, all-accessory,
or universal background/interruption guarantee is claimed. Conditional AppModel
replacement teardown is future hardening; no production replacement path was found.
Backend/web source is unchanged; full backend/frontend suites were not repeated.

## Team, changes, and commands

Ten bounded subagents were used across discovery, implementation and independent
review: simulator scout (Luna Medium), domain checks (Luna Low), auth diagnosis
(Terra High), physical device execution (Terra Medium), publication hygiene
(Terra Medium), auth implementation (Terra Medium), audio/UI implementation
(Terra Medium), iPad/Watch architecture and QA (Sol High), independent auth/UI
review (Sol High), and independent audio review (Sol High). Effective routing was
not exposed by authoritative metadata and remains unverified. No grandchildren.
Compiles were bounded and coordinated; physical/simulator resources were handed
off explicitly to the user's parallel task.

This pass changed AuthService.swift, AppModel.swift, AppRootView.swift,
NativeAudioEngine.swift, Resources/Localizable.xcstrings, project.pbxproj,
AuthReliabilityTests.swift, AudioReliabilityTests.swift, BrassTuneAppUITests.swift,
ReleaseSectionCoverageUITests.swift, this report, and DOCS_INDEX.md. Earlier dirty native and
release-document edits were preserved. Public-export README/.gitignore were added.

Commands/checks: `swift test`; native `xcodebuild test`, `build-for-testing`,
`test-without-building`, `archive`, and `-exportArchive`; `xcresulttool` summaries
and attachment export; `codesign --verify --deep --strict`; `dwarfdump --uuid`;
localization/design/preflight scripts; SHA-256 source/artifact comparisons;
`git diff --check`; scoped public-export Git staging/commit/push; `devicectl`
backup/install/restore/readback/launch; read-only Supabase logs; Chrome GitHub and
Google configuration; Safari App Store Connect. Optional deletion of two temporary
DerivedData caches was rejected by the shell's dangerous-command guard; caches
were retained and this did not block release work.

References: [Google audience rules](https://support.google.com/cloud/answer/15549945?hl=en),
[Apple iPad full-screen migration](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key),
[Apple Watch haptics](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play%28_%3A%29).
