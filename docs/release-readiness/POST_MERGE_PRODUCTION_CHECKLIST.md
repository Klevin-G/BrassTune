# Post-Merge Production Checklist

Updated: 2026-07-23. Run this only after the exact merged SHA passes required self-hosted CI.

## Ordered rollout

1. Record the final `main` SHA and verify Backend, Frontend, Security, and Swift checks ran on matching configured self-hosted runners.
2. Inspect linked migration state and apply the three reviewed expand migrations:
   - `20260716201825_audio_storage_jobs_and_upload_reservations.sql`
   - `20260723021828_account_deletion_privacy_tombstones.sql`
   - `20260723120000_reassert_backend_data_and_audio_privacy.sql`
3. Push approved Supabase configuration, including narrow reset/callback URLs and the iOS Google callback. Preserve Apple provider disabled until Apple setup is verified.
4. Deploy the privacy-aware Render backend at the exact SHA; verify readiness, version identity, privacy scrub/expand state, REST, and WebSocket paths.
5. Only after expand cleanup and retained backend rollback evidence, create/review/apply a separate terminal privacy contract migration. Do not create it early.
6. Deploy Vercel from the same SHA; require the canonical alias `https://brasstune.vercel.app` and provider commit metadata to match.
7. Run hosted smoke: signed-out guest, email auth, Google auth, Apple unavailable copy, class privacy, audio, offline workspace, REST/CORS/WebSocket, and account lifecycle with disposable users.

## Rollback

Before terminal contract enforcement, retain the privacy-aware expand backend as the rollback target. After enforcement, do not restore a backend that can write unsanitized terminal deletion data. Roll back Vercel independently if necessary and record affected data/surfaces.

## Explicitly excluded

This checklist does not establish Apple provider completion, physical-device validation, signing, TestFlight, or App Store readiness.
