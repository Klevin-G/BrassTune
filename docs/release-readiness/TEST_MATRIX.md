# Predeployment Test Matrix

Updated: 2026-07-23

Candidate code head: `e1b3f61351d62e1438ac457c31b1a8d40691a1d5`; production-identical full-gate predecessor: `2106768f177c64a1475c6168eed6d9a172633435`.

| Gate | Evidence | Status | Boundary |
|---|---|---|---|
| Backend suite | Local `223 passed`, `4` PostgreSQL-only skips; [CI 30002610359](https://github.com/Klevin-G/BrassTune/actions/runs/30002610359) PostgreSQL `226 passed`, `1 skipped`, readiness green. | Passed | No live Supabase migration. |
| Backend security/dependencies | Recorded local Bandit/pip-audit clean; [CI 30002610363](https://github.com/Klevin-G/BrassTune/actions/runs/30002610363) succeeded. | Passed | Not a production authorization. |
| Frontend units/build | Local `39` files / `199` tests, production build, `11` locale chunks, and dependency audit (`0` findings) passed. | Passed | Local only. |
| Frontend browser matrix | Predecessor local full E2E `398 passed`, `7` intended skips in `4.9m`; [CI 30002610356](https://github.com/Klevin-G/BrassTune/actions/runs/30002610356): `398 passed`, `7 skipped` in `20.7m`. Candidate seed-once persistence test: mobile-WebKit `10/10`. | Candidate focused gate passed; final full CI pending | Browser automation, not physical hardware. |
| Native package/app/UI/builds | Recorded local Core `3/3`, app units `113/113`, UI `9/9`, four simulator builds, launch/plist/localization/black-band checks; [CI 30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369) succeeded. | Passed | Unsigned simulator only. |
| Supabase PR1 migrations | Dry-run names exactly the audio/storage and account-deletion/privacy tombstone migrations; neither is applied. | Pending | Provider mutation and validation required. |
| Preview | Exact-head Vercel preview `dpl_7xmSMfo1bX3dX9WQEXGxPhfpa2VJ`. | Available | Preview is not production smoke. |
| Hosted smoke | Vercel, Render, Supabase, WebSocket, auth, account deletion, and offline shell at production URLs. | Pending | Must follow sequential deployment. |
| Apple/device | Physical audio, accessibility, signing/archive, TestFlight, App Store Connect. | Pending | Excluded from PR1 candidate evidence. |

## Reproduction commands

- `cd backend && .venv/bin/python -m pytest`
- `cd frontend && npm test && npm run build && npm audit --omit=dev`
- `cd frontend && CI=true npm run e2e:local && npm run simulate:devices`
- `cd swift/BrassTuneCore && swift test`

Do not combine local, CI, preview, hosted, simulator, and physical-device evidence into one release claim.
