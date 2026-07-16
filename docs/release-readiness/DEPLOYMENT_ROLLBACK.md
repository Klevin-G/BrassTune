# Deployment And Rollback

## Current Hosted Surfaces

- Web: `https://brasstune.vercel.app`
- Backend: `https://brasstune-u8qj.onrender.com`
- Health: `https://brasstune-u8qj.onrender.com/api/health`

## CI/Checks Added Or Preserved

- Backend pytest on PR/push.
- Frontend unit/build/audit plus Playwright browser release journeys.
- Security workflow with npm audit, pip-audit with exact ignored advisories, Bandit, and Gitleaks.
- Swift workflow for Swift package tests, native simulator build, native unit tests, and native UI smoke with dynamic simulator discovery.
- Deploy workflow is guarded to run only from `main`, uses the `production` GitHub environment, has bounded timeouts, minimal read permissions, deploy concurrency, and an exact-SHA Render API request.

## Deployment Procedure

1. Merge reviewed PR to `main`.
2. Confirm backend migrations are compatible with current production data.
3. Trigger deploy workflow from `main` only.
4. Frontend deploy uses Vercel CLI with `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`.
5. Backend deploy uses `RENDER_API_KEY` and `RENDER_SERVICE_ID` to disable auto-deploy and request the exact workflow commit from Render's deploy API.
6. Run hosted smoke:
   - `BRASSTUNE_WEB_BASE_URL=https://brasstune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com npm run smoke:hosted`
   - `curl -IL https://brasstune.vercel.app`
   - `curl -IL https://brasstune.vercel.app/settings`
   - `curl -fsS --max-time 70 https://brasstune-u8qj.onrender.com/api/health`
   - CORS OPTIONS from Vercel origin.
   - `E2E_BASE_URL=https://brasstune.vercel.app E2E_API_BASE_URL=https://brasstune-u8qj.onrender.com E2E_WS_BASE_URL=wss://brasstune-u8qj.onrender.com npm run e2e:hosted`
   - For protected previews, provide `E2E_VERCEL_SHARE_URL` or an automation bypass; connector-only access is not enough for local Playwright.

## Rollback Procedure

1. Stop rollout if health, CORS, auth, account deletion, or WebSocket checks fail.
2. Vercel: promote/revert to last known-good deployment in Vercel dashboard or rerun deploy for the previous commit.
3. Render: rollback to previous deploy from Render dashboard or redeploy previous commit.
4. Database: do not roll back migrations without reviewing data compatibility. Prefer forward fixes unless a documented reversible migration exists.
5. Supabase storage/auth: do not manually delete identities or buckets during rollback unless tied to a documented incident and owner approval.
6. Communicate affected surfaces, start/end times, and whether user data was impacted.

## Current Deployment Notes

- Hosted WebSocket handshake passed after Render deployed exact commit `395a9d29870b25a7aadf161dc1d69c988bdaa841`.
- After PR merge, run `POST_MERGE_PRODUCTION_CHECKLIST.md` before inviting production closed-beta testers.
- Protected Vercel preview page journeys still need an automation bypass; direct connector fetch and hosted API/WS smoke passed.
- `render.yaml` no longer provides a broad `https://.*\.vercel\.app` CORS regex by default. Configure exact production and preview origins before deployment.
