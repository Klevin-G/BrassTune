# Incident Response

Updated: 2026-06-20 UTC.

## Scope

This is the closed-beta incident checklist for BrassTune web/API/native testing. It does not replace provider security contacts or legal breach response.

## Severity

| Severity | Examples | First Action |
|---|---|---|
| SEV0 | Secret exposure, unauthorized user data access, destructive account-deletion bug | Disable affected workflow, rotate credentials, preserve logs, notify owner/legal. |
| SEV1 | Production auth outage, data export/delete failure, hosted API unavailable | Stop tester invites, run hosted smoke, check Render/Vercel/Supabase status and deploy history. |
| SEV2 | WebSocket/mic/recording regression, score import local failure, broken route | File issue, reproduce locally, patch behind normal release process. |
| SEV3 | Copy/accessibility/visual bug with workaround | Track in beta feedback triage. |

## Response Steps

1. Record incident time, affected environment, branch/SHA/deploy ID, and user-visible symptom.
2. Do not paste tokens, private user data, recordings, OAuth payloads, score files, or raw logs with personal data into chat or public issues.
3. Run read-only hosted checks first: Vercel root/deep link, Render `/api/health`, CORS, and raw WebSocket auth-required response.
4. Check whether the issue is production-only, preview-only, local-only, or provider-wide.
5. Roll back only through owner-approved Vercel/Render controls. Do not force-push or rewrite Git history.
6. For suspected auth/data exposure, rotate affected secrets and verify Supabase RLS/storage policies before re-enabling tests.
7. Update `FAILURE_LOG.md`, `DEPLOYMENT_ROLLBACK.md`, and `POST_MERGE_PRODUCTION_CHECKLIST.md` with evidence and follow-up.

## Owner Inputs Needed

- Incident contact list.
- Escalation path for Vercel, Render, Supabase, Apple, and Google.
- Backup/restore owner and retention policy.
- Public beta support channel and response SLA.
