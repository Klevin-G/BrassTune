# Release Readiness Docs Index

Date: 2026-07-23

Branch: `arya/ux-parity-localization-20260722`
Candidate code head: `e1b3f61351d62e1438ac457c31b1a8d40691a1d5`

Current status: [PR #11](https://github.com/Klevin-G/BrassTune/pull/11) is open. Production-identical predecessor `2106768f177c64a1475c6168eed6d9a172633435` passed recorded local gates and GitHub Actions Backend [30002610359](https://github.com/Klevin-G/BrassTune/actions/runs/30002610359), Security [30002610363](https://github.com/Klevin-G/BrassTune/actions/runs/30002610363), Frontend [30002610356](https://github.com/Klevin-G/BrassTune/actions/runs/30002610356), and Swift [30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369). Candidate `e1b3f61` changes only the Playwright persistence fixture and passed the focused mobile-WebKit check `10/10`; final candidate-head checks remain the PR merge gate. Nothing is merged, migrated, or deployed.

| Topic | Canonical file | Purpose |
|---|---|---|
| Current PR1 decision | `FINAL_REPORT.md` | Exact head, evidence, provider boundary, and next gates. |
| Machine-readable evidence | `release-evidence.json` | Candidate SHA, counts, workflow IDs, provider preflight, rollback references. |
| Test matrix | `TEST_MATRIX.md` | Local/CI results and environment boundaries. |
| Deployment/rollback | `POST_MERGE_PRODUCTION_CHECKLIST.md`, `DEPLOYMENT_ROLLBACK.md` | Required sequential PR1 then PR2 provider actions. |
| Apple readiness | `APP_STORE_CHECKLIST.md`, `APP_REVIEW_NOTES.md`, `APP_PRIVACY_DRAFT.md`, `TESTFLIGHT_HANDOFF.md` | Simulator evidence and explicit human/device/signing gates. |
| Web recovery history | `WEB_RECOVERY_FINDINGS.md`, `WEB_PRODUCTION_COMPLETION_GATE.md`, `FAILURE_LOG.md` | Historical evidence; not the current candidate decision. |
| Security/privacy | `SECURITY_PRIVACY.md`, `THREAT_MODEL.md`, `AUTH_PROVIDER_SETUP.md`, `LIVE_AUTH_TEST_PLAN.md` | Auth, privacy, and production checks. |

## Evidence rule

No document may claim CI green, merge-ready, hosted verified, native complete, production complete, or release ready without the exact SHA, source, environment, date, and result. Preview evidence is not production evidence; simulator evidence is not physical-device or App Store evidence.
