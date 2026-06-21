# Platform Requirements

Updated: 2026-06-20 UTC. Primary sources were checked during this run; links are included for traceability.

## Apple

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Apps need accurate metadata, working demo access, privacy compliance, and no misleading claims. | Release docs now avoid full readiness claims and keep demo/provider blockers explicit. | App Store Connect metadata, demo account or demo-mode instructions, and owner/legal signoff remain. |
| [Account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/) | Account-creation apps must let users initiate deletion in app. | Web/native account lifecycle surfaces exist; web export/delete tests exist locally. | Live Supabase identity/storage deletion still needs disposable-provider verification. |
| [Cocoa keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html) | Camera and microphone access require purpose strings. | Native microphone usage description is configured. | Native score scanner/camera flow and final camera purpose string are not complete. |
| [VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) | Native document scanning should use system document camera where available. | Native scanner is documented as deferred. | Implement VisionKit scan, fallback paths, tests, and purpose-string review. |
| [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) | App and SDK privacy practices and required-reason APIs must be declared. | `PrivacyInfo.xcprivacy` exists. | Final SDK/privacy audit after production native dependencies are pinned. |
| [Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple) | Apple sign-in needs entitlement/provider configuration. | Web UI exposes Apple sign-in only when auth is configured. | Apple developer capability, Supabase Apple provider, and native callback setup remain. |
| [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) | TestFlight requires App Store Connect app record and uploaded signed build. | Simulator builds/tests are documented. | Signed archive, upload, groups, feedback process, and export logs are missing. |

## Google Identity

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [GIS web button](https://developers.google.com/identity/gsi/web/guides/display-button) and [branding](https://developers.google.com/identity/branding-guidelines) | Google sign-in buttons and copy must follow branding rules. | Auth-disabled builds no longer show unavailable provider paths. | Google provider UI should be reviewed only after provider setup is added. |
| [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating) | Native Google auth requires configured client IDs and callback handling. | Native auth remains provider-blocked. | Add provider config and native auth tests before claiming parity. |

## Supabase

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [Google auth](https://supabase.com/docs/guides/auth/social-login/auth-google), [Apple auth](https://supabase.com/docs/guides/auth/social-login/auth-apple), [redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls) | Providers and redirects must be explicitly configured. | Frontend/backend now fail safer when provider config is absent. | Disposable live-provider tests are required. |
| [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) | Exposed tables require RLS and ownership policies. | Earlier Supabase baseline documented RLS enabled and public helper grant locked down. | Re-run advisors and drift checks after any migration/provider change. |

## Hosting And Browser APIs

| Source | Requirement | BrassTune Evidence | Remaining Gap |
|---|---|---|---|
| [Vercel rewrites](https://vercel.com/docs/routing/rewrites), [deployment protection](https://vercel.com/docs/deployment-protection), [headers](https://vercel.com/docs/headers), [vercel.json](https://vercel.com/docs/project-configuration/vercel-json) | Frontend routing, preview protection, and headers need explicit configuration. | `.vercel/repo.json` links project directory `frontend`; preview protection is documented. | Strict content smoke must run after production deploy. |
| [Render free services](https://render.com/docs/free), [deploy hooks](https://render.com/docs/deploy-hooks), [deploys](https://render.com/docs/deploys) | Free services can spin down; deploys should be verified by exact commit. | Keepalive is documented as a closed-beta helper, not uptime. | Paid always-on service/alerts for public beta. |
| [getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia), [MediaRecorder support](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder/isTypeSupported_static), [AudioWorklet](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Using_AudioWorklet), [Web Audio scheduling](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Advanced_techniques) | Mic/camera/audio features need permissions, capability checks, and user gestures. | Score camera uses `getUserMedia`; metronome starts from user gesture and uses `AudioContext.currentTime`. | AudioWorklet, long-run timing, and physical-device validation remain. |
| [PDF.js examples](https://mozilla.github.io/pdf.js/examples/) | Robust PDF page rendering needs a dedicated renderer if beyond browser iframe preview. | Current score route previews PDFs without bundled PDF.js. | Add lazy PDF.js only if reader features need custom rendering. |
