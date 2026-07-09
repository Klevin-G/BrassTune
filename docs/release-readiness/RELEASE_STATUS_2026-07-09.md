# BrassTune Release Status — 2026-07-09 (authoritative)

This file supersedes earlier "PASSED / production certified" language in the
release-readiness ledger. Those earlier gate files describe the June beta
evidence and are historical. The current, honest status is below.

## Decision

- **Web (code):** COMPLETE and merged to `main`.
- **Native (code):** COMPLETE and merged to `main`.
- **Web production deploy:** BLOCKED on owner provider reconnection (see below).
- **Native store release:** BLOCKED on physical-device validation + Apple signing/TestFlight (owner/hardware).

`main` HEAD at time of writing: web PR #7 (`2768170`) + native PR #8 (`953dcc9`)
+ preserved CI scripts (`7913ba9`). `main` is the only active branch.

## Local validation (reproduced from CI workflow definitions, 2026-07-09)

Backend `pytest` 104 passed · Frontend unit 50 passed · Frontend production build passed
· Local Playwright e2e 95 passed · `npm audit --omit=dev` 0 vulnerabilities
· `pip-audit` no known vulnerabilities · Bandit no issues.

BrassTuneCore `swift test` 3 passed · App unit tests 18 passed · iPhone Debug build,
iPhone Release build, iPad Debug build all succeeded · UI smoke
(`testLaunchPracticeAndSettingsSurfaces`) passed on an unloaded machine.
(The UI smoke fails only under heavy concurrent CPU load — a simulator timing
artifact, not an app defect.)

## Providers

- **Supabase (`uvbcvqupelcrncyhqsrq`):** ACTIVE_HEALTHY. All 10 tables
  (`users`, `practice_sessions`, `pitch_samples`, `note_events`, `groups`,
  `group_members`, `invitations`, `instrument_profiles`, `recommendations`,
  `account_deletion_jobs`) + `rls_auto_enable` RPC deployed; `session-audio`
  bucket private; all 5 migrations present. Verified via service key + PostgREST.
- **Render (`brasstune.onrender.com`):** UP and auth-enabled (protected routes
  return 401), but serving stale commit `b956cf5` (2026-06-21). Redeploy of the
  new `main` FAILS: the Render deploy API returns
  `not found: https://api.github.com/repositories/1267917679`. The repo ID is
  correct, so Render's GitHub App lost repo access when the repo was transferred
  to `Klevin-G`. **Owner action required.**
- **Vercel (`brass-tune.vercel.app`):** production is LIVE, HTTP 200, no SSO wall,
  correct `permissions-policy` for camera/mic. The available `VERCEL_TOKEN`
  (account `epicgamerglobal`) resolves 0 projects and cannot see/deploy the
  `brass-tune` project. **Owner action required.**
- **GitHub Actions:** billing-blocked on the private `Klevin-G` repo —
  `workflow_dispatch` runs sit queued with no runner (a prior commit literally
  recorded the "GitHub Actions billing blocker"). July-4 `pull_request` runs
  passed; all gates have been reproduced green locally. **Owner action required.**

## Exact owner actions to finish the deploy (all stem from the repo transfer + private-repo billing)

1. **Render:** In Render → the BrassTune service → reconnect/authorize the Render
   GitHub App on `Klevin-G/BrassTune`, then trigger a deploy of `main`. Verify
   `/api/live`, `/api/ready`, `/api/version` return 200.
2. **Vercel:** Reconnect the `brass-tune` project's Git integration to
   `Klevin-G/BrassTune` (or supply a `VERCEL_TOKEN` scoped to the owning account),
   then deploy `main` to production.
3. **GitHub Actions:** Add a payment method / raise the Actions spending limit on
   the `Klevin-G` account so the required checks and the `Deploy` workflow can run.
4. **Native store:** Run on a physical iPhone/iPad for live-mic validation, then
   archive + sign + upload to TestFlight (requires Apple Developer credentials).

Everything code-side is complete, verified, and on `main`. The remaining work is
provider reconnection and billing that only the repository/account owner can perform.
