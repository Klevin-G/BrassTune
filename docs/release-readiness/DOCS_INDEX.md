# Release Readiness Docs Index

Date: 2026-07-23
Branch: `arya/ux-parity-localization-20260722`

Current audit status: local implementation candidate `8035d6c6b69a814a419439e0aeee820464f34d36` has passed the recorded local web, backend, native simulator, security, and audio/domain gates. It is not yet pushed, reviewed, merged, migrated, or deployed. Current production is healthy but stale; physical-device, signing, TestFlight, and App Store gates remain separate and unverified.

## Canonical Current Files

| Topic | Canonical File | Notes |
|---|---|---|
| Current predeployment decision | `FINAL_REPORT.md` | Human-readable current candidate, evidence, and release boundaries. |
| Machine-readable current evidence | `release-evidence.json` | Current candidate SHAs, gate counts, migration state, provider boundaries, and rollback references. |
| Deployment sequence and rollback | `POST_MERGE_PRODUCTION_CHECKLIST.md`, `DEPLOYMENT_ROLLBACK.md` | Required PR1 migration/backend then PR2 contract/backend/frontend sequence. |
| Historical web recovery | `WEB_RECOVERY_FINDINGS.md`, `WEB_PRODUCTION_COMPLETION_GATE.md` | Prior recovery and beta evidence only; not the current candidate decision. |
| Workstream ownership | `WORKSTREAM_OWNERSHIP.md` | Maps multi-agent audits, evidence, and remaining blockers. |
| Test evidence matrix | `TEST_MATRIX.md` | Must be refreshed after final commit and CI. Treat older counts as historical. |
| Historical failures | `FAILURE_LOG.md` | Use for prior CI/local failures and recovery backup records. |
| Final closeout | `FINAL_REPORT.md` | Current local closeout; refresh again after exact-SHA CI, merge, deployment, and hosted smoke. |

## Supporting Docs

| Topic | Files | Status |
|---|---|---|
| Web E2E and device simulation | `WEB_E2E_REPORT.md`, `device-simulation-report.md`, `ACCESSIBILITY_BETA_CHECKLIST.md` | Supporting evidence; rerun after final implementation. |
| Backend/security/privacy | `SECURITY_PRIVACY.md`, `THREAT_MODEL.md`, `AUTH_PROVIDER_SETUP.md`, `LIVE_AUTH_TEST_PLAN.md` | Must stay aligned with explicit `BRASSTUNE_AUTH_MODE` and dependency audit status. |
| Score practice | `SCORE_PRACTICE_FEATURE.md`, `SCORE_CAPTURE_VALIDATION.md` | Current status is web foundation, not full reader/native parity. |
| Metronome | `METRONOME_VALIDATION.md` | Current status is web foundation, not measured long-run/native parity. |
| Native and Apple | `IOS_SIMULATOR_REPORT.md`, `NATIVE_DESIGN_PARITY.md`, `WEB_NATIVE_PARITY_CONTRACT.md`, `APP_STORE_CHECKLIST.md`, `APP_REVIEW_NOTES.md`, `APP_PRIVACY_DRAFT.md`, `TESTFLIGHT_HANDOFF.md` | Simulator evidence exists; App Store/TestFlight/native parity remain blocked. |
| Beta operations | `CLOSED_BETA_HANDOFF.md`, `BETA_QA_GUIDE.md`, `FRIEND_QA_SCRIPT.md`, `BETA_FEEDBACK_TRIAGE.md` | Keep tester language scoped to web closed-beta candidate. |
| Deployment and incident handling | `POST_MERGE_PRODUCTION_CHECKLIST.md`, `DEPLOYMENT_ROLLBACK.md`, `INCIDENT_RESPONSE.md`, `HUMAN_ACTIONS.md` | Production deploy was not changed in this run. |
| Historical baseline and follow-up | `BASELINE.md`, `FINDINGS.md`, `LOCAL_IMPLEMENTATION_INVENTORY.md`, `NEXT_WORK.md` | Useful context, but not current release evidence unless refreshed with the latest pushed SHA. |

## Duplicate Handling

- `FINAL_REPORT.md` owns the current human-readable predeployment decision.
- `release-evidence.json` owns the current machine-readable candidate evidence.
- `WEB_RECOVERY_FINDINGS.md` and `WEB_PRODUCTION_COMPLETION_GATE.md` are historical recovery/beta context.
- `FAILURE_LOG.md` owns historical failure narratives.
- `TEST_MATRIX.md` owns native simulator command/result evidence after final validation.
- `FINAL_REPORT.md` is current for local evidence and must be refreshed after exact-SHA CI, merge, deployment, and hosted smoke.
- `BETA_LOAD_ABUSE_SMOKE.md` and `LOAD_ABUSE_SMOKE.md` overlap; keep one canonical load/abuse procedure in the next docs cleanup.
- `BETA_QA_GUIDE.md` and `FRIEND_QA_SCRIPT.md` overlap; keep the beta guide canonical and make friend scripts persona-specific.

## Evidence Rule

No document may claim `CI green`, `merge-ready`, `hosted verified`, `native complete`, `production complete`, or `release ready` unless it names the exact Git SHA, command/source, environment, date, and result.
