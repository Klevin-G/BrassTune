# BrassTune PR1 Release Evidence

Updated: 2026-07-23

Exact code head: `2106768f177c64a1475c6168eed6d9a172633435`
Branch/PR: `arya/ux-parity-localization-20260722`, [PR #11](https://github.com/Klevin-G/BrassTune/pull/11) (open and pushed)

## Decision

The exact code head has passed the recorded local and GitHub Actions gates. It is a reviewed PR1 candidate only: it has not been merged, migrated, or deployed. This document does not make a hosted, physical-device, signing, TestFlight, or App Store claim.

## Evidence

| Surface | Result | Boundary |
|---|---|---|
| Backend | Local: `223 passed`, `4` PostgreSQL-only skips. [CI run 30002610359](https://github.com/Klevin-G/BrassTune/actions/runs/30002610359): PostgreSQL suite `226 passed`, `1 skipped`; readiness green. | CI/local evidence; no production database change. |
| Security | [CI run 30002610363](https://github.com/Klevin-G/BrassTune/actions/runs/30002610363) succeeded; recorded Bandit and dependency-audit checks are clean. | Does not authorize a provider change. |
| Frontend | Local: `39` files / `199` unit tests, production build, `11` locale chunks, and dependency audit (`0` findings) passed; full E2E `398 passed`, `7` intended skips in `4.9m`; focused mobile-WebKit `10/10`. [CI run 30002610356](https://github.com/Klevin-G/BrassTune/actions/runs/30002610356): `398 passed`, `7 skipped` in `20.7m`. | Browser automation only. |
| Native | [CI run 30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369) succeeded. Recorded local simulator evidence includes Core `3/3`, app units `113/113`, UI `9/9`, four builds, and launch/black-band checks. | Unsigned simulator evidence only. |
| Vercel preview | `dpl_7xmSMfo1bX3dX9WQEXGxPhfpa2VJ` is the exact-head preview. | Preview is not a production deployment or hosted-release smoke. |

Independent security, audio/scorer, PostgreSQL-fix, deployment-preflight, and artifact reviews reported no P0-P2 blocker at their reviewed revisions. The heavy-gate evidence bundle is `/Users/aryasalem/Downloads/BrassTune-safety-bundles/20260723T094812Z-gates-8ee07d6`; a fresh checksum-backed bundle and independent artifact review are required for the documentation-only successor before merge.

## Provider preflight and rollback posture

- Linked Supabase project preflight identified two unapplied PR1 migrations: `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and `20260723021828_account_deletion_privacy_tombstones.sql`.
- Render and Vercel production deployment are pending. Preserve the pre-PR1 Render rollback reference `dep-d9c4s2u1a83c73boitl0` and clean Vercel rollback reference `dpl_4xD8XQDQLBpr5ufn6K2VaLBm6Gex`, both at `b84daccfd287669b227a1c40b8e9676573d1ab8d`.
- The terminal privacy contract migration remains outside PR1 and must follow the separately reviewed PR2 sequence.

## Next gates

1. Merge PR #11 only after its exact-head checks and review remain valid.
2. Apply and validate only the two PR1 Supabase migrations, then deploy Render at the merged SHA.
3. Merge/apply the separate terminal-privacy contract migration; deploy Render and Vercel from that exact SHA.
4. Run strict hosted Vercel/Render/Supabase smoke before publishing the production URL or creating outreach drafts with it.
5. Keep physical iPhone/iPad microphone, accessibility, signing/archive, TestFlight, and App Store review as separate, uncompleted gates.
