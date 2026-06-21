# Post-Release Backlog

Updated: 2026-06-21T00:13:54Z

These items are useful but are not allowed to expand the locked release scope unless they reveal a P0/P1 security, data-loss, critical-journey, or hard release-gate failure.

| Item | Area | Notes |
|---|---|---|
| MusicXML/OMR printed-note comparison | Score Practice | Keep disabled until score interpretation and alignment thresholds are documented and user-confirmed. |
| Automatic score following | Score Practice | Current release can support manual page/time markers without claiming automatic alignment. |
| Advanced crop/dewarp tools | Score Practice | Helpful for scan quality but not required for local PDF/image preview and manual practice. |
| Acoustic metronome timing/bleed lab | Audio | Current web UI exposes scheduled queue stats only; physical-device acoustic validation remains separate. |
| Native physical-device audio proof | iOS | Simulator tests cannot prove microphone quality, audio route behavior, or bleed rejection. |
| Full native web-feature parity polish | iOS | Needed before native release claims, but web beta release should not claim App Store readiness. |
| Account-linking ceremony | Auth | Email-only linking is blocked; explicit user-controlled identity linking can be designed after beta. |
| Long-running deletion worker UI | Account lifecycle | The backend now records retryable deletion jobs; operator UI and scheduled worker can follow. |
