# Release Test Matrix

Updated: 2026-07-24. Final release revision: `PENDING_FINAL_SHA`.

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
| Supabase heartbeat migration | `20260724072904_account_deletion_maintenance_heartbeats.sql`; local/remote histories matched | Applied | Reconfirm before the dependent production verification. |
| Render/Vercel same-SHA deployment | Direct deployment planned | Pending | Record provider deployment identities and exact revision. |
| Hosted smoke | No current hosted result | Pending | Cover web, REST, WebSocket, auth, class, audio, offline, and account lifecycle. |
| Apple/signing/physical microphone | External | Pending | Required for Apple/live-audio claims. |

## Reproduction boundary

The results above are supplied current working-tree evidence. Re-run affected local gates if the final commit changes; replace `PENDING_FINAL_SHA` only after that final commit is recorded.
