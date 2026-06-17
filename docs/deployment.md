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
uvicorn app.main:app --reload
```

Frontend:

```bash
cd frontend
npm ci
npm run dev
```

## Vercel Frontend

`vercel.json` builds `frontend/` and serves `frontend/dist`.

Set these Vercel env vars:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `VITE_API_BASE_URL=https://brasstune.onrender.com`
- `VITE_WS_BASE_URL=wss://brasstune.onrender.com`

Do not set backend secret keys as `VITE_` variables.

## Render Backend

`render.yaml` defines the FastAPI web service.

Required Render env vars:

- `APP_ENV=production`
- `FRONTEND_ORIGIN`
- `CORS_ALLOWED_ORIGINS`
- `BRASSTUNE_DATABASE_URL` or `DATABASE_URL`
- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
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

## GitHub Secrets

Use secret stores only. Do not commit values.

- `SUPABASE_URL`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`
- `RENDER_DEPLOY_HOOK_URL`

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
