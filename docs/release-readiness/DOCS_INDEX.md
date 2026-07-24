# Release Readiness Docs Index

Updated: 2026-07-24. Deployed application revision: `26683c82c42839016383fb9cab676c9a35d554ca`.

## Current decision

The web/backend candidate is deployed and hosted smoke passes on the recorded application revision. Local web, backend, Swift, simulator, audit, and independent-review gates pass, linked Supabase migrations match through `20260724072904`, and 44 unique professor outreach drafts are prepared in the designated Gmail account. GitHub Actions remained disabled and was not used. Apple/provider signing, physical-device audio, disposable-account lifecycle, and human language QA remain separate gates.

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
| Third-party button-art provenance | `../../THIRD_PARTY_ASSETS.md` |

## Evidence rule

Always tie claims to the revision and environment actually tested. Local browser, simulator, and unit evidence does not prove a deployed revision, live OAuth completion, physical microphone behavior, signing, TestFlight, or App Store acceptance.
