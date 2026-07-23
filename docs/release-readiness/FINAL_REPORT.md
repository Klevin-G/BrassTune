# BrassTune PR1 Release Evidence

Updated: 2026-07-23

Candidate code head: `e1b3f61351d62e1438ac457c31b1a8d40691a1d5`
Billing-attempt and exact local-gate basis: `99e5a7f`
Branch/PR: `arya/ux-parity-localization-20260722`, [PR #11](https://github.com/Klevin-G/BrassTune/pull/11) (open and pushed)

## Decision

Production-identical predecessor `2106768f177c64a1475c6168eed6d9a172633435` passed the recorded local and GitHub Actions gates. Candidate code `e1b3f61` plus release-evidence head `99e5a7f` differs from that predecessor only in Playwright coverage and release documentation—no production application code changed. Candidate `e1b3f61` adds a seed-once regression guard after final review found the earlier fixture could mask persistence mutation; its focused mobile-WebKit check passed `10/10`. Exact-head checks are blocked, not failed tests: the four GitHub Actions attempts were stopped by GitHub billing/spending enforcement before checkout or any workflow step, and no self-hosted runner was available. Merge remains blocked until the exact-head checks can execute green; no paid or new-runner workaround was authorized. This is a PR1 candidate only, not a hosted, physical-device, signing, TestFlight, or App Store claim.

## Evidence

| Surface | Result | Boundary |
|---|---|---|
| Backend | Local: `223 passed`, `4` PostgreSQL-only skips. Predecessor [CI run 30002610359](https://github.com/Klevin-G/BrassTune/actions/runs/30002610359): PostgreSQL suite `226 passed`, `1 skipped`; readiness green. | Candidate delta is Playwright-only; no production database change. |
| Security | [CI run 30002610363](https://github.com/Klevin-G/BrassTune/actions/runs/30002610363) succeeded; recorded Bandit and dependency-audit checks are clean. | Does not authorize a provider change. |
| Frontend | Exact local gate at `99e5a7f`: `39` files / `199` unit tests, production build, `11` locale chunks, dependency audit (`0` findings), and full E2E `398 passed`, `7` intended skips in `5.0m`. Predecessor [CI run 30002610356](https://github.com/Klevin-G/BrassTune/actions/runs/30002610356): `398 passed`, `7 skipped` in `20.7m`. | Browser automation only; final candidate-head CI is still required. |
| Native | Exact local gate at `99e5a7f`: Core `3/3`, app units `113/113`, and a Debug iPhone 17 Pro simulator build. [CI run 30002610369](https://github.com/Klevin-G/BrassTune/actions/runs/30002610369) succeeded on the production-identical predecessor. Earlier recorded local simulator evidence includes UI `9/9`, four builds, and launch/black-band checks. | Unsigned simulator evidence only. |
| Exact-head Actions gate | Frontend [30004831887](https://github.com/Klevin-G/BrassTune/actions/runs/30004831887), Security [30004831904](https://github.com/Klevin-G/BrassTune/actions/runs/30004831904), Backend [30004831929](https://github.com/Klevin-G/BrassTune/actions/runs/30004831929), and Swift [30004831943](https://github.com/Klevin-G/BrassTune/actions/runs/30004831943) were blocked by GitHub billing/spending enforcement before checkout or any step. | This is infrastructure enforcement, not a test result. Zero self-hosted runners were available; no paid/new-runner workaround was authorized. |
| Vercel preview | `dpl_7xmSMfo1bX3dX9WQEXGxPhfpa2VJ` is a predecessor-source preview for production-identical predecessor `2106768`, not an exact `99e5a7f` preview. | Preview is not a production deployment or hosted-release smoke. |

Independent security, audio/scorer, PostgreSQL-fix, deployment-preflight, and artifact reviews reported no P0-P2 blocker at their reviewed revisions. The heavy-gate evidence bundle is `/Users/aryasalem/Downloads/BrassTune-safety-bundles/20260723T094812Z-gates-8ee07d6`; a fresh checksum-backed bundle and independent artifact review are required for the documentation-only successor before merge.

## Provider preflight and rollback posture

- Linked Supabase project preflight identified two unapplied PR1 migrations: `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and `20260723021828_account_deletion_privacy_tombstones.sql`.
- Render and Vercel production deployment are pending. Preserve the pre-PR1 Render rollback reference `dep-d9c4s2u1a83c73boitl0` and clean Vercel rollback reference `dpl_4xD8XQDQLBpr5ufn6K2VaLBm6Gex`, both at `b84daccfd287669b227a1c40b8e9676573d1ab8d`.
- The terminal privacy contract migration remains outside PR1 and must follow the separately reviewed PR2 sequence.

## Next gates

1. Restore authorized GitHub Actions capacity or an authorized eligible runner, then execute Frontend, Security, Backend, and Swift checks green on the then-current exact head; do not merge before then.
2. Apply and validate only the two PR1 Supabase migrations, then deploy Render at the merged SHA.
3. Merge/apply the separate terminal-privacy contract migration; deploy Render and Vercel from that exact SHA.
4. Run strict hosted Vercel/Render/Supabase smoke before publishing the production URL or creating outreach drafts with it.
5. Keep physical iPhone/iPad microphone, accessibility, signing/archive, TestFlight, and App Store review as separate, uncompleted gates.
