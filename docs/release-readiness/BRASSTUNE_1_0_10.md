# BrassTune 1.0.10 (22)

Kelvin Guo, Arya Salem · November 15, 2026

Two educators independently described difficulty choosing a welcome-screen path and a preference for the higher metronome click throughout a bar. The update explains guest storage, account profiles and class sign-in. Metronome settings now offer the higher click on all audible ticks, including count-in and subdivisions. Visual-only mode and silent bars still suppress audio. Existing installations default to the previous sound. The build also includes the November 8 goal-review ordering and single-BPM target changes.

## Changes and verification

- WelcomeAuthViews.swift uses existing localized text for the three welcome-screen choices.
- AppRootView.swift, Models.swift, NativeAudioEngine.swift and Localizable.xcstrings add the sound preference and preserve existing saved settings. GapMetronomeTests.swift covers sound generation and silence. The Xcode project sets version 1.0.10 and build 22.
- Swift package tests passed (12). Xcode native app unit tests passed (380), including 15 metronome tests. Localization coverage and native git diff whitespace checks passed.
- XcodeBuildMCP built and launched the app on iPhone 17 Pro, iOS 26.2. Computer Use verified the welcome explanations, class sign-in destination, entry into guest practice, and location of the new switch in Metronome settings. Physical speaker loudness was not measured.
- The release script archived and exported the production bundle. Strict codesign verification passed. The exported IPA and archive agree on version, bundle ID and production auth settings. Exported IPA SHA-256 is 25902819ab4ddefa547748c6d6a0414f9042a397aed0341f09b31ed0de5bfdfe.
- Xcode reported upload success and Apple processing at 5:51 p.m. Central. Local receipts are in ~/Library/Application Support/BrassTune/ReleaseEvidence/1.0.10-22/.
- One combined test invocation selected UI tests under the unit scheme and stopped before running tests. Unit and UI checks were then invoked under their corresponding schemes.
- Four Terra Medium agents covered Gmail review, release discovery and the two implementation areas. A Sol High reviewer checked source provenance, asset attribution and release risk. Effective model routing was unavailable. The parent handled versioning, verification, signing, upload and App Store Connect. No website or backend deployment was needed.
- Three UI tests passed on the iOS 26.5 QA simulator under BrassTuneAppUISmoke. They covered silent-bar cycling and persistence, account/guest reentry, and Arabic welcome at maximum Dynamic Type.

## App Store submission

At 5:55 p.m. Central on November 15, App Store Connect confirmed “1 Item Submitted,” “Draft Submissions (0),” and “1.0.10 Waiting for Review.” The submission contained version 1.0.10 (22). Automatic release after approval and immediate availability to all users were selected. Apple approval and public availability remain pending.

The App Store Connect receipt is stored with the owner’s release evidence.

## Expanded candidate, build 23

A second review of educator correspondence identified requests for measurable passage goals, guidance on using individual practice tools, beginner-friendly temperament instruction and less distraction during offline practice. Build 23 adds four workflows based on those requests.

- First practice walks a guest through tuning a comfortable note, playing a passage with the metronome and reflecting. Each step is optional and the player controls the microphone and sound.
- Clean-repetition goals now have a collapsible tempo ladder. Set a starting BPM and increment, repeat a rung, or step back. The final rung reaches the exact target. Advancing the ladder leaves progress reporting and completion up to the player.
- Saved scores can open an editable goal populated with their title, passage details and target tempo. A goal is created when the player saves it.
- The drone exercise offers a major third and perfect fifth and shows how the just interval differs from its equal-tempered counterpart, rounded to −14 and +2 cents respectively.

Relative to the signed build 22 source manifest, the production changes are in AppRootView.swift, PracticeFeatureViews.swift, PracticeFeatures.swift, PrimaryNavigationViews.swift, Localizable.xcstrings, and the Xcode project build number. The build includes all build 22 improvements. The test changes are in PracticeGoalFeatureTests.swift, DroneEnhancementTests.swift and FeedbackGoalsUITests.swift.

The full native unit suite passed 384 tests on iOS 26.2 and the shared Swift suite passed 12. The localization check reported zero missing static keys, incomplete locales and placeholder violations. Production version, auth configuration, bundle ID, signature, and 47 source fingerprints were verified before upload. The signed IPA SHA-256 is 15ec16ba74564e6044697ba2cec3fd4e3c238fc1043439724bb34eefd580f41b. Private export, upload and test receipts are in ~/Library/Application Support/BrassTune/ReleaseEvidence/1.0.10-23/final/. Physical audio quality and an actual airplane-mode device run remain unverified.

Four implementation and discovery agents requested Terra Medium. An independent UI verification agent requested Sol High. Effective routing was unavailable. The parent integrated translations, verified the source against build 22, ran native and core tests, checked the simulator, and managed the signed upload and store submission.

Four focused simulator UI journeys passed together on iOS 26.5. They covered the first-practice walkthrough, selecting both drone intervals and seeing their signed offsets, advancing a ladder and opening the stopped metronome at the selected BPM, and saving an editable goal from a fixture score. The initial UI test selectors for two SwiftUI groups failed; addressing the distinct visible button labels fixed the test harness. The final UI result and log were copied to the private evidence directory.

At 6:11 p.m. Central on November 15, build 23 replaced build 22 in App Review. App Store Connect confirmed “1 Item Submitted” and displayed “1.0.10 (23) App Version Waiting for Review” in the submission details. Automatic release after approval for all users was selected. The App Store Connect receipt is stored with the owner’s release evidence.

## Local follow-up after submission

Score Practice now appears first on the Practice tab. Saved scores show View full page, Create practice goal, and Start guided practice before page and annotation controls. This changes discovery of existing manual features and is outside submitted build 23. The score-to-goal UI journey passed on iOS 26.5, and the localization coverage check passed. A targeted search of received educator email found a comparison with forScore and a separate request for measurable passage goals. It found no direct request for a more prominent reader or automatic notation recognition.
