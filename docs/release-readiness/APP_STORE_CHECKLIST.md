# Apple App Store Checklist

Updated: 2026-07-23. Candidate code head: `e1b3f61351d62e1438ac457c31b1a8d40691a1d5`; billing-attempt and exact local-gate basis: `99e5a7f`. This is an implementation and simulator checklist, not an App Store readiness decision.

## Implemented local artifacts

- Native SwiftUI target, unit/UI targets, microphone and photo-library usage descriptions, and `PrivacyInfo.xcprivacy` are present.
- Camera capture is not exposed and no camera usage description is declared.
- In-app privacy, terms, support, export, and account-deletion surfaces exist. Local clear/delete controls remove imported-score metadata and copied local files.
- The app includes Tuner, Play-Along, Progress, Class, and Settings; the String Catalog covers 12 production locales.
- The shared scorer defines centered/accepted thresholds and two-second hold; the metronome contract defines BPM as the selected denominator beat.
- Bundled icon artwork remains a placeholder and needs final brand art.

## Current evidence

- Exact local gate at `99e5a7f`: BrassTuneCore `3/3`, app units `113/113`, and a Debug build on a dynamically discovered iPhone 17 Pro simulator. Earlier recorded local evidence also includes UI smoke `9/9`, four simulator builds, launch screenshots, plist checks, localization, and black-band checks.
- GitHub Actions [Swift run 30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369) succeeded on production-identical predecessor `2106768f177c64a1475c6168eed6d9a172633435`; the successor changes only Playwright coverage and release documentation, not production application code. Exact-head Swift attempt [30004831943](https://github.com/Klevin-G/BrassTune/actions/runs/30004831943) was blocked by GitHub billing/spending enforcement before checkout or any step, not by a Swift test failure. Zero self-hosted runners were available; no paid/new-runner workaround was authorized, so exact-head Swift evidence remains required before merge.

This is unsigned simulator/CI evidence. It does not establish physical-device microphone quality, configured native production auth/API settings, signing, archive/export validity, TestFlight, or App Store acceptance.

## Required before submission

- Set bundle identifier, Apple Team/signing, version/build strategy, app record, store metadata, icon, support/legal URLs, privacy disclosures, export compliance, age rating, and review/demo access.
- Configure and verify Sign in with Apple/Supabase callback plus production API/Auth settings.
- Perform a final dependency/privacy-manifest and required-reason-API audit after production dependencies are pinned.
- Validate physical iPhone/iPad microphone/brass audio, metronome routes/timing, Files/Photos import, accessibility, localization, and interruption behavior.
- Create and validate a signed archive, then upload/process it in TestFlight before App Store Connect submission.

## Apple references

- [Submitting apps](https://developer.apple.com/app-store/submitting/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## Explicit exclusions

No physical-device, signing, archive, TestFlight, App Store Connect, production-provider, or hosted-release completion is claimed by the evidence above.
