# BrassTune Completion Candidate

Updated: 2026-07-24. Deployed application revision: `26683c82c42839016383fb9cab676c9a35d554ca`.

## Decision

The verified web/backend candidate is deployed at the exact merged revision above. Direct Render/Vercel deployment, revision checks, hosted smoke, provider error scans, and the linked Supabase migration state pass. This does not certify Apple distribution, physical-device audio, or every live identity/account-lifecycle path. GitHub Actions remained disabled and was not used.

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

## Production deployment record

1. Supabase migration history matched through `20260724072904_account_deletion_maintenance_heartbeats.sql`.
2. Render deployment `dep-d9hinqjeo5us73e9eqng` is live and reports commit `26683c82c42839016383fb9cab676c9a35d554ca`.
3. Vercel deployment `dpl_5izYQzxQu4ZjwUn6gJxrHYArBD8v` is ready and owns `https://brasstune.vercel.app`.
4. Hosted smoke passed web root, readiness, exact version, two CORS paths, WebSocket app response, query-token rejection, and bad-Origin rejection.
5. Render and Vercel post-deploy error queries returned no errors for the checked window.
6. Gmail outreach preparation completed in `brasstune1@gmail.com`: 44 drafts, 44 unique recipients, 44 unique subjects, and no duplicates. No message was sent.

## External blockers

- Apple live provider configuration and signing remain external.
- Google is enabled on the linked Supabase project; Apple remains disabled until its Apple Developer credentials are configured.
- Physical-device microphone/audio validation remains external.

No claim here establishes Apple live-provider enablement, signed native delivery, physical-device microphone quality, disposable live-account lifecycle completion, or sent Gmail messages.
