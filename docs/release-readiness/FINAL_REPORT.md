# BrassTune Predeployment Release Audit

Updated: 2026-07-23

## Decision

This branch is a **predeployment candidate**. It is not yet a production release, TestFlight, or App Store readiness decision. The committed implementation tree tested below is `3ec585ec8b604b9a04cb7708872c66bef963fe3f`; device-evidence commit `9003cf4282f8aef5d1e4d5900454d57862e1519e` records the clean responsive simulation, and the containing documentation commit changes reports only. Provider mutation and hosted validation remain pending.

## Evidence Recorded For This Candidate

| Surface | Evidence | Boundary |
|---|---|---|
| Backend | Local suite: `223 passed`, `4` PostgreSQL-only skips; production-code Bandit clean; current-environment `pip-audit --local` found no known vulnerabilities. | Local evidence only. The isolated PostgreSQL compatibility harness remains for CI because Docker/PostgreSQL was unavailable locally. |
| Web | `35` test files / `188` unit tests; production build/typecheck and PWA checks passed; `11` lazy locale chunks; `npm audit --omit=dev` found `0` vulnerabilities; full local Playwright matrix `365` total: `358 passed`, `7` intentional PDF-engine skips; offline production smoke `2/2`; device simulation `12/12` Pass/None from clean `3ec585e`. The final full matrix emitted no React cross-render warning. | Local browser and synthetic viewport evidence only. |
| Native | Fresh BrassTuneCore package tests passed `3/3`; the native app tree is unchanged, with prior exact evidence of `104/104` app units and Release iPhone/iPad simulator builds. | Local package plus prior unsigned simulator evidence only; not physical-device, live-provider, signing, or Apple distribution evidence. |
| Supabase | Linked list/dry-run shows only `20260716201825` and the PR1 expand migration `20260723021828` pending; linked schema lint reports no errors. | No provider mutation was made for this candidate. The contract migration is intentionally absent until PR2. |

## Candidate Scope And Evidence Boundaries

- The candidate includes committed backend, web, fixture, localization, native SwiftUI, and release-workflow changes.
- Test fixtures, simulator execution, browser automation, launch-frame checks, and static localization assertions are synthetic or local evidence unless an individual result states otherwise. They do not validate real brass audio, microphone routing, accessibility assistive technology, human translation quality, Apple signing, or deployed-provider behavior.
- The two pending migrations are `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and the expand-only `20260723021828_account_deletion_privacy_tombstones.sql`. Their repository presence is not evidence of an applied migration.
- The final full local browser matrix contains no React cross-render warning. This is local-run evidence, not a hosted-runtime claim.
- Production-code Bandit, current-environment `pip-audit --local`, and `npm audit --omit=dev` were refreshed after the implementation tree was frozen. The requirements-file `pip-audit` resolver still hits the documented local `ensurepip` crash before analysis; exact lockfile auditing remains a remote security-workflow gate.

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
