# TestFlight Handoff
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23 UTC. The dated build-2 material below is historical only.

## Current submitted candidate

- Deployed web/backend implementation is `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`; native archive source is distinct, `d371100` on `arya/final-physical-release-20260823`.
- Build `1.0.1 (7)` archive/export/upload succeeded. Its IPA has a strict valid Apple Distribution signature for `Apple Distribution: Arya Salem`, team `8S79RLTSWV`, bundle `com.aryasalem.BrassTune`, production environment/API, matching app/dSYM UUID `77D84475-6D50-3D94-B842-290431F0D74D`, and SHA-256 `640511f5a15f579500f86710393a6f661ced4cff87a64f00b8ccbe689bea2782`.
- TestFlight reports build 7 **Ready to Submit**. Version `1.0.1` has build 7 attached, stale review notes were replaced, and the version is submitted as **Waiting for Review** with manual release selected.
- Connected-iPhone evidence includes automation canary `1/1`, strict accessibility `1/1`, standard UI `26/26`, expanded audio stress `1/1`, and the earlier sustained 120-BPM check `1/1`; see `TEST_MATRIX.md` for exact durations and boundaries.

## Historical 2026-08-05 native state

- Production identity is configured: team `8S79RLTSWV`, bundle
  `com.aryasalem.BrassTune`, Sign in with Apple, Apple Distribution identity,
  and explicit App Store profile.
- Current source remains version `1.0.0 (2)`. Build `2` already exists in
  TestFlight and has five preserved physical crash reports, so it must not be
  selected as the submission candidate.
- Fresh current-source gates passed: Swift Core `12/12`, native units `240/240`,
  selected non-physical UI `23/23`, focused legal UI `1/1`, Release simulator
  build, localization, release-auth preflight, privacy-manifest validation, and
  public legal/support URL checks.
- Fresh current-source physical targeted UI/audio passed `7/7`, zero
  failures/skips in 663.931 test seconds on the wired iPhone 15 Pro Max. The
  full crash-family case completed 20 Tuner, 20 microphone Scale, 20 Metronome,
  20 reference-tone cycles, background recovery, and 50 rapid tab switches;
  its postflight inventory added no BrassTune report.
- A no-install, no-archive generic iOS Release build passed store validation
  with zero errors/warnings. It is Apple Distribution-signed with
  `get-task-allow=false`, `beta-reports-active=true`, Sign in with Apple
  `Default`, and matching app/dSYM UUID
  `6F560646-9C34-38C0-B097-B05E8B70C0EC`.
- Google and Apple native provider completion, callback, cold restore, sign-out,
  and signed-out relaunch previously passed on the isolated physical `.dev`
  bundle. Those results do not replace final-candidate TestFlight validation.
- The wired iPhone 15 Pro Max remains connected on iOS 26.4.1 with Developer
  Mode enabled. Production and `.dev` bundles both remain `1.0.0 (2)`. The
  production TestFlight app remained at its original install path and untouched;
  only the isolated `.dev` app was rebuilt for testing and then restored to a
  normal current-source Debug `.dev` build.

Evidence:

`<user-home>/Library/Application Support/BrassTune/ReleaseEvidence/NativeIOSContinuation-2026-08-05/AppStorePreflight`

## Historical next-candidate sequence (superseded by build 7)

1. Reconcile the dirty native worktree with upstream and bind the intended
   candidate to an exact reviewed commit.
2. Assign a unique build number greater than `2`. The earlier no-build-3/no-upload
   restriction must be explicitly superseded before this step.
3. Create and validate the production archive; preserve the archive, export
   diagnostics, and matching dSYM.
4. Upload only that exact candidate, wait for TestFlight processing, assign the
   internal group, and install it on the physical device without treating the
   existing build 2 as a substitute.
5. Repeat the original metronome, live input-tap, and duplicate-tap crash
   reproductions, their repeated-cycle groups, and cross-feature stress against
   the processed build. Preserve device logs and any failure artifacts.
6. Complete the remaining metadata and owner/legal attestations from
   [`APP_STORE_SUBMISSION_PACKET_2026-08-05.md`](APP_STORE_SUBMISSION_PACKET_2026-08-05.md).

## Current decision

**Submitted; Waiting for Review.** Manual release remains selected. App Review
acceptance is external. Remaining unavailable checks are calibrated brass/acoustic
accuracy, AirPlay/HomePod/Bluetooth/wired routes, Files/Photos preseeded
fixtures, timer/media-reset operator prerequisites, and full assistive-tech/iPad
coverage.

## Do not claim

- App Store submission readiness from simulator or build-only signing evidence.
- Build 2 as a repaired candidate.
- Bluetooth, wired input, or audible production AirPlay coverage when the
  corresponding hardware/evidence is unavailable.
- Calibrated tuner latency/accuracy or accepted audible metronome jitter from
  the existing consumer-device observations.
