# iOS Simulator Report
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. The current source is merged on `main` at `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`; historical revision references do not bind this candidate.

## Verified simulator evidence

| Check | Result |
|---|---|
| Swift domain package | `12/12` passed |
| App unit tests | `270/270` passed on iPhone 17 Pro / iOS 26.2 simulator after the physical-signing test update |
| App UI tests | Exact-current monolithic suite `26/26`, zero failures/skips, 790.802 test seconds on iPhone 17 Pro / iOS 26.5 simulator |
| iPad first-run and main journey | Build/launch visually inspected; main adaptive journey passed |
| Class privacy follow-up | Targeted class journey passed on iPhone and iPad after invitation privacy copy |
| Localization verifier | 890 static keys, 1,027 catalog entries, 12 locales, 0 issues |
| Debug/Release simulator build | Passed; Release binary includes `@executable_path/Frameworks` for the embedded Swift package |
| Manual simulator walkthrough | Gateway hierarchy, five-step tutorial, always-on Tuner plus explicit Record, first-play Metronome, More buttons, Credits, Privacy, and Support were rendered and inspected with XcodeBuildMCP |

## Implemented native scope

The SwiftUI app provides full-screen welcome/auth, tuner and focused practice, warm-up/packs/play-along tools, goals/reflections, classes with aggregate-only reports, localized strings for 12 locales, Keychain-backed auth, Google PKCE browser auth, Apple nonce/token auth, and an AVAudioEngine microphone path. Sign in/Create account remain discoverable from welcome and Classes, authentication surfaces clearly expose Apple and Google with live-availability gating, and first-run/status banners no longer displace iPad navigation.

## Connected-device boundary

The signed physical app-unit suite passed `259`, skipped `11` source-tree-only audits, and failed `0` on the connected iPhone 15 Pro Max / iOS 26.6.1 after adding `@executable_path/Frameworks` to the app runtime search path. The physical UI runner installed, but iOS timed out enabling UI automation before any scenario executed; it is neither a pass nor an app-test failure. This does not assess microphone/brass accuracy or audible metronome/drone behavior.

## Limits

- All evidence above is unsigned simulator evidence.
- Google/Apple live-provider completion, physical microphone/brass accuracy, route changes, Bluetooth/wired input, interruption behavior, accessibility with assistive technology, processed-build physical validation, and App Store acceptance remain separate gates.
- Apple provider configuration requires Apple Developer credentials and Supabase enablement.
