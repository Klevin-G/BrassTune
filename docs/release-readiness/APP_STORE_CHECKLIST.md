# Apple App Store Checklist

Updated: 2026-07-23. This is a preparation checklist, not an App Store readiness decision.

## Current simulator evidence

- Swift Core `3/3`, native units `139/139`, UI tests `15/15`.
- Debug iPhone/iPad and Release iPhone simulator builds passed with zero warnings.
- The target includes native auth, practice, class, localization, privacy, export, and account-deletion surfaces.

## Required before submission

- Configure Apple Developer team, bundle identifier, Sign in with Apple App ID/Services ID/key, Supabase Apple provider, signing, version/build policy, and App Store Connect record.
- Test a signed archive and TestFlight build on physical iPhone/iPad, including microphone/brass input, audio routes/interruption, accessibility, localization, auth lifecycle, export/delete, and class privacy.
- Finalize icon, support/legal URLs, privacy disclosures, export compliance, age rating, review access, and metadata.

Simulator results do not prove signed archive, physical audio, TestFlight, App Store acceptance, or Apple provider availability.
