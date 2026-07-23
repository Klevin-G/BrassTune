# Post-Merge Production Checklist

Use this only after the current integration pull request is merged into `main`. Do not tag or promote production from this checklist without owner approval.

Precondition: the final integration head must have reviewed Backend, Frontend, Security, Swift, and exact-SHA preview results, or any external CI/service blocker must be recorded explicitly before merge. The release intentionally spans two pull requests because `supabase db push` applies every pending migration. PR1 contains the database expand and compatible backend but no contract migration. PR2 adds the contract and promotes the final exact-SHA backend and frontend. Do not combine both migrations in one push.

## Ordered Production Rollout

1. Merge PR1 with additive migrations through `20260723021828_account_deletion_privacy_tombstones.sql` (expand). Confirm PR1 does not contain `20260723052642_enforce_account_deletion_terminal_privacy.sql`.
2. Record the PR1 `main` SHA. Inspect, dry-run, and apply all linked pending migrations while the contract file is absent.
3. Dispatch `.github/workflows/deploy.yml` with `target=backend` at the PR1 SHA. Require the captured Render deployment ID to reach provider status `live` with `commit.id` equal to the PR1 SHA, then require public readiness and exact `/api/version` to pass.
4. Confirm the privacy-aware backend initialized `deleted_identity_tombstone_config.enforcement_phase` as `expand` and scrubbed legacy terminal jobs. Retain the successful Render deployment ID and PR1 SHA as the post-contract rollback target.
5. Add the reserved `20260723052642_enforce_account_deletion_terminal_privacy.sql` contract migration in PR2, review it, and merge PR2.
6. Record the PR2 `main` SHA. Confirm the retained PR1 Render artifact and completed expand cleanup, then inspect, dry-run, and apply all linked pending migrations. The contract must fail closed if the compatibility checks are not satisfied.
7. Dispatch `.github/workflows/deploy.yml` first with `target=backend` and then with `target=frontend`, both at the exact PR2 SHA. Require backend evidence to identify the captured Render deployment ID at provider status `live` with `commit.id` equal to the PR2 SHA. Require Vercel evidence to show `READY`, production, matching deployment/canonical-alias IDs, and provider `githubCommitSha` equal to the PR2 SHA.
8. Allow `.github/workflows/production-smoke.yml` to consume the frontend deploy run's token-free evidence artifact. Require exact backend protocol smoke and strict hosted browser smoke to pass before declaring rollout complete.

Rollback boundary: before contract, the pre-PR1 backend can be restored. After contract, the retained privacy-aware PR1 Render deployment is the only approved backend rollback target; never redeploy a backend that writes unsanitized terminal deletion rows. The frontend can be rolled back independently to its previous known-good Vercel deployment.

## Confirm Deployed State

1. Confirm local branch and `main` head:
   ```bash
   git fetch origin
   git checkout main
   git pull --ff-only origin main
   git rev-parse HEAD
   ```
2. Confirm the frontend deploy's `production-deployment-evidence` artifact identifies the merged `main` SHA, the immutable Vercel deployment ID/URL, and canonical `https://brasstune.vercel.app` alias. Dashboard status alone is insufficient.
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

1. Prefer the automatic `workflow_run` smoke so it consumes the exact deploy run's evidence artifact. For a manual run, select `deployed_target` and supply full expected SHAs when they differ from the dispatched `main` SHA.
2. Confirm a backend deployment runs protocol smoke only; confirm a frontend deployment passes artifact verification, exact backend protocol, root, CORS, WebSocket, and strict browser smoke.
3. If production is behind deployment protection or a different URL, set `BRASSTUNE_WEB_ACCESS_URL` as a GitHub variable and rerun without exposing tokens in logs.

## Rollback Confirmation

1. If production health, CORS, WebSocket, legal routes, export, auth, or account deletion fail, stop rollout.
2. Vercel rollback: promote the previous known-good deployment or redeploy the previous commit.
3. Render rollback before contract: redeploy the previous known-good backend commit. After contract: redeploy only the retained privacy-aware PR1 Render deployment, identified by its recorded deploy ID and SHA; the pre-PR1 backend is incompatible.
4. Database rollback: do not reverse or relax the contract migration without data and constraint review. Prefer forward fixes.
5. Record incident start/end time, impacted surfaces, whether user data was affected, and owner-approved customer communication.

## Remaining External Gates To Record

- Live Supabase/Apple auth lifecycle evidence.
- Vercel preview automation bypass or public preview decision.
- Apple Developer signing, App Store Connect, legal metadata, support URL/email, age rating, export compliance, and review/demo access.
- Physical iPhone/iPad microphone and brass-room validation.
