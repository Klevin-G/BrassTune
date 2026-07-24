# iOS Simulator Report

Updated: 2026-07-24. Candidate source revision: `PENDING_FINAL_SHA`.

## Verified simulator evidence

| Check | Result |
|---|---|
| Swift domain package | `3/3` passed |
| App unit tests | `145/145` passed on iPhone simulator |
| App UI tests | `20/20` passed on iPhone simulator |
| iPad first-run and main journey | Build/launch visually inspected; main adaptive journey passed |
| Class privacy follow-up | Targeted class journey passed on iPhone and iPad after invitation privacy copy |
| Localization verifier | 660 static keys, 718 catalog entries, 12 locales, 0 issues |
| Debug build | Passed on dynamically discovered iPhone and iPad simulators |

## Implemented native scope

The SwiftUI app provides full-screen welcome/auth, tuner and focused practice, warm-up/packs/play-along tools, goals/reflections, classes with aggregate-only reports, localized strings for 12 locales, Keychain-backed auth, Google PKCE browser auth, Apple nonce/token auth, and an AVAudioEngine microphone path. Sign in/Create account remain discoverable from welcome and Classes, authentication surfaces clearly expose Apple and Google with live-availability gating, and first-run/status banners no longer displace iPad navigation.

## Limits

- All evidence above is unsigned simulator evidence.
- Google/Apple live-provider completion, physical microphone/brass accuracy, route changes, Bluetooth/wired input, interruption behavior, accessibility with assistive technology, signing, archive validation, TestFlight, and App Store acceptance remain separate gates.
- Apple provider configuration requires Apple Developer credentials and Supabase enablement.
