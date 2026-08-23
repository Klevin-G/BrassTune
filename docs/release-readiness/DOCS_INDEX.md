# Release Readiness Docs Index
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. Build `1.0.1 (7)` is the latest documented App Store
candidate. Its native archive source `d371100` is distinct from deployed
web/backend implementation `98fd1d9`.

Project attribution is maintained in [Credits](../CREDITS.md): Kelvin Guo, Arya Salem.

## Current decision

Build `1.0.1 (7)` is uploaded, TestFlight **Ready to Submit**, attached to
version `1.0.1`, and submitted as **Waiting for Review** with manual release.
That is submission evidence, not approval or release evidence. Build-3/5
reports remain historical evidence only. Hosted Vercel/Render strict Playwright
passed `50/50` for implementation `98fd1d9`; physical unattended checks retain
their documented route/accessibility limits.

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
| Current build-7 submission/state | `FINAL_REPORT.md`, `APP_STORE_CHECKLIST.md`, `TESTFLIGHT_UPLOAD.md`, `TESTFLIGHT_HANDOFF.md` |
| Historical build-5 App Store response/state | `APP_REVIEW_RESPONSE_2026-08-14.md` (version `1.0.0 (5)`, not the current build-7 submission) |
| Historical build-3 physical/signing evidence | `NATIVE_PHYSICAL_RELEASE_REPORT_2026-08-06.md` |
| Third-party button-art provenance | `../../THIRD_PARTY_ASSETS.md` |
| Canonical project attribution | `../CREDITS.md` |
| Physical-device automation prompt | `IPHONE_AUTOMATION_PROMPT.md` |
| Retention, accessibility, and seller-name rationale | `PRODUCT_STEWARDSHIP_RATIONALE.md` |

## Evidence rule

Always tie claims to the revision and environment actually tested. Local browser, simulator, and unit evidence does not prove a deployed revision, live OAuth completion, physical microphone behavior, signing, TestFlight, or App Store acceptance.
