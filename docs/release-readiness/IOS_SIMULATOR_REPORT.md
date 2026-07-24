# iOS Simulator Report

Updated: 2026-07-23. Candidate source revision: `7c12b15`.

## Verified simulator evidence

| Check | Result |
|---|---|
| Swift domain package | `3/3` passed |
| App unit tests | `139/139` passed |
| App UI tests | `15/15` passed |
| Welcome/auth follow-up | `4/4` affected UI checks passed after `7c12b15` |
| Debug build | Passed on dynamically discovered iPhone and iPad simulators |
| Release build | Passed on dynamically discovered iPhone simulator |
| Build diagnostics | Zero warnings reported for the current Debug/Release simulator builds |

## Implemented native scope

The SwiftUI app provides full-screen welcome/auth, tuner and focused practice, warm-up/packs/play-along tools, goals/reflections, classes with aggregate-only reports, localized strings for 12 locales, Keychain-backed auth, Google PKCE browser auth, Apple nonce/token auth, and an AVAudioEngine microphone path. The `7c12b15` follow-up keeps Sign in/Create account discoverable from welcome, opens the complete auth sheet from Classes, localizes Google text, and uses an exact-pixel crop of official Google artwork without recoloring or redrawing.

## Limits

- All evidence above is unsigned simulator evidence.
- Google/Apple live-provider completion, physical microphone/brass accuracy, route changes, Bluetooth/wired input, interruption behavior, accessibility with assistive technology, signing, archive validation, TestFlight, and App Store acceptance remain separate gates.
- Apple provider configuration requires Apple Developer credentials and Supabase enablement.
