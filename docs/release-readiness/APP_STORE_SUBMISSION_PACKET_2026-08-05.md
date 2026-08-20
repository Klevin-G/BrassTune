# BrassTune App Store Submission Packet

Updated: 2026-08-05. This packet is prepared from the current native iOS source and a read-only App Store Connect audit. It is not evidence that a new build was archived, uploaded, selected, or submitted.

## App identity

- App Store Connect app: BrassTune
- Apple ID: `6795688588`
- Bundle ID: `com.aryasalem.BrassTune`
- App Store version: `1.0`
- Current source marketing version: `1.0.0`
- Current source build number: `2`
- Recommended primary category: Music
- Recommended secondary category: Education
- Recommended age rating: 4+, provided the final questionnaire continues to contain no objectionable, gambling, medical, unrestricted-web, public-user-content, or messaging features.

## English (U.S.) product-page copy

### Subtitle — 27 characters

Tuner, scales, and practice

### Promotional text — 161 characters

Practice with a live brass tuner, guided warm-ups, scales up to three octaves, metronome, drone and interval tools, score routines, and honest progress tracking.

### Description

BrassTune is a focused practice companion for brass players. It brings the tools for intonation, timing, warm-ups, scales, score work, and progress review into one clear routine.

LIVE BRASS TUNER

See the detected written note, octave, cents, frequency, confidence, and whether you are flat, centered, or sharp. BrassTune shows estimating, unavailable, interrupted, and denied states honestly instead of inventing a reading.

PRACTICE TOOLS

- Run guided warm-ups and visual routines.
- Practice major, minor, melodic minor, harmonic minor, and chromatic scales.
- Choose one, two, or three octaves when the range fits the selected instrument.
- Use a configurable metronome for tempo, meter, subdivisions, accents, count-in, sound, and haptics.
- Play reference tones, drones, and intervals.

SCORE PRACTICE

Import a PDF or photo from Files or Photos, review each page, add focus measures and passage notes, set a target tempo, and start a manual guided all-notes routine. Score files stay on the device unless you explicitly export or share them.

PROGRESS YOU CAN TRUST

Review saved sessions, reflections, practice totals, pitch summaries, and completed routines. Guest practice works without an account. Optional account features are clearly separated from local practice.

PRIVACY-FIRST AUDIO

The microphone runs only when you start a listening feature. Native recordings stay on the device unless you explicitly export or share them. BrassTune does not use advertising trackers.

BrassTune supports trumpet, cornet, flugelhorn, horn, trombone, bass trombone, euphonium, baritone, and tuba profiles with written-pitch and transposition-aware feedback.

### Keywords — 86 bytes

`brass,tuner,trumpet,trombone,tuba,horn,euphonium,scales,metronome,practice,pitch,drone`

### URLs and copyright

- Support URL: `https://brasstune.vercel.app/support`
- Marketing URL: `https://brasstune.vercel.app`
- Privacy Policy URL: `https://brasstune.vercel.app/privacy`
- Terms URL used in app: `https://brasstune.vercel.app/terms`
- Copyright: `2026 Arya Salem`

All three required legal/support pages returned HTTP 200 during this pass. Recheck from the final candidate before submission.

## App Review information

- Sign-in required: No. Core practice can be reviewed as a guest.
- Contact name: Arya Salem
- Contact email: `brasstune1@gmail.com`
- Contact phone: owner must supply a monitored phone number; none is stored in the repository and one must not be invented.
- Demo credentials: not required for the guest review path.

Suggested reviewer notes:

> BrassTune can be reviewed without an account. On first launch choose Continue as Guest, select any instrument, and choose Start Practicing. The microphone is requested only after starting Tuner or a microphone-assisted scale. Scales also provide a Visual timing mode that does not require microphone access. Practice includes guided warm-ups, metronome, drone and interval tools, reference tones, and local score practice. To test a score, import a PDF from Files or an image from Photos; add practice notes and select Start guided practice. Imported scores and native recordings remain on the device unless the reviewer explicitly exports or shares them. Account creation, Apple sign-in, and Google sign-in are optional and are not required to exercise the core app.

