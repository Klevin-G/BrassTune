# BrassTune Predeployment Release Audit

Updated: 2026-07-23

## Decision

This branch is a **predeployment candidate**. It is not yet a production release, TestFlight, or App Store readiness decision. The committed implementation tree tested below is `0273347b7ab32da3031a13abaa4b751730c46c1b`; the containing evidence commit changes only reports and generated screenshots. Provider mutation and hosted validation remain pending.

## Evidence Recorded For This Candidate

| Surface | Evidence | Boundary |
|---|---|---|
| Backend | Local suite: `221 passed`, `4` PostgreSQL-only skips; account-deletion focus `23/23`; production-code Bandit clean; current-environment `pip-audit` clean. | Local evidence only. The isolated PostgreSQL compatibility harness remains for CI because Docker/PostgreSQL was unavailable locally. |
| Web | `175/175` unit tests; production build; `11` lazy locale chunks; `npm audit --omit=dev` with `0` vulnerabilities; full local Playwright matrix `308 passed`, `7` intentional skips; offline production smoke `2/2`; WebKit skip-link stress `20/20`; Firefox reflection stress `10/10`; device simulation `12/12` Pass/None. | Local browser and synthetic viewport evidence only. The final device report records `0273347...` from a clean worktree. |
| Native | BrassTuneCore `3/3`; native units `104/104`; UI smoke `8/8`; Debug and Release iPhone/iPad simulator builds and launch-frame checks passed. Localization validation covered `556` source keys, `562` catalog entries, `159` sentinels, and `1,511` locale assertions with zero violations. | Local unsigned simulator and static localization evidence only; not physical-device, live-provider, signing, or Apple distribution evidence. |
| Supabase | Linked list/dry-run shows only `20260716201825` and the PR1 expand migration `20260723021828` pending; linked schema lint reports no errors. | No provider mutation was made for this candidate. The contract migration is intentionally absent until PR2. |

## Candidate Scope And Evidence Boundaries

- The candidate includes committed backend, web, fixture, localization, native SwiftUI, and release-workflow changes.
- Test fixtures, simulator execution, browser automation, launch-frame checks, and static localization assertions are synthetic or local evidence unless an individual result states otherwise. They do not validate real brass audio, microphone routing, accessibility assistive technology, human translation quality, Apple signing, or deployed-provider behavior.
- The two pending migrations are `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and the expand-only `20260723021828_account_deletion_privacy_tombstones.sql`. Their repository presence is not evidence of an applied migration.
- The full browser rerun exposed and then verified the restored-session recovery fix across all five configured projects. A WebKit keyboard-harness race was resolved by waiting for the lazy tuner route; the exact path then passed `20/20`.
- The final blocker-closure pass added exact Render deployment-ID/provider-SHA locking, normalized auth-return rejection, an awaited guest-session escape, open-tab weekly rollover reconciliation, deterministic native tuner release on scene deactivation, five music-terminology corrections, and CI tombstone-secret coverage. The integrated backend, frontend, native-unit, browser, and device checks above include those changes.

## Required Gates Before A Release Decision

1. Complete independent exact-SHA diff, security, audio, localization, deployment, and artifact review.
2. Merge PR1, apply only the two expand-compatible Supabase migrations, and verify linked history, readiness, RLS, storage, and account lifecycle.
3. Deploy and retain the exact PR1 privacy-aware backend as the post-contract rollback target.
4. Merge/apply the separate PR2 contract migration, then deploy the exact PR2 backend followed by the exact PR2 frontend and run strict hosted smoke.
5. Keep physical iPhone/iPad microphone, brass-room, assistive-technology, signing, TestFlight, and App Store evidence as separate future gates.
6. Complete in-context linguistic review with human speakers; automated terminology tests do not certify translation quality.

## Exclusions And Known Unknowns

- No production Vercel or Render deployment, hosted smoke, provider promotion, or post-contract rollback deployment is claimed here.
- No App Store Connect, TestFlight upload, signed archive, physical-device microphone, or physical brass-room result is claimed.

**Predeployment documentation status: committed implementation and local evidence recorded; exact-SHA review, provider, hosted, physical-device, and distribution gates remain pending.**
