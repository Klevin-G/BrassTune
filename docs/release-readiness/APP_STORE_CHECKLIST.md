# Apple App Store Checklist
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. This is the native iOS submission checklist. It separates
current-source simulator checks, signed build evidence, historical physical
evidence, and remaining hosted/physical/App Review gates.

## Current 2026-08-23 submission state

- Vercel and Render serve release implementation
  `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`; strict hosted Playwright passed
  `50/50` across five projects. The native candidate source is distinct:
  `d371100` on `arya/final-physical-release-20260823`. A future merge SHA must
  not be substituted for either identifier.
- Build `1.0.1 (7)` was archived/exported from `d371100`, with a strict valid
  Apple Distribution signature (`Apple Distribution: Arya Salem`, team
  `8S79RLTSWV`), production environment/API, bundle
  `com.aryasalem.BrassTune`, matching app/dSYM UUID
  `77D84475-6D50-3D94-B842-290431F0D74D`, and IPA SHA-256
  `640511f5a15f579500f86710393a6f661ced4cff87a64f00b8ccbe689bea2782`.
- Build 7 upload succeeded and TestFlight is **Ready to Submit**. Version
  `1.0.1` has build 7 attached; stale review notes were replaced and the
  version was submitted. It is now **Waiting for Review** with manual release.
  Guest sign-in-required is unchecked. App Privacy is published for Email
  Address, User ID, Other User Content, Name, and Photos or Videos; all are
  linked, for App Functionality, and not used for tracking.
- Physical automation canary passed `1/1` in 14.058 s; strict accessibility
  `1/1` in 79.342 s; standard UI `26/26` in 774.943 s; and expanded audio
  stress `1/1` in 511.046 s, including 20 tuner listener reinstalls and three
  explicit take/save cycles. Broad XCUI detector findings were audited as false
  positives using screenshots/token ratios.

## Historical 2026-08-05 evidence

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

## Historical candidate prerequisites (satisfied or superseded)

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

## Historical App Review prerequisites (recheck against the current candidate)

- Populate the prepared screenshots, subtitle, promotional text, description,
  keywords, support/marketing/privacy URLs, copyright, reviewer notes, and
  category fields in App Store Connect.
- Complete age rating, content rights, privacy questionnaire, pricing,
  territory availability, and accessibility declarations against the final
  processed binary.
- In App Store Connect, add the profile-feature App Privacy entries if that
  feature ships: **Contact Info — Name** and **User Content — Photos or
  Videos**; each is linked to the user, not used for tracking, and used for
  **App Functionality**. The checked-in `PrivacyInfo.xcprivacy` now contains
  that mapping; confirm it in the final signed binary. This is prepared guidance
  only: the App Store Connect questionnaire has not been updated by this
  repository change.
- Verify that the deployed avatar storage remains private and backend-proxied;
  exercise upload, replacement, removal, account deletion cleanup, and the
  account-export profile fields with a disposable account. The local backend
  contract exports the current avatar only as `profile/avatar.jpg`, with bounded
  metadata at `profile/avatar.json`; it never exposes the raw storage object
  key/path and omits both entries when no avatar exists. Validate that contract
  against the deployed candidate before relying on it.
- Supply a monitored App Review phone number and make the Digital Services Act
  trader declaration. These are owner/legal attestations and must not be guessed.
- Select only the new crash-free candidate, keep manual release selected, run a
  final read-only review, and then add the version to App Review.

## Current decision

**Submitted; Waiting for Review.** Manual release remains selected. App Review
acceptance is not implied. Unavailable attended gates remain: calibrated
brass/acoustic accuracy; AirPlay/HomePod, Bluetooth, and wired routes;
Files/Photos preseeded fixtures; timer/media-reset operator prerequisites; and
full assistive-technology/iPad coverage.
