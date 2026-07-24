# Release Readiness Docs Index

Updated: 2026-07-23. Candidate source revision: `7c12b15` (includes `428a123`, `4f742a0`, and `cc3a8dc`).

## Current decision

Local implementation evidence is strong, but this is **not deployed or released**. The duplicate-identity PII race is fixed and the full backend suite now passes; the merged SHA still requires self-hosted CI, Supabase migration/config rollout, exact-SHA Render/Vercel deploys, and hosted smoke.

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
