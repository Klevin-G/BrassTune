# Predeployment Test Matrix

Updated: 2026-07-23. Heavy-gate base: `8ee07d63ddf201efc59f4b8c0b8d661cfd491082`; candidate successor: `8035d6c6b69a814a419439e0aeee820464f34d36`.

| Gate | Evidence | Status | Boundary |
|---|---|---|---|
| Backend suite | `223 passed`, `4` PostgreSQL-only skips; successor has no backend changes. | Passed locally | Not a live PostgreSQL/provider result. |
| Backend security/dependencies | Bandit: zero issues across 6,309 lines; pip audit clean. | Passed locally | Re-run if backend inputs change. |
| Frontend units | Successor: `38` files / `198` tests; shared metronome fixture focus: `5/5`. | Passed locally | Local only. |
| Frontend build/locales/audit | Production build passed; `11` locale chunks; npm audit clean. | Passed locally | No Vercel deployment claim. |
| Full local E2E | Heavy base: `398 passed`, `7` documented browser-engine skips. Successor metronome focus: `10/10` across five projects. | Passed locally | Router/UI production code is unchanged by the successor; local Playwright only. |
| Offline and viewport | Offline `2` passed; `12` simulated viewports. | Passed locally | Synthetic browser evidence, not physical devices. |
| Native package/app/UI/builds | Successor app units `113/113`, zero skips. Production-tree identity matches the heavy base, which passed Core `3/3`, UI `9/9` in one invocation, four builds, launch screenshots, plist, localization, and black-band checks. | Passed locally | Unsigned simulator only. |
| Review gates | Security approve/no P0–P2; audio/scorer approve with explicit denominator-beat contract; source/deploy preflight approve. | Approved locally | Does not approve a deploy. |
| Supabase PR1 migrations | Dry-run lists exactly `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and `20260723021828_account_deletion_privacy_tombstones.sql`; neither is applied. | Pending | Provider mutation/verification required; contract migration is not in PR1. |
| Hosted smoke | Candidate revision deployed and exercised against Vercel, Render, and Supabase. | Pending | Current production is healthy but stale. |
| Apple/device | Physical audio, accessibility, signing/archive, TestFlight, App Store Connect. | Pending | Excluded from this candidate. |

## Reproduction commands

- `cd backend && .venv/bin/python -m pytest`
- `cd frontend && npm test && npm run build && npm audit --omit=dev`
- `cd frontend && CI=true npm run e2e:local && npm run simulate:devices`
- `cd swift/BrassTuneCore && swift test`

Do not combine reruns, SHAs, simulator evidence, or hosted state into a single release claim.
