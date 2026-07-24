# Direct Deployment And Rollback

Updated: 2026-07-24. Target revision: `PENDING_FINAL_SHA`.

## Deployment boundary

- GitHub Actions is disabled and must not be used for this candidate.
- Supabase migration `20260724072904_account_deletion_maintenance_heartbeats.sql` was applied on 2026-07-24; local and remote migration histories match.
- Direct Render and Vercel deployment is planned; no deployment IDs or hosted results are recorded yet.

## Order

1. Record `PENDING_FINAL_SHA` after the final commit exists.
2. Reconfirm the applied migration state before deployment.
3. Deploy Render directly from the final SHA; verify readiness, reported revision, and maintenance-heartbeat behavior.
4. Deploy Vercel directly from the same SHA; verify the production alias and reported revision.
5. Run hosted smoke before expanding access or making production-complete claims.

## Known-good rollback boundary

- The pre-candidate production revision is `6f4054412765d2aafe28d901e85a23ead5238c97`.
- The pre-candidate Render deployment is `dep-d9hg7cnavr4c73ehi0j0`.
- The pre-candidate Vercel deployment is `dpl_3wrVmKHRx8fxmH75haGKz55WWJfR`.
- The heartbeat migration is additive and private, so it remains schema-compatible with that application revision. The older backend does not write or enforce the new heartbeat.
- The terminal privacy contract migration `20260724034725_enforce_account_deletion_terminal_privacy.sql` is already applied. Never roll back to a backend that can write unsanitized terminal deletion rows; use `6f4054412765d2aafe28d901e85a23ead5238c97` or a later privacy-aware revision.

## Stop and rollback criteria

Stop the rollout for a failed migration, mismatched revision, failed readiness/heartbeat check, or failed hosted smoke affecting REST, WebSocket, auth, class, audio, offline, or account lifecycle.

- Vercel: revert/promote only to a previously recorded known-good deployment after confirming the affected revision.
- Render: roll back only to a previously recorded known-good deployment compatible with the applied database migration state.
- Supabase: do not reverse migrations without a reviewed data-compatibility plan; prefer a forward corrective migration when safe.

Record the incident, affected surface, provider deployment IDs, revisions, data impact, and recovery verification. Apple provider/signing and physical-device microphone evidence are external and are not rollback proof. Gmail drafts remain prohibited until the designated sender identity is connected.
