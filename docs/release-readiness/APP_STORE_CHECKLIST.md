# Apple App Store Checklist

Updated: 2026-08-05. This is the native iOS submission checklist. It separates
current-source simulator checks, signed build-only evidence, historical physical
evidence, and the still-missing exact TestFlight candidate.

## Verified in this pass

- Swift Core passed `12/12`; the native app unit suite passed `240/240` on an
  iPhone 17 Pro / iOS 26.5 simulator.
- The selected non-physical UI suite passed `23/23`, zero failures/skips, and the
  focused legal journey passed `1/1`.
- The fresh current-source physical targeted suite passed `7/7`, zero
  failures/skips, in 663.931 test seconds on the wired iPhone 15 Pro Max. It
  includes strict Light/Dark structure, legal/support, More, guided score
  practice, three-octave Scales, Practice reset, and the built-in-route audio
  crash-family stress.
- Current-source Release simulator compilation passed.
- A fresh, no-install, no-archive generic iOS Release build completed with zero
  Xcode errors or warnings using Apple Distribution and the explicit
  `BrassTune App Store Distribution 2026` profile.
- The built app is `com.aryasalem.BrassTune` version `1.0.0 (2)`. Its strict
  signature is valid; the app and profile both contain Sign in with Apple
  `Default`, `get-task-allow=false`, and `beta-reports-active=true`; the app and
  dSYM UUID are `6F560646-9C34-38C0-B097-B05E8B70C0EC`.
- `PrivacyInfo.xcprivacy` is present and valid, the non-exempt-encryption flag is
  false, localization checks are clean, and public privacy/terms/support URLs
  returned HTTP 200.
- Five opaque 6.9-inch iPhone screenshots and two opaque 13-inch iPad screenshots
  are prepared under `<user-home>/Library/Application Support/BrassTune/AppStoreSubmissionAssets-2026-08-05`.
- Production TestFlight build `1.0.0 (2)` remained installed at its original
  path and untouched. The isolated `.dev` app was rebuilt for the current-source
  physical suite and then restored to a normal Debug `.dev` build.

Evidence root:

`<user-home>/Library/Application Support/BrassTune/ReleaseEvidence/NativeIOSContinuation-2026-08-05/AppStorePreflight`

Prepared copy, privacy mapping, review notes, screenshot checksums, and the live
App Store Connect audit are in
[`APP_STORE_SUBMISSION_PACKET_2026-08-05.md`](APP_STORE_SUBMISSION_PACKET_2026-08-05.md).

## Required before a new internal candidate

- Reconcile the preserved dirty native worktree with the four upstream commits
  and bind the intended source to an exact reviewed commit without discarding
  unrelated user work.
- Change the current build number from already-used `2` to a unique higher build
  number. The earlier instruction prohibiting build 3 remains in force.
- Archive and validate that exact source, retain the archive and dSYM, upload it
  to TestFlight, wait for processing, and install the processed build without
  using build 2 as the candidate.
- Repeat the original three crash-family physical matrix against that exact
  processed build. Preserve crash/device logs and keep unavailable Bluetooth,
  wired, and audible AirPlay routes marked untested rather than passed.

## Required before App Review

- Populate the prepared screenshots, subtitle, promotional text, description,
  keywords, support/marketing/privacy URLs, copyright, reviewer notes, and
  category fields in App Store Connect.
- Complete age rating, content rights, privacy questionnaire, pricing,
  territory availability, and accessibility declarations against the final
  processed binary.
- Supply a monitored App Review phone number and make the Digital Services Act
  trader declaration. These are owner/legal attestations and must not be guessed.
- Select only the new crash-free candidate, keep manual release selected, run a
  final read-only review, and then add the version to App Review.

## Current decision

**Blocked for App Store submission.** Local compilation, tests, screenshots, and
distribution signing are prepared, but the exact unique-build archive,
processed TestFlight candidate, exact-candidate physical closure, and live
metadata/owner attestations do not yet exist.
