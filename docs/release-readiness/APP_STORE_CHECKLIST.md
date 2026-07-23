# Apple App Store Checklist

Updated: 2026-07-23. This is an implementation and local-simulator checklist, not an App Store readiness decision.

## Implemented local artifacts

- Native SwiftUI target, unit/UI test targets, microphone and photo-library usage descriptions, and `PrivacyInfo.xcprivacy` are present.
- Camera capture is not implemented or exposed; no camera usage string is declared.
- In-app privacy, terms, support, export, and account-deletion surfaces exist. Local clear/delete controls remove imported-score metadata and copied local files.
- The app has Tuner, Play-Along, Progress, Class, and Settings tabs; its String Catalog covers 12 production locales.
- Real-microphone Tuner and Play-Along behavior is separated from explicit UI-test fixtures. The shared scorer contract includes centered/accepted thresholds and a two-second hold. The separate metronome contract defines BPM as the selected denominator beat.
- Metronome, local practice, and score import/view/edit/export features exist. The bundled app icon remains a placeholder and needs final brand artwork.

## Current local evidence

- BrassTuneCore: `3` tests passed.
- Native app units: `113/113` tests passed with zero skips.
- UI smoke: `9` tests passed in one invocation.
- Four simulator builds, launch screenshots, plist checks, and black-band checks passed.

This is unsigned simulator evidence. It does not prove the final bundle identifier, a configured Supabase/native production environment, physical-device behavior, signing, archive/export validity, TestFlight, or App Store acceptance.

## Required before submission

- Set final bundle identifier, Apple Team/signing, version/build strategy, app record, store metadata, icon, support/legal URLs, privacy disclosures, export compliance, age rating, and review/demo access.
- Configure and verify Sign in with Apple/Supabase callback and production API/Auth settings. Current environment values are intentionally not documented here; blank or unavailable configuration remains unverified.
- Run a final dependency/privacy-manifest and required-reason-API audit after production dependencies are pinned.
- Validate physical iPhone/iPad microphone/brass audio, metronome click/haptics/routes/timing, Files/Photos import, accessibility, localization, and interruption handling.
- Produce and validate a signed archive, upload/process it in TestFlight, then complete App Store Connect and review.

## Apple references

- [Submitting apps](https://developer.apple.com/app-store/submitting/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## Explicit exclusions

No physical-device, signing, archive, TestFlight, App Store Connect, or hosted-provider completion is claimed by the local counts above.
