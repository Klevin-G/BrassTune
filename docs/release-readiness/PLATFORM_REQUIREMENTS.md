# Platform Requirements
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23 UTC. Primary-source links are included for traceability; current deployment/signing/submission evidence is separated from remaining lifecycle and hardware gaps.

## Apple

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Apps need accurate metadata, working demo access, privacy compliance, and no misleading claims. | Version `1.0.1` build 7 is submitted and Waiting for Review with guest access/reviewer notes and published privacy disclosure. | App Review outcome and continuing accuracy of future metadata/builds. |
| [Account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) | Account-creation apps must let users initiate deletion in app. | Web/native account lifecycle surfaces exist; web export/delete tests exist locally. | Live Supabase identity/storage deletion still needs disposable-provider verification. |
| [Cocoa keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html) | Camera and microphone access require purpose strings. | Native microphone usage description is configured. | Native score scanner/camera flow and final camera purpose string are not complete. |
| [VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) | Native document scanning should use system document camera where available. | Native scanner is documented as deferred. | Implement VisionKit scan, fallback paths, tests, and purpose-string review. |
| [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) | App and SDK privacy practices and required-reason APIs must be declared. | `PrivacyInfo.xcprivacy` and published App Store privacy include linked email, user ID, other user content, Name, and Photos or Videos for App Functionality without tracking. Build 7 archive/privacy checks passed. | Reconcile future signed builds and behavior; complete unattended lifecycle acceptance. |
| [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) | Apple sign-in needs entitlement/provider configuration. | Native and web Apple provider configuration, Services ID, callback, and rotating web secret are deployed. | Untested live lifecycle paths remain distinct from deployed configuration. |
| [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) | TestFlight requires App Store Connect app record and uploaded signed build. | Build `1.0.1 (7)` archive/export/upload succeeded and TestFlight is Ready to Submit; App Store version is Waiting for Review. | Review outcome and any future beta-group/feedback process. |

## Google Identity

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [GIS web button](https://developers.google.com/identity/gsi/web/guides/display-button) and [branding](https://developers.google.com/identity/branding-guidelines) | Google sign-in buttons and copy must follow branding rules. | Production web Google sign-in, session restoration, and sign-out passed with an authorized ordinary test identity. | Retain branded UI review and verify failure/cancel, refresh/expiry, and exact deployed revision in a future release check. |
| [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating) | Native Google auth requires configured client IDs and callback handling. | Native Google configuration is deployed; prior physical `.dev` lifecycle evidence exists. | Release-candidate live lifecycle remains untested. |

## Supabase

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [Google auth](https://supabase.com/docs/guides/auth/social-login/auth-google), [Apple auth](https://supabase.com/docs/guides/auth/social-login/auth-apple), [redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls) | Providers and redirects must be explicitly configured. | Apple/Google providers, native callbacks, web Apple Services ID/secret, and narrow redirects are configured and deployed. | Retain configuration drift checks and separately test unexercised provider lifecycles. |
| [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) | Exposed tables require RLS and ownership policies. | Earlier Supabase baseline documented RLS enabled and public helper grant locked down. | Re-run advisors and drift checks after any migration/provider change. |

## Hosting And Browser APIs

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [Vercel rewrites](https://vercel.com/docs/routing/rewrites), [deployment protection](https://vercel.com/docs/deployment-protection), [headers](https://vercel.com/docs/headers), [vercel.json](https://vercel.com/docs/project-configuration/vercel-json) | Frontend routing, preview protection, and headers need explicit configuration. | Vercel and Render serve implementation `98fd1d9`; strict hosted Playwright passed `50/50`. | Retain exact-SHA smoke on future deployment changes. |
| [Render free services](https://render.com/docs/free), [deploy hooks](https://render.com/docs/deploy-hooks), [deploys](https://render.com/docs/deploys) | Free services can spin down; deploys should be verified by exact commit. | Keepalive is documented as a closed-beta helper, not uptime. | Paid always-on service/alerts for public beta. |
| [getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia), [MediaRecorder support](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/isTypeSupported_static), [AudioWorklet](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Using_AudioWorklet), [Web Audio scheduling](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Advanced_techniques) | Mic/camera/audio features need permissions, capability checks, and user gestures. | Score camera uses `getUserMedia`; metronome starts from user gesture and uses `AudioContext.currentTime`. | AudioWorklet, long-run timing, and physical-device validation remain. |
| [PDF.js examples](https://mozilla.github.io/pdf.js/examples/) | Robust PDF page rendering needs a dedicated renderer if beyond browser iframe preview. | Current score route previews PDFs without bundled PDF.js. | Add lazy PDF.js only if reader features need custom rendering. |

## Storage and privacy release boundary

The deployed same-origin audio proxy/delete repair is covered by strict hosted Playwright. Before a lifecycle claim, verify with disposable accounts: playback/export, deletion, final object absence, account deletion, and live cross-user denial. Hosted browser coverage does not replace those account-specific checks.
