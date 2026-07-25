# Apple App Store Checklist

Updated: 2026-07-24. This is a preparation checklist, not an App Store readiness decision.

## Current local and simulator evidence

- The current native simulator build/run completed with zero warnings and errors; native unit tests passed `158` tests and all 20 UI scenarios passed in bounded batches. This remains unsigned simulator evidence.
- The release script now fails closed on the Apple Team ID, bundle ID, public production Supabase URL, and public publishable key, and archives with `CODE_SIGNING_ALLOWED=YES`.
- The target includes native auth, practice, class, localization, privacy, export, and account-deletion surfaces.

## Required before submission

- Configure Apple Developer team, bundle identifier, signing, version/build policy, and App Store Connect record.
- Native Apple sign-in and Google controls are intentionally hidden. Before offering native third-party sign-in, configure Sign in with Apple App ID/Services ID/key and the Supabase Apple provider, then re-enable Apple entitlement/control together with Google presentation only after live dual-provider verification.
- Test a signed archive and TestFlight build on physical iPhone/iPad, including Ring/Silent behavior, microphone/brass input, Bluetooth/audio routes and interruptions, local recording deletion/file protection, accessibility, localization, auth lifecycle, export/delete, and class privacy.
- Reconcile App Store Connect privacy answers with the signed build: native takes can be retained app-locally for listen-back but are not uploaded automatically; signed-in web takes upload on Stop through the authenticated backend/Supabase path; class reporting excludes recordings, reflection text, and private session detail. A limited set of authorized service administrators may access cloud account/session/audio data only for security, support, abuse investigation, or service operation.
- Finalize icon, export compliance, age rating, review access, and metadata. Native legal/support actions link to the published HTTPS privacy, terms, and support pages.

Simulator results do not prove signed archive, physical audio, TestFlight, App Store acceptance, or Apple provider availability.
