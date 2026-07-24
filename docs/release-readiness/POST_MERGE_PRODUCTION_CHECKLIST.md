# Direct Production Deployment Checklist

Updated: 2026-07-24. Final revision: `PENDING_FINAL_SHA`.

GitHub Actions is disabled. Do not wait for, trigger, or cite Actions checks for this candidate.

1. Record the final committed SHA in this file and the release evidence JSON.
2. Reconfirm the applied state of `20260724072904_account_deletion_maintenance_heartbeats.sql`; local and remote histories matched after the 2026-07-24 application.
3. Deploy the backend directly to Render from `PENDING_FINAL_SHA`. Record the deployment ID and verify readiness, reported revision, and maintenance-heartbeat behavior.
4. Deploy the frontend directly to Vercel from the same SHA. Record the deployment ID and verify the canonical production alias serves that revision.
5. Run hosted smoke for web, REST, WebSocket, auth, class, audio, offline, and account lifecycle. Record failures and rollback decisions.
6. Keep Apple live provider setup, signing, and physical-device microphone validation as separate external gates.
7. Do not create Gmail outreach drafts: reconnect the designated BrassTune sender first.

## Completion record

Do not mark production complete until the SHA, Supabase migration state, Render/Vercel deployment IDs, and hosted-smoke result are all recorded. Current values are pending.
