# Predeployment Test Matrix

Updated: 2026-07-23

Candidate code head: `e1b3f61351d62e1438ac457c31b1a8d40691a1d5`; billing-attempt and exact local-gate basis: `99e5a7f`; production-identical full-gate predecessor: `2106768f177c64a1475c6168eed6d9a172633435`. The candidate differs from the predecessor only in Playwright coverage and release documentation, not production application code.

| Gate | Evidence | Status | Boundary |
|---|---|---|---|
| Backend suite | Local `223 passed`, `4` PostgreSQL-only skips; [CI 30002610359](https://github.com/Klevin-G/BrassTune/actions/runs/30002610359) PostgreSQL `226 passed`, `1 skipped`, readiness green. | Passed | No live Supabase migration. |
| Backend security/dependencies | Recorded local Bandit/pip-audit clean; [CI 30002610363](https://github.com/Klevin-G/BrassTune/actions/runs/30002610363) succeeded. | Passed | Not a production authorization. |
| Frontend units/build | Exact local gate at `99e5a7f`: `39` files / `199` tests, production build, `11` locale chunks, and dependency audit (`0` findings) passed. | Passed | Local only. |
| Frontend browser matrix | Exact local gate at `99e5a7f`: `398 passed`, `7` intended skips in `5.0m`; predecessor [CI 30002610356](https://github.com/Klevin-G/BrassTune/actions/runs/30002610356): `398 passed`, `7 skipped` in `20.7m`. | Passed locally; final full CI blocked | Browser automation, not physical hardware. |
| Native package/app/UI/builds | Exact local gate at `99e5a7f`: Core `3/3`, app units `113/113`, and a Debug iPhone 17 Pro simulator build. Earlier recorded local evidence includes UI `9/9`, four builds, launch/plist/localization/black-band checks; [CI 30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369) succeeded on the production-identical predecessor. | Passed locally | Unsigned simulator only. |
| Exact-head GitHub Actions | Frontend [30004831887](https://github.com/Klevin-G/BrassTune/actions/runs/30004831887), Security [30004831904](https://github.com/Klevin-G/BrassTune/actions/runs/30004831904), Backend [30004831929](https://github.com/Klevin-G/BrassTune/actions/runs/30004831929), and Swift [30004831943](https://github.com/Klevin-G/BrassTune/actions/runs/30004831943) were stopped by GitHub billing/spending enforcement before checkout or any workflow step. | Blocked | Not test failures. Zero self-hosted runners were available; no paid/new-runner workaround was authorized. Exact-head checks must execute green before merge. |
| Supabase PR1 migrations | Dry-run names exactly the audio/storage and account-deletion/privacy tombstone migrations; neither is applied. | Pending | Provider mutation and validation required. |
| Preview | Predecessor-source Vercel preview `dpl_7xmSMfo1bX3dX9WQEXGxPhfpa2VJ` for production-identical predecessor `2106768`; not an exact `99e5a7f` preview. | Available | Preview is not production smoke. |
| Hosted smoke | Vercel, Render, Supabase, WebSocket, auth, account deletion, and offline shell at production URLs. | Pending | Must follow sequential deployment. |
| Apple/device | Physical audio, accessibility, signing/archive, TestFlight, App Store Connect. | Pending | Excluded from PR1 candidate evidence. |

## Reproduction commands

- `cd backend && .venv/bin/python -m pytest`
- `cd frontend && npm test && npm run build && npm audit --omit=dev`
- `cd frontend && CI=true npm run e2e:local && npm run simulate:devices`
- `cd swift/BrassTuneCore && swift test`

Do not combine local, CI, preview, hosted, simulator, and physical-device evidence into one release claim.
