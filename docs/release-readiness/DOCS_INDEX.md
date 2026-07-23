# Release Readiness Docs Index

Date: 2026-07-23

Branch: `arya/ux-parity-localization-20260722`
Candidate code head: `e1b3f61351d62e1438ac457c31b1a8d40691a1d5`
Billing-attempt and exact local-gate basis: `99e5a7f`

Current status: [PR #11](https://github.com/Klevin-G/BrassTune/pull/11) is open. Production-identical predecessor `2106768f177c64a1475c6168eed6d9a172633435` passed recorded GitHub Actions Backend [30002610359](https://github.com/Klevin-G/BrassTune/actions/runs/30002610359), Security [30002610363](https://github.com/Klevin-G/BrassTune/actions/runs/30002610363), Frontend [30002610356](https://github.com/Klevin-G/BrassTune/actions/runs/30002610356), and Swift [30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369). Candidate code `e1b3f61` and billing-attempt basis `99e5a7f` differ only in Playwright coverage and release documentation, not production application code; exact local gates at `99e5a7f` passed backend `223/227` with four skips, web units `199/199`, web E2E `398/405` with seven intended skips, native Core `3/3`, native app units `113/113`, and the web/native builds. Exact-head Actions attempts—Frontend [30004831887](https://github.com/Klevin-G/BrassTune/actions/runs/30004831887), Security [30004831904](https://github.com/Klevin-G/BrassTune/actions/runs/30004831904), Backend [30004831929](https://github.com/Klevin-G/BrassTune/actions/runs/30004831929), and Swift [30004831943](https://github.com/Klevin-G/BrassTune/actions/runs/30004831943)—were blocked by GitHub billing/spending enforcement before checkout or any step, not by test failures. Zero self-hosted runners were available and no paid/new-runner workaround was authorized. Merge is blocked until checks execute green on the then-current exact head. Nothing is merged, migrated, or deployed.

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
