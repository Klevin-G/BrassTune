# Deployment

BrassTune is configured for:

- Frontend: Vercel
- Backend: Render
- Auth/storage/database: Supabase when configured
- Local fallback: SQLite and local audio files

## Local Development

Backend:

```bash
cd backend
python -m pip install -r requirements.txt
APP_ENV=local uvicorn app.main:app --reload
```

Production is the safe default when `APP_ENV` is absent. Local development and local browser automation must set `APP_ENV=local` or use the checked-in `.env.example` values in a local `.env` file.

Frontend:

```bash
cd frontend
npm ci
npm run dev
```

## Vercel Frontend

`vercel.json` builds `frontend/` and serves `frontend/dist`. Inspect `.vercel/repo.json` before changing CLI working directory assumptions; the linked project may already point at `frontend/`.

Set these Vercel env vars:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_API_BASE_URL=https://brasstune-u8qj.onrender.com`
- `VITE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com`

Do not set backend secret keys as `VITE_` variables.

Production and preview variables should be scoped deliberately in Vercel. Changes to Vercel env vars apply only to new deployments, so redeploy after changing `VITE_*` values.

Recommended production values:

```text
VITE_API_BASE_URL=https://brasstune-u8qj.onrender.com
VITE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com
VITE_SUPABASE_URL=<supabase project url>
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key only>
```

Do not add `SUPABASE_SECRET_KEY`, Render deploy hooks, GitHub tokens, Apple keys, or database URLs to Vercel frontend env vars.

## Render Backend

`render.yaml` defines the FastAPI web service.

Required Render env vars:

