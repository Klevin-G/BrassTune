# Release Readiness Docs Index

Date: 2026-06-20
Branch: `arya/release-readiness-hardening`

## Canonical Current Files

| Topic | Canonical File | Notes |
|---|---|---|
| Current status and release decision | `MASTER_FINDINGS.md` | Source of truth until final pushed SHA is verified. |
| Local recovery inventory | `LOCAL_IMPLEMENTATION_INVENTORY.md` | Lists dirty/untracked implementation files and known gaps. |
| Workstream ownership | `WORKSTREAM_OWNERSHIP.md` | Maps multi-agent audits, evidence, and remaining blockers. |
| Test evidence matrix | `TEST_MATRIX.md` | Must be refreshed after final commit and CI. Treat older counts as historical. |
| Historical failures | `FAILURE_LOG.md` | Use for prior CI/local failures and recovery backup records. |
| Final closeout | `FINAL_REPORT.md` | Refresh only after implementation is committed, main is merged, and exact-SHA CI is known. |

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
| Historical baseline | `BASELINE.md`, `FINDINGS.md`, `NEXT_WORK.md` | Useful context, but not current release evidence unless refreshed with final SHA. |

## Duplicate Handling

- `MASTER_FINDINGS.md` owns the current release decision.
- `FAILURE_LOG.md` owns historical failure narratives.
- `TEST_MATRIX.md` owns command/result evidence after final validation.
- `FINAL_REPORT.md` should summarize, not duplicate, the full evidence matrix.
- `BETA_LOAD_ABUSE_SMOKE.md` and `LOAD_ABUSE_SMOKE.md` overlap; keep one canonical load/abuse procedure in the next docs cleanup.
- `BETA_QA_GUIDE.md` and `FRIEND_QA_SCRIPT.md` overlap; keep the beta guide canonical and make friend scripts persona-specific.

## Evidence Rule

No document may claim `CI green`, `merge-ready`, `hosted verified`, `native complete`, `production complete`, or `release ready` unless it names the exact Git SHA, command/source, environment, date, and result.
