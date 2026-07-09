# BrassTune Release Status — 2026-07-09 (authoritative)

This supersedes all earlier "PASSED / blocked / production certified" language in
the release-readiness ledger; those files are historical June-beta evidence.

## Architecture (current)

- **Frontend:** Vercel project `brass-tune` (team `kelvis-prject`) → https://brass-tune.vercel.app
- **Backend:** Render web service `srv-d97sq6m7r5hc73dcbhr0` → https://brasstune-u8qj.onrender.com (auto-deploys `main`)
- **Database / Auth / Storage:** Supabase project `yznziwewxrlwnwiynlvl` (org `nuqhkyceoxcjnpozttpg`, us-east-2)
- Frontend calls the Render backend cross-origin (`VITE_API_BASE_URL`, with a hosted-default fallback). Audio playback uses Supabase signed URLs.

## Decision

- **Web: DEPLOYED and verified live.** Frontend on Vercel + backend on Render + Supabase, end-to-end verified (below).
- **Native (iOS): code COMPLETE** on `main`; remaining is physical-device validation + Apple signing/TestFlight (owner/hardware).

`main` HEAD deployed. Only branch is `main`.

## Live verification (2026-07-09)

- Frontend `https://brass-tune.vercel.app` → HTTP 200; production bundle has the new
  Supabase URL + anon key (index chunk) and Render backend URL (client chunk) baked in.
- Backend `https://brasstune-u8qj.onrender.com` → `/api/health|live|version|ready` 200;
  `/api/version` commit matches `main`; `/api/ready` = postgresql/production; instruments
  read from Supabase; protected routes 401; CORS preflight from the Vercel origin allowed.
- Supabase auth: anon sign-in path → `400 invalid_credentials` (working); service-key admin
  API reachable. JWKS ES256 present.
- Vercel Deployment Protection **disabled** (public site).

## Operational note — Vercel git-author policy

The `kelvis-prject` Vercel team blocks deployments whose git commit author is not a team
member (`seatBlock: TEAM_ACCESS_REQUIRED`). Commits authored by `aryasalem09` are blocked;
commits authored by the owner (`klevin-g`) deploy normally. To let all pushes to `main`
auto-deploy the frontend, add `aryasalem09` to the Vercel team (or relax the git-author
policy). The Render backend has no such restriction and auto-deploys any push to `main`.

## Providers (verified live 2026-07-09)

- **Supabase `yznziwewxrlwnwiynlvl`:** ACTIVE_HEALTHY. 5 migrations applied →
  10 tables (`users`, `practice_sessions`, `pitch_samples`, `note_events`,
  `groups`, `group_members`, `invitations`, `instrument_profiles`,
  `recommendations`, `account_deletion_jobs`) + `rls_auto_enable` RPC; RLS enabled
  on every table; `session-audio` bucket **private**. Verified over Postgres + the
  backend readiness gate (all checks `ok`).
- **Render backend (`brasstune-u8qj.onrender.com`):** LIVE, commit `0f318b9`.
  `/api/health`, `/api/live`, `/api/version`, `/api/ready` all 200;
  `/api/ready` → `database_backend: postgresql`, `environment: production`;
  `/api/instruments` reads from Supabase; protected routes 401; CORS preflight from
  `https://brass-tune.vercel.app` returns the allow-origin header. Start command uses
  `--proxy-headers` (accurate per-client rate limiting); healthcheck `/api/live`.
  Plan: free (cold starts expected; `render-keepalive` workflow mitigates).
- **Vercel frontend (`brass-tune.vercel.app`):** deployed from root dir `frontend`
  (Vite). Build-time env `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`,
  `VITE_API_BASE_URL`, `VITE_WS_BASE_URL` set for Production + Preview.
- **GitHub Actions secrets/variables:** updated to the new Supabase/Render/Vercel
  values (Klevin-G admin). CI itself remains billing-gated on the account, but every
  gate is reproduced green locally and both providers auto-deploy on push to `main`.

## Local validation (reproduced from CI definitions)

Backend `pytest` 104 · Frontend unit 50 · Frontend build · Local e2e 95 ·
`npm audit --omit=dev` 0 vulns · `pip-audit` clean · Bandit clean.
BrassTuneCore 3 · native app unit 18 · iPhone Debug/Release + iPad Debug builds ·
UI smoke pass (on an unloaded machine).

## Remaining owner actions

1. **Live acceptance with a real account** — sign up on https://brass-tune.vercel.app,
   record a session, upload/play audio, export, delete account. (Backend + DB + storage are wired; this exercises the full flow with the real Supabase keys.)
2. **Native store release** — physical iPhone/iPad mic validation, then archive + sign + upload to TestFlight (Apple Developer credentials).