- `APP_ENV=production`
- `PYTHON_VERSION=3.11.15`, pinned through Render's supported environment-variable mechanism and synchronized by the exact-deploy workflow.
- `BRASSTUNE_SEED_DEMO_DATA` should be unset or `0` in production. Set `1` only for a deliberate disposable demo environment.
- `BRASSTUNE_AUTH_MODE=supabase`
- `BRASSTUNE_TRUST_PROXY=1`. Render must keep Uvicorn proxy rewriting disabled so the application receives the raw forwarding chain. Render's current guidance reads the true client from `X-Forwarded-For`, and its rate-limit example selects the first list entry; malformed first entries fall back to the socket peer instead of scanning later values.
- `FRONTEND_ORIGIN=https://brasstune.vercel.app`
- `CORS_ALLOWED_ORIGINS` as an exact comma-separated allowlist for production and approved preview origins.
- `CORS_ALLOWED_ORIGIN_REGEX` and `BRASSTUNE_ALLOW_CORS_REGEX` must be absent in production. The exact-deploy workflow deletes both service-level variables before every backend deploy so the backend uses only the exact origin allowlist.
- `BRASSTUNE_DATABASE_URL` or `DATABASE_URL` pointing to PostgreSQL. Render is IPv4-only, so use the Supabase pooler endpoint unless a compatible direct connection is explicitly available.
- `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET` for the scheduled account deletion retry executor.
- `BRASSTUNE_DELETION_TOMBSTONE_SECRET`, a dedicated stable secret of at least 32 bytes used only to HMAC deleted Supabase subjects. Never reuse a JWT, Supabase, storage, or maintenance credential. Back up this value in the production secret store: losing or rotating it without a deliberate tombstone migration makes readiness fail closed.
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_JWKS_URL` and `SUPABASE_JWT_SECRET` are reserved for a future JWKS validation path and are not required by the current backend.
- `SESSION_AUDIO_STORAGE_BACKEND=supabase`
- `SUPABASE_STORAGE_BUCKET=session-audio`
- `BRASSTUNE_MAX_OWNED_CLASSES_PER_USER=10`
- `BRASSTUNE_MAX_ACTIVE_CLASS_MEMBERSHIPS_PER_USER=20`
- `BRASSTUNE_MAX_PENDING_CLASS_INVITATIONS_PER_USER=20`
- `BRASSTUNE_MAX_SESSIONS_PER_USER=5000`
- `BRASSTUNE_MAX_AUDIO_STORAGE_BYTES_PER_USER=524288000` (500 MiB; replacing
  one session recording subtracts its prior size before quota evaluation)

Class quota values must be between `1` and `10000`; `0`, negative, or invalid
values fall back to the checked-in safe defaults. Session and audio quota `0`
values deliberately disable those quotas and should be used only in local/test
environments; negative or invalid values fall back to safe defaults.
Export resource caps cannot be disabled: zero, negative, or invalid
`BRASSTUNE_EXPORT_MAX_*` values fall back to their safe defaults. HTTP and
WebSocket rate/connection limits allow `0` only as a deliberate local/test
disable; negative or invalid values fall back to safe defaults.

Render's free web-service plan does not support pre-deploy commands. The start
command therefore runs the read-only `python -m app.db.check_ready` gate before
Uvicorn; an incomplete database schema or unsafe production configuration keeps
the new instance from becoming live. This gate does not apply migrations.

Account-deletion privacy uses an explicit two-PR expand/contract rollout.
`supabase db push` applies every pending migration, so the contract migration
must not exist in PR1:

1. Merge PR1 with the additive storage and account-deletion **expand** migration
   through `20260723021828_account_deletion_privacy_tombstones.sql`. PR1 must
   not contain
   `20260723052642_enforce_account_deletion_terminal_privacy.sql`.
2. At the PR1 `main` SHA, inspect and apply all linked pending migrations.
   Dispatch `target=backend` for that exact SHA and wait for Render readiness
   and `/api/version` to report it. The privacy-aware backend startup path
   initializes `deleted_identity_tombstone_config.enforcement_phase` as
   `expand` and scrubs legacy completed deletion jobs. Retain the successful
   Render deployment ID and PR1 SHA as the post-contract rollback target.
3. Add the reserved
   `20260723052642_enforce_account_deletion_terminal_privacy.sql` contract
   migration in PR2, review it, and merge PR2.
4. At the PR2 `main` SHA, confirm the retained PR1 Render artifact and completed
   expand cleanup, then inspect and apply all linked pending migrations. The
   contract migration must fail closed if the compatible backend has not
   completed the required cleanup.
5. Dispatch `target=backend` at the exact PR2 SHA, then dispatch
   `target=frontend` at the same PR2 SHA. The frontend workflow must verify that
   the canonical Vercel alias and provider `githubCommitSha` both identify the
   PR2 SHA before hosted smoke runs.

Use the Supabase commands once at the PR1 boundary while the contract file is
absent, and again at the PR2 boundary after it is merged:

```bash
supabase migration list --linked
supabase db push --linked --dry-run
supabase db push --linked
```

Before the contract migration, the previous backend remains a viable rollback.
After contract enforcement, the only approved backend rollback target is the
retained privacy-aware PR1 Render deployment; a pre-PR1 backend that writes
unscrubbed completed deletion jobs is incompatible. Roll the frontend back
independently when needed. Never reverse the contract migration without data and
constraint review.

The remainder of the Render start command uses `--no-proxy-headers`, a 256 KiB
WebSocket transport message cap, a 16-message WebSocket queue, a 100-connection
concurrency cap, and a 128-connection backlog. Do not replace this with
`--forwarded-allow-ips '*'`: that makes Uvicorn rewrite the socket peer before
the application can validate Render's header contract. See Render's [April 2026
DDoS guidance](https://render.com/articles/how-render-handles-ddos-attacks) and
[first-entry contract clarification](https://feedback.render.com/features/p/send-the-correct-xforwardedfor).

Liveness check for Render:

```text
https://brasstune-u8qj.onrender.com/api/live
```

Release readiness check:

```text
https://brasstune-u8qj.onrender.com/api/ready
```

Version identity check:

```text
https://brasstune-u8qj.onrender.com/api/version
```

WebSocket:

```text
wss://brasstune-u8qj.onrender.com/ws/pitch
```

WebSocket Origin checks mirror the HTTP CORS policy. Include
`https://brasstune.vercel.app` and any owner-approved preview/share origins;
prefer exact `CORS_ALLOWED_ORIGINS`/`FRONTEND_ORIGIN` entries.

Production deployment actively deletes `CORS_ALLOWED_ORIGIN_REGEX` and
`BRASSTUNE_ALLOW_CORS_REGEX` through Render's per-key environment-variable API.
Prefer exact origins for production and previews. Reintroducing a regex requires
an explicit, reviewed workflow change in addition to backend configuration.

### Account Deletion Retry

The backend exposes `POST /api/maintenance/account-deletions/retry` for retryable account deletion jobs. It is protected by the `X-BrassTune-Maintenance-Secret` header and the Render/GitHub secret-store value named `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET`.

