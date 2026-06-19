# Post-Merge Production Checklist

Use this only after PR #2 is merged into `main`. Do not merge, tag, or promote production from this checklist without owner approval.

Precondition: the latest PR #2 head must have green Backend, Frontend, Security, Swift, and Vercel checks. PR head `91ca605b64a58e582b2e8f6b2d06c9f80ba3b6c7` was verified green before the final docs consistency pass; re-check the latest head if any later commit is pushed before merging.

## Confirm Deployed State

1. Confirm local branch and `main` head:
   ```bash
   git fetch origin
   git checkout main
   git pull --ff-only origin main
   git rev-parse HEAD
   ```
2. Confirm Vercel production deployment is ready for the merged `main` commit in the Vercel dashboard or GitHub deployment status.
3. Confirm Render backend deploy state and commit in Render. The backend service is `https://brasstune.onrender.com`.
4. Confirm the owner has recorded remaining external blockers in `HUMAN_ACTIONS.md`.
5. Confirm production deploy uses the repo-root GitHub workflow path. The root `vercel.json` builds `frontend`; do not assume the GitHub production deploy should run from `frontend`.
6. Confirm required secret names exist without printing values: `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`, `VITE_API_BASE_URL`, `VITE_WS_BASE_URL`, Supabase frontend vars, and the Render deploy hook.
7. Confirm Supabase migration state includes the baseline/readiness/RPC lockdown migrations, nine RLS-enabled app tables, and `rls_auto_enable()` with `anon_execute=false` and `authenticated_execute=false`.

## Hosted Smoke

Run from the repo root:

```bash
BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app \
BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com \
BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com \
npm run smoke:hosted
```

Manual HTTP checks:

```bash
curl -IL --max-time 30 https://brass-tune.vercel.app
curl -IL --max-time 30 https://brass-tune.vercel.app/settings
curl -fsS --max-time 70 https://brasstune.onrender.com/api/health
curl -i -X OPTIONS https://brasstune.onrender.com/api/health \
  -H "Origin: https://brass-tune.vercel.app" \
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
12. Confirm WebSocket uses `wss://brasstune.onrender.com/ws/pitch`.
13. Confirm no provider secrets or private env values appear in built client output.

Suggested production hosted browser run after deployment:

```bash
cd frontend
E2E_START_LOCAL_SERVERS=0 \
E2E_BASE_URL=https://brass-tune.vercel.app \
E2E_API_BASE_URL=https://brasstune.onrender.com \
E2E_WS_BASE_URL=wss://brasstune.onrender.com \
npm run e2e:hosted
```

Strict production content check after this branch is deployed:

```bash
cd frontend
E2E_START_LOCAL_SERVERS=0 \
E2E_BASE_URL=https://brass-tune.vercel.app \
E2E_API_BASE_URL=https://brasstune.onrender.com \
E2E_WS_BASE_URL=wss://brasstune.onrender.com \
npm run e2e:hosted:strict
```

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
