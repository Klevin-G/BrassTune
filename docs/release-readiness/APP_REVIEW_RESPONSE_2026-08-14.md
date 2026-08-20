# App Review response — Guideline 2.1 Information Needed

Status updated 2026-08-15 America/Chicago. Live App Store Connect is authoritative over older release documents.

## Candidate

- App: BrassTune
- Bundle: `com.aryasalem.BrassTune`
- Version/build: `1.0.0 (5)`
- App Store Connect: Build 5 selected on the existing iOS 1.0 submission and resubmitted on 2026-08-15 at 1:44 PM America/Chicago. Both the submission and item visibly reported `Waiting for Review`.
- Physical device: iPhone 15 Pro Max (`iPhone16,2`). Latest-OS recording target: iOS 26.6.
- Persistent reviewer credentials are stored only in App Store Connect Sign-In Information. They must not be copied into Git or this document.

## App Review Information Notes

Keep the saved note below under App Store Connect's 4,000-byte limit.

> Build 1.0.0 (5). Physical-device recording attached: BrassTune-1.0.0-5-iPhone15ProMax-iOS26.6-AppReviewWalkthrough-Verified.mp4. It was captured from the wired iPhone screen and speaker on an iPhone 15 Pro Max (iPhone16,2) running iOS 26.6. The single attached video presents two back-to-back physical takes, with one cut between successful self-registration and the later sign-in/account-deletion continuation.
>
> Pre-submission device/OS coverage: physical iPhone 15 Pro Max on iOS 26.6; iPhone 17 Pro simulator on iOS 26.5; and iPad Pro 13-inch (M5) simulator on iOS 26.5. The physical recording uses the installed signed Build 5.
>
> BrassTune is a free practice companion for brass players. Its value is one focused place for a live tuner, guided warm-ups and scales, a metronome, drone/reference-tone and interval tools, local score practice, and practice-progress review. It is not a medical device or diagnostic service.
>
> Core review requires no account: launch → Continue as Guest → select an instrument → Start Practicing. No special hardware, server setup, sample file, invitation, or location is required. Score Practice can optionally import a reviewer-owned PDF or image from Files or Photos; BrassTune does not provide or distribute third-party scores.
>
> The persistent email/password reviewer account is populated in the Sign-In Information fields above. From a guest session: More → Settings → Sign in. To review self-registration, choose Create account; BrassTune then displays the email-confirmation state. To delete a signed-in account: More → Settings → Your data → Delete account → confirm Delete account. The app returns to its signed-out Settings state and clears local account data on that device.
>
> Microphone access is requested only when the reviewer starts Tuner or a microphone-assisted Scale. The metronome and visual practice paths do not require microphone access. Files and Photos pickers appear only after the reviewer explicitly chooses an import source. The app does not request camera access.
>
> There is no paid content, in-app purchase, subscription, advertising, or purchase flow in this build. There is no public user-generated-content feed, public posting, messaging, user reporting, or blocking feature.
>
> External services: Supabase provides optional account authentication/account data; the BrassTune API is hosted on Render for signed-in/online functions; Apple and Google are optional sign-in providers; the linked support/legal website is hosted on Vercel. Core guest practice tools remain available locally without account creation. There are no payment, advertising, AI-generation, or third-party content-provider services.
>
> BrassTune contains no region-gated code or region-specific content; storefront availability follows the territories selected in App Store Connect. The app ships no regulated material or licensed third-party scores/media. Users may optionally import files they own or are authorized to use.

## Reply to App Review

> Hello App Review,
>
> We addressed the Guideline 2.1 information request with corrected Build 1.0.0 (5). App Review Information now includes a persistent demo login, complete setup/deletion/permission/service/region/content details, and an attached physical-device walkthrough covering launch, guest and core-practice use, self-registration, account sign-in, and account deletion on iPhone 15 Pro Max with iOS 26.6. The recording also shows microphone permission behavior. The app has no paid content or public UGC/report/block flows.
>
> Thank you.

## Evidence and submission state

- Final automated source verification: 253 native tests, 12 Swift package tests, and seven focused metronome tests passed.
- Independent metronome and signup-decoder reviews: approved.
- Signed archive, App Store export, Release Testing export, upload log, and device install JSON are under `~/Library/Application Support/BrassTune/ReleaseEvidence/AppStoreCandidate-2026-08-15-Build5/`.
- The latest-OS physical walkthrough is complete and the final normalized recording passes a full decode check. The verified MP4 was attached to App Review Information, the complete notes were saved, and the Resolution Center reply was sent.
- Build 5 replaced rejected Build 3 on submission `d6b5b557-84e9-4e46-b979-8263670fc18c`. App Store Connect confirmed `Waiting for Review` for both the submission and item on 2026-08-15 at 1:44 PM. This is resubmission evidence, not approval or release evidence.
- Haptic actuation, calibrated pitch accuracy, route coverage, and audio timing are not claimed from QuickTime capture.
