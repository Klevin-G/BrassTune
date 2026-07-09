# BrassTune Release Status — 2026-07-09 (authoritative)

This supersedes all earlier "PASSED / blocked / production certified" language in
the release-readiness ledger; those files are historical June-beta evidence.

## Architecture (current)

- **Frontend:** Vercel project `brass-tune` (team `kelvis-prject`) → https://brass-tune.vercel.app
- **Backend:** Render web service `srv-d97sq6m7r5hc73dcbhr0` → https://brasstune-u8qj.onrender.com (auto-deploys `main`)
- **Database / Auth / Storage:** Supabase project `yznziwewxrlwnwiynlvl` (org `nuqhkyceoxcjnpozttpg`, us-east-2)
- Frontend calls the Render backend cross-origin (`VITE_API_BASE_URL`, with a hosted-default fallback). Audio playback uses Supabase signed URLs.

## Decision

- **Web: DEPLOYED.** Backend live and verified; frontend deployed on Vercel with env wired.
- **Native (iOS): code COMPLETE** on `main`; remaining is physical-device validation + Apple signing/TestFlight (owner/hardware).

`main` HEAD: `0f318b9` (backend commit live on Render). Only branch is `main`.

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
