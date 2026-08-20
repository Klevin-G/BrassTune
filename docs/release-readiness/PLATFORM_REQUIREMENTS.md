# Platform Requirements

Updated: 2026-08-04 UTC. Primary-source links are included for traceability; this document records the current verified boundaries, not deployment approval.

## Apple

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Apps need accurate metadata, working demo access, privacy compliance, and no misleading claims. | Release docs now avoid full readiness claims and keep demo/provider blockers explicit. | App Store Connect metadata, demo account or demo-mode instructions, and owner/legal signoff remain. |
| [Account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) | Account-creation apps must let users initiate deletion in app. | Web/native account lifecycle surfaces exist; web export/delete tests exist locally. | Live Supabase identity/storage deletion still needs disposable-provider verification. |
| [Cocoa keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html) | Camera and microphone access require purpose strings. | Native microphone usage description is configured. | Native score scanner/camera flow and final camera purpose string are not complete. |
| [VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) | Native document scanning should use system document camera where available. | Native scanner is documented as deferred. | Implement VisionKit scan, fallback paths, tests, and purpose-string review. |
| [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) | App and SDK privacy practices and required-reason APIs must be declared. | `PrivacyInfo.xcprivacy` records linked email, user ID, and user content; local-only raw microphone capture is not declared as collected. | Final SDK/privacy audit and App Store Connect answer reconciliation after a signed candidate is available. |
| [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) | Apple sign-in needs entitlement/provider configuration. | Native Apple controls and production/`.dev` capabilities are enabled. A physical flow reached AuthKit/Continue but stopped at Face ID; no callback or session was observed. | Complete the physical Apple callback/session. Web Apple additionally requires a Services ID and rotating web secret before configuration and lifecycle validation. |
| [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) | TestFlight requires App Store Connect app record and uploaded signed build. | Simulator builds/tests are documented. | Signed archive, upload, groups, feedback process, and export logs are missing. |

## Google Identity

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [GIS web button](https://developers.google.com/identity/gsi/web/guides/display-button) and [branding](https://developers.google.com/identity/branding-guidelines) | Google sign-in buttons and copy must follow branding rules. | Production web Google sign-in, session restoration, and sign-out passed with an authorized ordinary test identity. | Retain branded UI review and verify failure/cancel, refresh/expiry, and exact deployed revision in a future release check. |
| [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating) | Native Google auth requires configured client IDs and callback handling. | Native Google completed once on a physical `.dev` build: callback, cold restore, sign-out, and signed-out relaunch. | Repeat against the intended release candidate before claiming production-native lifecycle acceptance. |

## Supabase

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [Google auth](https://supabase.com/docs/guides/auth/social-login/auth-google), [Apple auth](https://supabase.com/docs/guides/auth/social-login/auth-apple), [redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls) | Providers and redirects must be explicitly configured. | Native Apple/Google controls are enabled; Google lifecycle evidence exists for physical `.dev` and production web. No Supabase provider toggle, credential, config, or schema change was made during this validation. | Native Apple callback/session is blocked at Face ID. Web Apple is unavailable without a Services ID and rotating web secret; retain narrow redirects and run its lifecycle later. |
| [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) | Exposed tables require RLS and ownership policies. | Earlier Supabase baseline documented RLS enabled and public helper grant locked down. | Re-run advisors and drift checks after any migration/provider change. |

## Hosting And Browser APIs

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [Vercel rewrites](https://vercel.com/docs/routing/rewrites), [deployment protection](https://vercel.com/docs/deployment-protection), [headers](https://vercel.com/docs/headers), [vercel.json](https://vercel.com/docs/project-configuration/vercel-json) | Frontend routing, preview protection, and headers need explicit configuration. | `.vercel/repo.json` links project directory `frontend`; preview protection is documented. | Strict content smoke must run after production deploy. |
| [Render free services](https://render.com/docs/free), [deploy hooks](https://render.com/docs/deploy-hooks), [deploys](https://render.com/docs/deploys) | Free services can spin down; deploys should be verified by exact commit. | Keepalive is documented as a closed-beta helper, not uptime. | Paid always-on service/alerts for public beta. |
| [getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia), [MediaRecorder support](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/isTypeSupported_static), [AudioWorklet](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Using_AudioWorklet), [Web Audio scheduling](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Advanced_techniques) | Mic/camera/audio features need permissions, capability checks, and user gestures. | Score camera uses `getUserMedia`; metronome starts from user gesture and uses `AudioContext.currentTime`. | AudioWorklet, long-run timing, and physical-device validation remain. |
| [PDF.js examples](https://mozilla.github.io/pdf.js/examples/) | Robust PDF page rendering needs a dedicated renderer if beyond browser iframe preview. | Current score route previews PDFs without bundled PDF.js. | Add lazy PDF.js only if reader features need custom rendering. |

## Storage and privacy release boundary

A synthetic signed-in recording/session persisted, but playback/export failed when the backend redirected to cross-origin Storage. The browser's privacy-safe followed fetch raised `TypeError`; a manual request encountered an opaque redirect. The source for signed-in **Delete saved audio** and a backend same-origin proxy repair are local-only and not deployed. Before a release claim, deploy the repair and verify deletion, final object absence, account deletion, and live cross-user denial with non-personal test accounts. One synthetic recording remains; its removal is also unverified.