## App Privacy answers for the native build

The final answers must match the final signed binary and `PrivacyInfo.xcprivacy`.

| Data type | Collected | Linked to identity | Tracking | Purpose |
|---|---:|---:|---:|---|
| Contact Info — Email Address | Yes | Yes | No | App Functionality |
| Identifiers — User ID | Yes | Yes | No | App Functionality |
| User Content — Other User Content | Yes | Yes | No | App Functionality |
| Audio Data | No | No | No | Native audio is local unless the person explicitly exports or shares it |
| Diagnostics, advertising, location, contacts, health, financial, browsing, search, purchases | No | No | No | Not collected by the native build |

- Tracking: No.
- Tracking domains: none.
- Privacy choices URL: leave blank unless a dedicated privacy-choices page is added; account deletion and local-data clearing are available in app.
- Export compliance: `ITSAppUsesNonExemptEncryption = false` because the app uses Apple-provided HTTPS/TLS and platform security services without custom non-exempt cryptography.

## Accessibility declarations

- VoiceOver: an owner-reported physical iPhone pass exists. Declare support for iPhone only if that pass covered the common tasks represented in the shipping candidate.
- Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, and Reduced Motion: the app has code and simulator evidence for several of these, but the App Store labels should remain undeclared until each Apple evaluation criterion is completed per supported device family.
- Captions and Audio Descriptions: not applicable because the app does not ship video dialogue or narrated video content.

Accessibility Nutrition Labels are separate from the app's ordinary accessibility behavior; they must not be inferred solely from SwiftUI APIs or simulator automation.

## Screenshot assets

Local asset root:

`<user-home>/Library/Application Support/BrassTune/AppStoreSubmissionAssets-2026-08-05`

### iPhone 6.9-inch

Five opaque JPEGs at `1320 x 2868`:

1. `iPhone-6.9/01-practice.jpg` — SHA-256 `a9b0bc00097e188e7d98249fb9cf27ad7d8f95ae07b3559144ca6facd63b46f3`
2. `iPhone-6.9/02-tuner.jpg` — SHA-256 `3b2a701e1f50649c60470af0dad062bb8c2b3e614ca76319e9aea8642e14c8b0`
3. `iPhone-6.9/03-scales-three-octaves.jpg` — SHA-256 `e2d955a860240b5a19f964f6946358237b7bf90c96de26bac1ee3ad21a720326`
4. `iPhone-6.9/04-score-practice.jpg` — SHA-256 `19423c886735cb644e61bcf5444505f422884cdc648d4538adbc80edd50951d4`
5. `iPhone-6.9/05-guided-score-practice.jpg` — SHA-256 `beae5ef697ef7e2dd7b23820c8249661c71a696cebcae25250cdc6c84640939f`

### iPad 13-inch

Two opaque JPEGs at `2064 x 2752`:

1. `iPad-13/01-practice.jpg` — SHA-256 `97653d8cf880e725410ac5fdcf6cb2bddf48d24a13e5d3b843b5e1bab6093ae1`
2. `iPad-13/02-tuner.jpg` — SHA-256 `d807f45af17fabf6deca699e395b9b2f2ecb4c09800760506e64d4d7f4597c7e`

The images contain deterministic sample practice data and no personal account data. The JPEGs meet Apple's current accepted 6.9-inch iPhone and 13-inch iPad portrait dimensions and contain no alpha channel.

## Current-source native preflight evidence

Verified after the metadata audit and screenshot capture:

