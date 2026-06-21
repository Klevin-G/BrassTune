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
- `VITE_API_BASE_URL=https://brasstune.onrender.com`
- `VITE_WS_BASE_URL=wss://brasstune.onrender.com`

Do not set backend secret keys as `VITE_` variables.

Production and preview variables should be scoped deliberately in Vercel. Changes to Vercel env vars apply only to new deployments, so redeploy after changing `VITE_*` values.

Recommended production values:

```text
VITE_API_BASE_URL=https://brasstune.onrender.com
VITE_WS_BASE_URL=wss://brasstune.onrender.com
VITE_SUPABASE_URL=<supabase project url>
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key only>
```

Do not add `SUPABASE_SECRET_KEY`, Render deploy hooks, GitHub tokens, Apple keys, or database URLs to Vercel frontend env vars.

## Render Backend

`render.yaml` defines the FastAPI web service.

Required Render env vars:

- `APP_ENV=production`
- `BRASSTUNE_SEED_DEMO_DATA` should be unset or `0` in production. Set `1` only for a deliberate disposable demo environment.
- `FRONTEND_ORIGIN=https://brass-tune.vercel.app`
- `CORS_ALLOWED_ORIGINS` as an exact comma-separated allowlist for production and approved preview origins.
- Leave `CORS_ALLOWED_ORIGIN_REGEX` empty in production unless the owner approves a tightly anchored temporary preview pattern.
- `BRASSTUNE_DATABASE_URL` or `DATABASE_URL`
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_JWKS_URL` and `SUPABASE_JWT_SECRET` are reserved for a future JWKS validation path and are not required by the current backend.
- `SESSION_AUDIO_STORAGE_BACKEND=supabase`
- `SUPABASE_STORAGE_BUCKET=session-audio`

Health check:

```text
https://brasstune.onrender.com/api/health
```

WebSocket:

```text
wss://brasstune.onrender.com/ws/pitch
```

WebSocket Origin checks use explicit `CORS_ALLOWED_ORIGINS`/`FRONTEND_ORIGIN` entries, not `CORS_ALLOWED_ORIGIN_REGEX`. Include `https://brass-tune.vercel.app` and any owner-approved preview/share origins explicitly when WebSocket smoke must pass from those hosts.

### Render Keepalive

`.github/workflows/render-keepalive.yml` pings the Render health endpoint every 10 minutes and on manual dispatch. The default URL is:

```text
https://brasstune.onrender.com/api/health
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
- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`
- `RENDER_DEPLOY_HOOK_URL`
- `RENDER_API_KEY`
- `RENDER_SERVICE_ID`
- `RENDER_KEEPALIVE_URL` if overriding the default health URL

The manual deployment workflow lives at `.github/workflows/deploy.yml`.
Use `workflow_dispatch` with `target=frontend`, `backend`, or `all`.

The hosted production smoke workflow lives at `.github/workflows/production-smoke.yml`. It currently runs on manual dispatch. It wraps:

```bash
BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app \
BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com \
BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com \
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