`.github/workflows/account-deletion-retry.yml` invokes the endpoint every 15 minutes and on manual dispatch. Configure the same secret name in the GitHub `production` environment and Render before treating account deletion as operationally durable.

### Render Keepalive

`.github/workflows/render-keepalive.yml` pings the Render liveness endpoint every 10 minutes and on manual dispatch. The default URL is:

```text
https://brasstune-u8qj.onrender.com/api/live
```

Optional overrides:

- GitHub variable or secret: `RENDER_KEEPALIVE_URL`
- Manual workflow input: `health_url`

This is a cold-start mitigation for the current Render free-plan backend. It is not an uptime guarantee, alerting system, SLA, or substitute for a paid always-on service. If the workflow is disabled, delayed, rate-limited, or GitHub Actions is unavailable, Render may still spin down.

## GitHub Secrets

Use secret stores only. Do not commit values.

- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET`
- `BRASSTUNE_DELETION_TOMBSTONE_SECRET`
- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`
- `RENDER_API_KEY`
- `RENDER_SERVICE_ID`
- `RENDER_KEEPALIVE_URL` if overriding the default liveness URL

The manual deployment workflow lives at `.github/workflows/deploy.yml`.
Use `workflow_dispatch` with exactly one target, `backend` or `frontend`, and
follow the two-PR sequence above: PR1 expand -> PR1 backend -> PR2 contract ->
PR2 backend -> PR2 frontend. The backend job disables Render auto-deploy, then
calls Render's authenticated deploy API with the workflow commit SHA. This
prevents a push-triggered build from racing the exact-SHA release. Do not
replace it with an unpinned deploy hook.

Before requesting that exact deploy, the backend job requires the GitHub
Production secret `BRASSTUNE_DELETION_TOMBSTONE_SECRET` and upserts it through
Render's per-key environment-variable API. The value is never printed, and the
corresponding `render.yaml` entry uses `sync: false` so GitHub remains the sole
authority instead of creating a divergent Blueprint-generated key. The job also
pins `PYTHON_VERSION=3.11.15`, then deletes the legacy
`BRASSTUNE_ALLOW_CORS_REGEX` and `CORS_ALLOWED_ORIGIN_REGEX` variables. Render
`204` and already-absent `404` responses are accepted; every other response
blocks deployment.

The frontend deploy stores a token-free `production-deployment-evidence`
artifact containing the immutable Vercel deployment ID/URL, canonical alias,
provider revision metadata, and readiness state. The backend deploy stores the
same artifact name with its Render deployment ID and a freshly captured
`/api/version` revision after the backend readiness wait passes. Provider tokens
are never written to either artifact.

The hosted production smoke workflow lives at
`.github/workflows/production-smoke.yml`. It runs after a successful `Deploy`
workflow and can also be manually dispatched. A workflow-triggered smoke first
downloads and validates the deploy run's evidence artifact against
`workflow_run.head_sha`, then checks out that exact revision. Backend deploys
run the exact-SHA protocol smoke only. Frontend deploys require exact frontend
artifact evidence and the protocol smoke independently verifies that the live
backend reports the same revision before browser smoke runs. A manual dispatch
selects `deployed_target` and accepts explicit full frontend and backend SHAs,
defaulting to the dispatched `main` revision. It wraps:

```bash
BRASSTUNE_WEB_BASE_URL=https://brasstune.vercel.app \
BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
BRASSTUNE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com \
npm run smoke:hosted
```

For protected previews, provide `BRASSTUNE_WEB_ACCESS_URL` as an owner-approved Vercel share/bypass URL through GitHub variables. Do not put passwords or tokens in workflow logs.

## Phone Testing

Open the Vercel URL on iPhone/iPad Safari. Go to:

```text
/settings/audio-lab
```

Confirm mic permission, WebSocket URL, sample rate, RMS, confidence, lock status, and save eligibility.

For the local-video workflow, record with the native Camera app or choose a file from Photos/Files. BrassTune analyzes the media audio in the browser and stores only pitch analytics, not the source video.

## Troubleshooting

- Mic permission requires HTTPS on phones.
- If REST fails, verify `VITE_API_BASE_URL` and Render health.
- If live tuning fails, verify `VITE_WS_BASE_URL` and CORS origins.
- If playback fails while signed in, verify backend token validation and private bucket signed URL creation.
- If scheduled keepalive fails, check Render health and GitHub Actions availability before treating it as a production outage.
