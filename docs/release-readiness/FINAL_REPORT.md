# BrassTune Completion Candidate

Updated: 2026-07-24. Candidate final revision: `PENDING_FINAL_SHA`.

## Decision

Local validation is complete for the current working-tree candidate. It is **not deployed** and is not a production-release certification. GitHub Actions is disabled and must not be used as a release gate for this candidate.

## Local evidence

| Surface | Result | Boundary |
|---|---|---|
| Backend | `286 passed, 11 skipped` | Local result only. |
| Frontend | `253/253` unit tests; production build passed | Local result only. |
| Device simulation | 12 viewport profiles passed | Simulated browser coverage, not physical devices. |
| Swift Core | `3/3` | Shared-domain coverage only. |
| Native iPhone units | `145/145` | Simulator evidence only. |
| Native iPhone UI | `20/20` | Simulator evidence only. |
| Native iPad journeys | First-run, main, and class journeys passed | Simulator evidence only. |
| Localization verifier | 660 keys across 12 locales; 0 issues | Does not prove human linguistic review. |

## Required release actions

1. Record the committed release revision as `PENDING_FINAL_SHA`; do not replace this placeholder until the final commit is known.
2. Reconfirm that `20260724072904_account_deletion_maintenance_heartbeats.sql` remains matched in local and remote Supabase migration history. It was applied on 2026-07-24.
3. Deploy the backend directly to Render and verify its reported revision/readiness and authenticated maintenance heartbeat behavior.
4. Deploy the frontend directly to Vercel and verify its reported revision matches the backend and `PENDING_FINAL_SHA`.
5. Run and record hosted smoke against the deployed web, REST, WebSocket, auth, class, audio, offline, and account-lifecycle surfaces.

## External blockers

- Apple live provider configuration and signing remain external.
- Google is enabled on the linked Supabase project; Apple remains disabled until its Apple Developer credentials are configured.
- Physical-device microphone/audio validation remains external.
- The connected Gmail sender identity is incorrect. Do not create outreach drafts until the designated sender is connected.

No claim here establishes a deployed revision, live provider enablement, signed native delivery, physical-device microphone quality, or sent/created Gmail drafts.
