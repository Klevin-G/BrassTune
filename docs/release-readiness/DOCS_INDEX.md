# Release Readiness Docs Index

Updated: 2026-07-24. Candidate source revision: `PENDING_FINAL_SHA`.

## Current decision

Local implementation evidence is strong, but this is **not deployed or released**. Local web, backend, Swift, simulator, audit, and independent-review gates pass, and linked Supabase migrations match through `20260724072904`. The committed SHA still requires direct same-SHA Render/Vercel deployments and hosted smoke. GitHub Actions is disabled and must not be used.

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
