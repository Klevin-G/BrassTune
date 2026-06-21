# Web Native Parity Contract

Updated: 2026-06-20 UTC.

| Feature | Web Status | Native Status | Current Release Claim |
|---|---|---|---|
| Home | Complete enough for closed-beta web. | Visual shell exists. | Web closed-beta candidate; native visual parity not final. |
| Practice tuner | Guest demo and mic paths exist with recording/review. | Fixture-backed simulator practice shell. | Native is test/demo scope until real API/audio parity and physical-device mic pass. |
| Metronome | Added `/metronome` with Web Audio scheduler, count-in, subdivisions, signatures, ramp, mute, and timing stats. | Deferred. | Web feature exists; accuracy/bleed claims require timing/device validation. |
| Sessions | Web list/review routes exist with guest fallback improvements. | Fixture/session surfaces exist. | Web beta surface; native not functionally equivalent. |
| Review | Web recovery from missing sessions added. | Fixture-backed review. | Native review is test-only. |
| Analytics | Web route now exposes API failure state. | Fixture analytics. | Web beta surface; native not production-equivalent. |
| Coach | Web route now exposes API failure state. | Fixture guidance. | Web beta surface; native not production-equivalent. |
| Ensemble | Web local/server authorization is partially covered. | Fixture/shell scope. | Teacher/student live personas remain beta follow-up. |
| Score Practice | Added `/practice/score` with PDF/image/camera import, preview, confirmation, and local storage. | Deferred. | Web beta feature with explicit OMR/native scanner caveats. |
| Auth | Web guest-disabled state and provider-gated UI improved. | Keychain/auth scaffold only. | Live provider tests required for any account-readiness claim. |
| Settings | Web export/delete/guest data behavior improved. | Settings/data surfaces exist. | Account deletion needs disposable live-provider verification. |
| Export/delete | Backend/user flows covered locally; guest export fixed. | Native fixture export surfaces. | Live storage/identity deletion remains blocked. |
| Legal/support | Web surfaces exist. | Native links/surfaces exist. | Owner/legal final URLs and App Store metadata remain. |

## Contract Rules

- Do not call native complete when it only passes simulator fixture tests.
- Do not claim score-following, printed-note verification, or OMR accuracy unless the score interpretation and alignment confidence gates are implemented and tested.
- Do not use web success as Apple readiness evidence. Apple readiness needs signed archive, TestFlight/App Store Connect, privacy/legal metadata, and physical-device evidence.
- Web and native status must be reported separately in final release notes.
