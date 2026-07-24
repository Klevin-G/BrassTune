# Release Test Matrix

Updated: 2026-07-24. Deployed application revision: `26683c82c42839016383fb9cab676c9a35d554ca`.

| Gate | Evidence | Status | Release meaning |
|---|---|---|---|
| Backend | `286 passed, 11 skipped` | Passed locally | Requires deployed backend verification. |
| Frontend units | `253/253` | Passed locally | Requires deployed-bundle smoke. |
| Frontend build | Passed | Passed locally | Requires Vercel deployment identity check. |
| Device simulation | 12 viewport profiles passed | Passed locally | Not physical-device evidence. |
| Swift Core | `3/3` | Passed locally | Shared-domain check only. |
| Native iPhone units | `145/145` | Passed in simulator | Unsigned simulator evidence only. |
| Native iPhone UI | `20/20` | Passed in simulator | Unsigned simulator evidence only. |
| Native iPad journeys | First-run, main, and class passed | Passed in simulator | Unsigned simulator evidence only. |
| Localization | 660 keys, 12 locales, 0 issues | Passed locally | No human linguistic review recorded. |
| GitHub Actions | Disabled | Not applicable | Must not be used for this release candidate. |
| Supabase heartbeat migration | `20260724072904_account_deletion_maintenance_heartbeats.sql`; local/remote histories matched | Applied | Private heartbeat storage is present for readiness. |
| Render deployment | `dep-d9hinqjeo5us73e9eqng`; exact revision reported by `/api/version` | Passed | Backend is live on the recorded revision. |
| Vercel deployment | `dpl_5izYQzxQu4ZjwUn6gJxrHYArBD8v`; canonical alias attached | Passed | Production web artifact is ready. |
| Hosted smoke | 8/8 checks passed | Passed | Web root, readiness/version, CORS, and WebSocket safety boundary verified. |
| Post-deploy error scan | Render and Vercel returned no errors in the checked window | Passed | Point-in-time provider evidence only. |
| Apple/signing/physical microphone | External | Pending | Required for Apple/live-audio claims. |

## Reproduction boundary

Local test results cover the source candidate merged into the recorded application revision. The hosted rows cover the exact production deployment identities above; later code changes require fresh deployment and smoke evidence.
