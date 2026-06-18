# Deployment And Rollback

## Current Hosted Surfaces

- Web: `https://brass-tune.vercel.app`
- Backend: `https://brasstune.onrender.com`
- Health: `https://brasstune.onrender.com/api/health`

## CI/Checks Added Or Preserved

- Backend pytest on PR/push.
- Frontend unit/build/audit plus Playwright browser release journeys.
- Security workflow with npm audit, pip-audit with exact ignored advisories, Bandit, and Gitleaks.
- Swift workflow for Swift package tests, native simulator build, native unit tests, and native UI smoke with dynamic simulator discovery.
- Deploy workflow is now guarded to run only from `main`.

## Deployment Procedure

1. Merge reviewed PR to `main`.
2. Confirm backend migrations are compatible with current production data.
3. Trigger deploy workflow from `main` only.
4. Frontend deploy uses Vercel CLI with `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.
5. Backend deploy uses Render deploy hook secret.
6. Run hosted smoke:
   - `curl -IL https://brass-tune.vercel.app`
   - `curl -IL https://brass-tune.vercel.app/settings`
   - `curl -fsS --max-time 70 https://brasstune.onrender.com/api/health`
   - CORS OPTIONS from Vercel origin.
   - Authenticated WebSocket handshake after Render route is fixed.

## Rollback Procedure

1. Stop rollout if health, CORS, auth, account deletion, or WebSocket checks fail.
2. Vercel: promote/revert to last known-good deployment in Vercel dashboard or rerun deploy for the previous commit.
3. Render: rollback to previous deploy from Render dashboard or redeploy previous commit.
4. Database: do not roll back migrations without reviewing data compatibility. Prefer forward fixes unless a documented reversible migration exists.
5. Supabase storage/auth: do not manually delete identities or buckets during rollback unless tied to a documented incident and owner approval.
6. Communicate affected surfaces, start/end times, and whether user data was impacted.

## Current Deployment Blocker

- Hosted WebSocket route returned `404`; do not claim production tuner WebSocket readiness until Render serves the current `/ws/pitch` route and an authenticated smoke passes.
