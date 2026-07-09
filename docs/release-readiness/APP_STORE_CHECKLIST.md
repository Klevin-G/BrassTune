# Apple App Store Checklist

Official Apple sources checked on 2026-06-18, refreshed for this run on 2026-06-20, and native status updated on 2026-07-04:

- [SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements/?id=02032026a): apps uploaded to App Store Connect must be built with Xcode 26 or later using iOS/iPadOS 26 SDKs since April 28, 2026.
- [Submitting apps](https://developer.apple.com/app-store/submitting/): build and test with current Xcode/latest SDKs.
- [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/): account-creation apps must let users initiate deletion in app.
- [Required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api): required-reason API usage must be declared in privacy manifests.
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files): app/SDK privacy practices and required-reason APIs belong in the privacy manifest.
- [App Review](https://developer.apple.com/distribute/app-review/): gated features need demo access/instructions.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): release claims, privacy disclosures, and demo access must be accurate.
- [VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller): native document scanning should use platform document-camera APIs where available.
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/): TestFlight requires App Store Connect setup and an uploaded signed build.

## Implemented Technical Artifacts

- Native SwiftUI app target exists at `swift/BrassTuneApp`.
- Not a web wrapper.
- Unit and UI test targets exist.
- `NSMicrophoneUsageDescription` is configured in build settings.
- `NSPhotoLibraryUsageDescription` is configured for user-selected score image import.
- Camera capture is not implemented, is hidden from the UI, and no camera usage string is declared in the app target.
- `PrivacyInfo.xcprivacy` exists and declares collected data (email, audio) and the one required-reason API in use (UserDefaults, CA92.1). The score-import file APIs use `.fileSizeKey`/`.contentTypeKey`, which are not required-reason APIs.
- App icon asset is present (a 1024×1024 brass tuning-fork placeholder in `AppIcon.appiconset`); replace with final brand artwork before store submission.
- In-app privacy, terms, support, data export, and account deletion surfaces exist.
- Account deletion can be initiated in app.
- Local clear/delete controls remove imported score metadata and copied local score files.
- Simulator Debug/Release builds pass with Xcode 26.2 / iOS 26.2 SDK.
- Native metronome simulator scope exists: visual pulse, audible click output, haptic option, mute, volume, meter, subdivision, and tap tempo.
- Native score assist scope: PDF/image/Photos/sample import, thumbnails, page selection, rotate/crop/enhance preview, a full-resolution zoomable page viewer (PDFKit for PDFs, memory-safe ImageIO decoding for images), annotations, metadata + original-file export, and local delete.
- Local AVAudioEngine live microphone capture code exists with permission handling, PCM input tap, pitch/confidence/RMS/no-lock detection, route/interruption notices, and sample-mode fallback.

## Owner Decisions Required

- Final bundle identifier.
- Apple Team ID.
- Signing certificates/profiles.
- App Store Connect app record.
- Marketing version and build-number strategy.
- Display name and subtitle.
- Final app icon artwork (a brass tuning-fork placeholder is in place; replace with brand artwork).
- Category, keywords, description, screenshots, app previews.
- Support URL/email.
- Privacy Policy public URL and legal controller identity.
- Terms URL/text owner approval.
- Copyright/rights owner.
- Export compliance answer.
- Age rating and children/school/minor-data decision.
- Review account or demo-mode instructions.

## Provider Configuration Required

- Sign in with Apple capability/entitlement.
- Apple Services ID if using web OAuth with Supabase.
- Supabase Apple provider configuration.
- Supabase redirect allowlist for web and native callbacks.
- Production API/Auth environment for native app.

## Not Yet Complete

- Signed archive validation/export.
- App Store Connect upload/TestFlight.
- Third-party SDK privacy signature/manifest audit after final dependencies are pinned.
- Required-reason API final audit after adding production Supabase Swift client.
- Physical-device microphone validation.
- Physical-device validation of the local live microphone path with real brass input.
- Physical-device metronome click-bleed, haptic, route, speaker, headphone, and timing validation.
- Physical-device Files/Photos score import validation.
- Native camera score scanner/VisionKit flow.
- Owner/legal metadata.
