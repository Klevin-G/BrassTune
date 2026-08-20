# Release Readiness Docs Index

Updated: 2026-08-19. Build `1.0.0 (5)` is the latest documented App Store
candidate. Source-publication verification is separate from that signed binary.

## Current decision

Build `1.0.0 (5)` replaced rejected build 3 on the existing version 1.0
submission and was documented as **Waiting for Review** on 2026-08-15. That is
resubmission evidence, not approval or release evidence. Build-3 physical and
signing reports remain historical evidence only. Documented validation gaps
remain open, and web/backend/source-publication evidence remains separate.

## Primary documents

| Need | Source |
|---|---|
| Candidate decision and evidence | `FINAL_REPORT.md` |
| Reproducible local and release gates | `TEST_MATRIX.md` |
| Web/native behavior boundary | `WEB_NATIVE_PARITY_CONTRACT.md` |
| Privacy, data, and migration rollout | `SECURITY_PRIVACY.md` |
| OAuth provider state and setup | `AUTH_PROVIDERS.md`, `AUTH_PROVIDER_SETUP.md` |
| Human-only gates | `HUMAN_ACTIONS.md` |
| Post-merge sequence | `POST_MERGE_PRODUCTION_CHECKLIST.md` |
| Native simulator evidence | `IOS_SIMULATOR_REPORT.md` |
| Latest App Store response/state | `APP_REVIEW_RESPONSE_2026-08-14.md` |
| Historical build-3 physical/signing evidence | `NATIVE_PHYSICAL_RELEASE_REPORT_2026-08-06.md` |
| Third-party button-art provenance | `../../THIRD_PARTY_ASSETS.md` |

## Evidence rule

Always tie claims to the revision and environment actually tested. Local browser, simulator, and unit evidence does not prove a deployed revision, live OAuth completion, physical microphone behavior, signing, TestFlight, or App Store acceptance.
