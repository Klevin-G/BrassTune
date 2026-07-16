# Post-Merge Production Checklist

Use this only after the current integration pull request is merged into `main`. Do not tag or promote production from this checklist without owner approval.

Precondition: the final integration head must have reviewed Backend, Frontend, Security, Swift, and exact-SHA preview results, or any external CI/service blocker must be recorded explicitly before merge. Production Supabase migrations must be applied in order, then Render must be owner-deployed to that backend commit before the capability-aware frontend is promoted and final hosted smoke can pass.

## Confirm Deployed State

1. Confirm local branch and `main` head:
   ```bash
   git fetch origin
   git checkout main
   git pull --ff-only origin main
   git rev-parse HEAD
   ```
2. Confirm Vercel production deployment is ready for the merged `main` commit in the Vercel dashboard or GitHub deployment status.
3. Confirm Render backend deploy state and commit in Render. The backend service is `https://brasstune-u8qj.onrender.com`.
4. Confirm the owner has recorded remaining external blockers in `HUMAN_ACTIONS.md`.
5. Confirm production deploy uses the repo-root GitHub workflow path. The root `vercel.json` builds `frontend`; do not assume the GitHub production deploy should run from `frontend`.
6. Confirm required secret names exist without printing values: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `RENDER_API_KEY`, `RENDER_SERVICE_ID`, `VITE_API_BASE_URL`, `VITE_WS_BASE_URL`, `VITE_SUPABASE_URL`, and `VITE_SUPABASE_PUBLISHABLE_KEY`. The frontend deploy workflow synchronizes the GitHub values into Vercel Production, re-pulls them, and must fail before build if any required value is empty or Google auth is not enabled.
7. Confirm Supabase migration state includes the baseline/readiness/RPC lockdown migrations, nine RLS-enabled app tables, `rls_auto_enable()` with `anon_execute=false` and `authenticated_execute=false`, unique class membership, rotated eight-character join codes, and Data API/storage lockdown.
8. Confirm `.github/workflows/render-keepalive.yml` is enabled only after owner approval for scheduled Actions usage. Keepalive is a cold-start mitigation, not an uptime guarantee.

## Hosted Smoke

Run from the repo root:

```bash
BRASSTUNE_WEB_BASE_URL=https://brasstune.vercel.app \
BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
BRASSTUNE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com \
npm run smoke:hosted
```

Manual HTTP checks:

```bash
curl -IL --max-time 30 https://brasstune.vercel.app
curl -IL --max-time 30 https://brasstune.vercel.app/settings
curl -fsS --max-time 70 https://brasstune-u8qj.onrender.com/api/health
curl -i -X OPTIONS https://brasstune-u8qj.onrender.com/api/health \
  -H "Origin: https://brasstune.vercel.app" \
  -H "Access-Control-Request-Method: GET"
```

## Browser Product Checks

1. Confirm root loads.
2. Confirm deep links refresh correctly: `/practice`, `/sessions`, `/analytics`, `/progress`, `/coach`, `/ensemble`, `/settings`, `/privacy`, `/terms`, `/support`.
3. Confirm demo onboarding.
4. Confirm demo practice.
5. Confirm record/stop.
6. Confirm session review.
7. Confirm export surfaces.
8. Confirm legal/support pages.
9. Confirm mobile viewport layout.
10. Confirm denied microphone state is understandable.
11. Confirm no browser request goes to `localhost` or `127.0.0.1`.
12. Confirm WebSocket uses `wss://brasstune-u8qj.onrender.com/ws/pitch`.
13. Confirm no provider secrets or private env values appear in built client output.

Suggested production hosted browser run after deployment:

```bash
cd frontend
E2E_START_LOCAL_SERVERS=0 \
E2E_BASE_URL=https://brasstune.vercel.app \
E2E_API_BASE_URL=https://brasstune-u8qj.onrender.com \
E2E_WS_BASE_URL=wss://brasstune-u8qj.onrender.com \
npm run e2e:hosted
```

Strict production content check after this branch is deployed:

```bash
cd frontend
E2E_START_LOCAL_SERVERS=0 \
E2E_BASE_URL=https://brasstune.vercel.app \
E2E_API_BASE_URL=https://brasstune-u8qj.onrender.com \
E2E_WS_BASE_URL=wss://brasstune-u8qj.onrender.com \
npm run e2e:hosted:strict
```

GitHub workflow check:

1. Run `.github/workflows/production-smoke.yml` with default production URLs.
2. Confirm the run passes root, Render health, CORS, and WebSocket app-level response.
3. If production is behind deployment protection or a different URL, set `BRASSTUNE_WEB_ACCESS_URL` as a GitHub variable and rerun without exposing tokens in logs.

## Rollback Confirmation

1. If production health, CORS, WebSocket, legal routes, export, auth, or account deletion fail, stop rollout.
2. Vercel rollback: promote the previous known-good deployment or redeploy the previous commit.
3. Render rollback: redeploy the previous known-good backend deploy or previous backend commit.
4. Database rollback: do not reverse migrations without data review. Prefer forward fixes unless a reversible migration has been reviewed.
5. Record incident start/end time, impacted surfaces, whether user data was affected, and owner-approved customer communication.

## Remaining External Gates To Record

- Live Supabase/Apple auth lifecycle evidence.
- Vercel preview automation bypass or public preview decision.
- Apple Developer signing, App Store Connect, legal metadata, support URL/email, age rating, export compliance, and review/demo access.
- Physical iPhone/iPad microphone and brass-room validation.
