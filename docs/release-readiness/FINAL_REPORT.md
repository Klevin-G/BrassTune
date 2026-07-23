# BrassTune Predeployment Release Audit

Updated: 2026-07-23

## Decision

This branch is a **predeployment candidate**. It is not a deployment, release, TestFlight, or App Store readiness decision. The quiescent local matrix passed, but the candidate has not yet been committed or independently reviewed. No clean-worktree claim, defect-free claim, provider mutation, or hosted result is recorded here.

## Evidence Recorded For This Candidate

| Surface | Evidence | Boundary |
|---|---|---|
| Backend | Local suite: `219 passed`, `2 skipped`; Bandit clean; `pip-audit` clean. | Local evidence only; it does not validate a deployed backend or provider configuration. |
| Web | `156/156` unit tests; production build; `11` lazy locale chunks; `npm audit --omit=dev` with `0` vulnerabilities; full local Playwright matrix `303 passed`, `7` intentional skips; offline production smoke `2/2`; WebKit redirect repeat `20/20`; Chromium and WebKit journey repeat `30/30`; device simulation `12/12` Pass/None. | Local browser and synthetic viewport evidence only; supporting reruns overlap the full matrix and are not added to its count. |
| Native | BrassTuneCore `3/3`; native units `99/99`; UI smoke `8/8`; Debug and Release iPhone/iPad simulator builds and launch-frame checks passed. Localization validation covered `556` source keys, `562` catalog entries, `159` sentinels, and `1,511` locale assertions with zero violations. | Local unsigned simulator and static localization evidence only; not physical-device, live-provider, signing, or Apple distribution evidence. |
| Supabase | Two repository migrations are pending on the linked provider. | No provider mutation was made for this candidate. |

## Candidate Scope And Evidence Boundaries

- The candidate includes backend, web, fixture, localization, native SwiftUI, and release-workflow changes visible in the working-tree diff.
- Test fixtures, simulator execution, browser automation, launch-frame checks, and static localization assertions are synthetic or local evidence unless an individual result states otherwise. They do not validate real brass audio, microphone routing, accessibility assistive technology, human translation quality, Apple signing, or deployed-provider behavior.
- The two pending migrations are `20260716201825_audio_storage_jobs_and_upload_reservations.sql` and `20260723021828_account_deletion_privacy_tombstones.sql`. Their repository presence is not evidence of an applied migration.

## Required Gates Before A Release Decision

1. Commit the quiescent candidate, record its exact revision, and complete independent diff/security/release review.
2. Apply the two Supabase migrations only through an authorized provider change; then verify linked migration history and relevant security/account-lifecycle invariants.
3. Establish exact revision identity for Vercel and Render, then run hosted smoke and authorized disposable-account lifecycle checks.
4. Run physical iPhone/iPad validation for microphone/brass quality, audio routes and interruptions, Files/Photos, accessibility, and localization/RTL review.
5. Complete in-context linguistic and RTL review with human speakers/reviewers.
6. Produce a signed archive and complete the separate TestFlight/App Store gates before making an Apple distribution claim.

## Exclusions And Known Unknowns

- No final exact commit, independent review approval, Vercel or Render deployment, hosted smoke, exact hosted SHA, or rollback target is claimed.
- No App Store Connect, TestFlight upload, signed archive, physical-device microphone, or physical brass-room result is claimed.

**Precommit documentation status: local evidence recorded; commit, review, provider, physical-device, and distribution gates remain pending.**
