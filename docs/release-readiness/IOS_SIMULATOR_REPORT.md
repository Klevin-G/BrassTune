# iOS Simulator Report
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. The deployed release implementation is `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`; the native follow-up archive source is distinct, `d371100` on `arya/final-physical-release-20260823`. Do not substitute any future merge SHA for either identity.

## Verified simulator evidence

| Check | Result |
|---|---|
| Swift domain package | `12/12` passed |
| App unit tests | `272/272` passed |
| iPad first-run and main journey | Build/launch visually inspected; main adaptive journey passed |
| Class privacy follow-up | Targeted class journey passed on iPhone and iPad after invitation privacy copy |
| Localization verifier | 889 static keys, 1,027 catalog entries, 12 locales, 0 violations |
| Debug/Release simulator build | Passed; Release binary includes `@executable_path/Frameworks` for the embedded Swift package |
| Manual simulator walkthrough | Gateway hierarchy, five-step tutorial, always-on Tuner plus explicit Record, first-play Metronome, More buttons, Credits, Privacy, and Support were rendered and inspected with XcodeBuildMCP |

## Implemented native scope

The SwiftUI app provides full-screen welcome/auth, tuner and focused practice, warm-up/packs/play-along tools, goals/reflections, classes with aggregate-only reports, localized strings for 12 locales, Keychain-backed auth, Google PKCE browser auth, Apple nonce/token auth, and an AVAudioEngine microphone path. Sign in/Create account remain discoverable from welcome and Classes, authentication surfaces clearly expose Apple and Google with live-availability gating, and first-run/status banners no longer displace iPad navigation.

## Connected-device boundary

The connected iPhone passed the automation canary `1/1` in 14.058 s, strict accessibility `1/1` in 79.342 s, and final standard suite `26/26` in 774.943 s. Expanded audio stress passed `1/1` in 511.046 s with 20 tuner listener reinstall cycles, three explicit take/save cycles, remaining tools, and tab switching. The earlier sustained 120-BPM physical check passed `1/1` in about 209.963 s. Broad XCUI detector findings were audited as false positives using screenshots/token ratios. This evidence remains bounded to exercised routes and does not establish calibrated brass/acoustic accuracy or accessory-route behavior.

## Limits

- The simulator-table and simulator-scope evidence above is unsigned simulator evidence; the separate Connected-device boundary records signed physical execution with its stated limits.
- Calibrated brass/acoustic accuracy; AirPlay/HomePod, Bluetooth, and wired routes; Files/Photos preseeded fixtures; timer/media-reset operator prerequisites; and full assistive-technology/iPad validation remain unavailable gates. App Review acceptance remains external.
- Apple provider configuration requires Apple Developer credentials and Supabase enablement.
