# Release Readiness Docs Index

See [BrassTune 1.0.10 release evidence](BRASSTUNE_1_0_10.md) for the November 15 submission, signed artifacts, and validation.
The [welcome redesign and marketing website report](WELCOME_MARKETING_2026-10-12.md) documents build 19 and the pending website and account-recovery deployment gates.
The [October 6 Google sign-in follow-up](GOOGLE_AUTH_FOLLOWUP_2026-10-06.md) records the callback investigation on earlier builds.

Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-11-22. Historical native candidate: `1.0.3 (11)`. See
[September release QA](RELEASE_QA_2026-09-21.md) for that candidate's source, tests, and submission status.
[Native Google sign-in callback — 1.0.5 (15) physical evidence](GOOGLE_AUTH_CALLBACK_1_0_5_2026-09-29.md) for the historical installation observations and ordered device gate.

Project attribution is maintained in [Credits](../CREDITS.md): Kelvin Guo, Arya Salem.

## Historical September decision

Candidate `1.0.3 (11)` passed final native unit and targeted iPhone/iPad checks;
real Google sign-in and repeated audio stress passed on the USB phone. Archive,
export, and upload succeeded. Apple confirmed **Waiting for Review** with automatic
release after approval. The verified submission receipt is tracked in
[the current report](RELEASE_QA_2026-09-21.md). Build 10 is superseded.

## Historical August 24 decision

Build `1.0.1 (8)` is uploaded, TestFlight **Ready to Submit**, attached to
version `1.0.1`, and submission `308027b4-96ad-4171-bc83-faee57539cb6` is
approved and manually released. App Store Connect reports **Ready for
Distribution**. Product-page attribution credits Kelvin Guo first. The first
public lookup still returned version `1.0`, so storefront propagation remained
pending. Build-3/5 reports remain historical evidence only. Vercel and Render are Ready at
candidate `5acfa2e`; hosted smoke passed `45` with `5` strict capability skips.
Physical unattended checks retain their documented route/accessibility limits.

## Primary documents

| Need | Source |
|---|---|
| Latest submitted native release and validation | [BrassTune 1.0.10 release evidence](BRASSTUNE_1_0_10.md) |
| Build 17 signing, upload and source fingerprints | [iOS 1.0.6 artifact verification](IOS_10617_ARTIFACT_VERIFICATION_2026-10-08.md) |
| Current auth investigation and evidence | [October Google sign-in follow-up](GOOGLE_AUTH_FOLLOWUP_2026-10-06.md) |
| Historical September native candidate | [September release QA](RELEASE_QA_2026-09-21.md) |
| Historical combined release report | `FINAL_REPORT.md` |
| Reproducible local and release gates | `TEST_MATRIX.md` |
| Web/native behavior boundary | `WEB_NATIVE_PARITY_CONTRACT.md` |
| Privacy, data, and migration rollout | `SECURITY_PRIVACY.md` |
| OAuth provider state and setup | `AUTH_PROVIDERS.md`, `AUTH_PROVIDER_SETUP.md` |
| Human-only gates | `HUMAN_ACTIONS.md` |
| Post-merge sequence | `POST_MERGE_PRODUCTION_CHECKLIST.md` |
| Native simulator evidence | `IOS_SIMULATOR_REPORT.md` |
| Historical build-8 submission/state | `FINAL_REPORT.md`, `APP_STORE_CHECKLIST.md`, `TESTFLIGHT_UPLOAD.md`, `TESTFLIGHT_HANDOFF.md` |
| Historical build-5 App Store response/state | `APP_REVIEW_RESPONSE_2026-08-14.md` (version `1.0.0 (5)`, not the current build-8 submission) |
| Historical build-3 physical/signing evidence | `NATIVE_PHYSICAL_RELEASE_REPORT_2026-08-06.md` |
| Third-party button-art provenance | `../../THIRD_PARTY_ASSETS.md` |
| Canonical project attribution | `../CREDITS.md` |
| Physical-device automation prompt | `IPHONE_AUTOMATION_PROMPT.md` |
| Retention, accessibility, and seller-name rationale | `PRODUCT_STEWARDSHIP_RATIONALE.md` |

## Evidence rule

Always tie claims to the revision and environment actually tested. Local browser, simulator, and unit evidence does not prove a deployed revision, live OAuth completion, physical microphone behavior, signing, TestFlight, or App Store acceptance.