- Swift Core: `12/12` passed.
- Native unit suite: `240/240`, zero failures/skips on iPhone 17 Pro / iOS 26.5 simulator.
- Selected non-physical native UI suite: `23/23`, zero failures/skips in 721.901 test seconds.
- Focused legal/support UI: `1/1` passed after replacing the stale legal-detail status copy.
- Current-source physical targeted UI/audio: `7/7`, zero failures/skips in 663.931 test seconds on the wired iPhone 15 Pro Max / iOS 26.4.1. The suite covered strict Light/Dark structure, legal/support, More, guided score practice, three-octave Scales, Practice reset, and the built-in-route audio crash-family stress (20 Tuner, 20 microphone Scale, 20 Metronome, 20 reference-tone cycles, background recovery, and 50 rapid tab switches). No current-run BrassTune report appeared in the postflight device inventory.
- Current-source optimized Release simulator build: passed.
- Current-source generic iOS Release build: passed with zero Xcode errors and zero warnings using Apple Distribution and `BrassTune App Store Distribution 2026`.
- Signed app: `com.aryasalem.BrassTune` `1.0.0 (2)`, strict signature valid, `get-task-allow=false`, `beta-reports-active=true`, Sign in with Apple `Default`.
- App/dSYM UUID: `6F560646-9C34-38C0-B097-B05E8B70C0EC`.
- Bundled `PrivacyInfo.xcprivacy`: present and valid.
- Screenshot recheck: all seven JPEG checksums match this packet, the five iPhone images are `1320 x 2868`, the two iPad images are `2064 x 2752`, and all report `hasAlpha: no`.

Evidence root:

`<user-home>/Library/Application Support/BrassTune/ReleaseEvidence/NativeIOSContinuation-2026-08-05/AppStorePreflight`

The distribution artifact was a build-only signing check. The separate physical pass replaced only `com.aryasalem.BrassTune.dev` and then restored a normal Debug `.dev` build. It did not replace or uninstall production `com.aryasalem.BrassTune`, create an archive, export an IPA, upload a build, or select a build in App Store Connect.

## Live App Store Connect audit

Observed read-only on 2026-08-05:

- App record exists and iOS version `1.0` is in Prepare for Submission.
- Product-page screenshots, promotional text, description, keywords, Support URL, Marketing URL, and copyright were empty.
- No build was selected.
- Sign-in required was enabled even though guest review is available; username and password were empty.
- App Review contact fields and notes were empty.
- Category, age rating, content-rights declaration, and Digital Services Act trader status were not set.
- Privacy Policy URL and the App Privacy questionnaire were empty.
- App Accessibility declarations were not started.
- Starting price and territory availability were not configured.
- Public distribution was selected. Apple silicon Mac and Apple Vision Pro availability were selected; the version was reported as incompatible with Apple Vision Pro.
- TestFlight contains only `1.0.0 (2)`, uploaded 2026-07-28. It reports Ready to Submit, 3 invites, 2 installs, 17 sessions, and 5 crashes. The five crash feedback entries match the preserved build-2 crash evidence.

No App Store Connect field was changed during the audit.

## Submission blockers that cannot be papered over

1. The current working tree is very large and dirty, and `main` is behind `origin/main`; an exact reviewed candidate commit does not yet exist.
2. The shipping source still has build number `2`, which is already used in TestFlight. A new upload requires a higher unique build number.
3. The earlier release pass explicitly prohibited creating or uploading build 3. This packet does not override that restriction.
4. Build 2 has five physical TestFlight crashes and must not be selected as the App Store candidate.
5. The repaired audio crash families still require closure against the exact new signed candidate on a physical iPhone, including repeated cycles and cross-feature stress.
6. A fresh distribution archive, validation, upload, TestFlight processing result, and final dSYM have not been created for the current source.
7. Pricing, availability, metadata, privacy, age rating, content rights, accessibility answers, review contact phone, and DSA trader status remain unset in App Store Connect.
8. DSA trader status and the reviewer contact phone are owner/legal attestations and must not be guessed.

## Exact safe submission order

1. Review and isolate the intended native changes without discarding unrelated user work.
2. Create an exact candidate commit and reconcile it with the four upstream commits.
3. Explicitly authorize a unique next build number and a new internal TestFlight upload.
4. Archive the production bundle with Apple Distribution signing, validate it, preserve the archive and dSYM, and upload only that exact candidate.
5. Repeat the crash-family physical matrix on the processed internal build and preserve logs.
6. Complete the owner/legal attestations and populate the prepared metadata/privacy fields.
7. Select the new crash-free build, use manual release, run a final read-only review, and only then add it to App Review.
