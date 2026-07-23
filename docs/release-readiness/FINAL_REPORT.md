# BrassTune Predeployment Snapshot

Updated: 2026-07-23

## Decision

`8035d6c6b69a814a419439e0aeee820464f34d36` is a **local predeployment candidate**, not a deployment, TestFlight, or App Store decision. Its heavy local gate is the exact base `8ee07d63ddf201efc59f4b8c0b8d661cfd491082`. The successor changes only the shared metronome fixture/docs, web timing helper/test, and native test; backend code is unchanged.

## Local evidence

| Surface | Result | Boundary |
|---|---|---|
| Backend | `223 passed`, `4` PostgreSQL-only skips; Bandit: zero issues across 6,309 lines; pip audit clean. | Local only; PostgreSQL path remains a CI/provider gate. |
| Web | Successor: `38` files / `198` unit tests, production build, `11` locale chunks, npm audit clean, and `10/10` focused metronome browser journeys. Heavy base: full E2E `398 passed`, `7` documented skips; offline `2` passed; device simulation `12` viewports. | Local browsers/viewport automation only. The router/UI tree is unchanged in the successor. |
| Native | Successor: app units `113/113`, including the shared metronome fixture with no skip. The production SwiftUI tree is identical to the heavy base, which passed BrassTuneCore `3/3`, UI `9/9` in one invocation, four simulator builds, launch screenshots, plist, localization, and black-band checks. | Unsigned simulator evidence only. |
| Review | Security: approve, no P0–P2. Audio/scorer: approve after explicit denominator-beat contract. Source/deploy preflight: approve. | Review is not a provider or device validation. |
| Supabase | Dry-run identifies exactly `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and `20260723021828_account_deletion_privacy_tombstones.sql`; neither is applied. | No provider mutation. The reserved contract migration remains absent from PR1. |

## Evidence artifact

Heavy-gate bundle: `/Users/aryasalem/Downloads/BrassTune-safety-bundles/20260723T094812Z-gates-8ee07d6`.

## Remaining release gates

- Documentation artifact must be current; this snapshot addresses that local artifact blocker.
- PR creation/review, push, merge, CI, and provider deployments remain pending.
- Apply only the two PR1 Supabase migrations after the required PR/approval flow; then verify provider state and rollback posture.
- Hosted Vercel/Render/Supabase smoke is pending. Production may be healthy but is stale and is not evidence that this candidate is deployed.
- Pre-PR1 rollback references are recorded: Render `dep-d9c4s2u1a83c73boitl0` and clean Vercel `dpl_4xD8XQDQLBpr5ufn6K2VaLBm6Gex`, both at `b84daccfd287669b227a1c40b8e9676573d1ab8d`. A new privacy-aware PR1 Render deployment must be retained before the later contract migration.
- Physical iPhone/iPad microphone and brass-room validation, signing, archive/export validation, TestFlight, App Store Connect, and review remain excluded.

**Status: local gates and reviews recorded; no hosted deployment, migration application, or Apple distribution claim.**
