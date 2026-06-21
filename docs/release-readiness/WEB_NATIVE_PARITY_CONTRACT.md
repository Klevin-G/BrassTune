# Web Native Parity Contract

Updated: 2026-06-21T06:30:28Z

| Feature | Web Status | Native Status | Current Release Claim |
|---|---|---|---|
| Auth gateway | Production guest-first web gateway deployed. | Native auth-first gateway, session restoration, Continue as guest, email/password, reset, and Apple token exchange surfaces implemented. | Live provider lifecycle remains credential-gated. |
| Home | Web `/home` production surface deployed. | Native branded Home with five-tab clearance and local/account status. | Parity claim limited to repository UI behavior. |
| Practice tuner | Guest microphone and recording journeys deployed for web. | Normal native path uses `AVAudioSession`/`AVAudioEngine` tap and local recording; deterministic frames are UI-test-only. | Simulator proves repository behavior, not physical brass quality. |
| Metronome | Web Audio metronome deployed. | Native metronome settings, scheduler, click generation, persistence, and bleed messaging implemented. | Acoustic timing and bleed require hardware validation. |
| Sessions/review | Web local/cloud sessions deployed. | Native local sessions persist, review, playback retained files, export summaries, and delete files/metadata. | Cloud sync remains account/provider-gated. |
| Analytics/progress/coach | Web analytics surfaces deployed. | Native derives metrics and recommendations from recorded local sessions with insufficient-data states. | No generated focus notes are represented as measured facts. |
| Ensemble | Web teacher/student workflows deployed for web scope. | Native hides generated roster data and shows account-required/account-backed states. | Live memberships require account/provider data. |
| Score Practice | Web PDF/image/camera Score Practice deployed for web scope. | Native file/photo/camera import metadata, PDF page count, local markers, and review linkage implemented. | Printed-note comparison/OMR remains conservative and user-confirmed. |
| Themes | Web shared-token themes deployed. | Native generated tokens, six themes, Liquid Glass/fallback surfaces, and Settings/gateway selectors implemented. | Visual parity validated on simulator screenshot only. |
| Legal/support | Web public routes deployed. | Native Privacy, Terms, and Support surfaces implemented. | Owner/legal final wording remains external. |

## Contract Rules

- Do not use simulator evidence as physical microphone quality evidence.
- Do not claim App Store/TestFlight readiness without signing, archive, upload, metadata, and review evidence.
- Do not claim live Supabase/Google/Apple account readiness until disposable provider tests pass.
- Do not claim printed-note recognition unless score interpretation/alignment confidence gates are implemented and tested.
- Report web and native status separately in release notes.
