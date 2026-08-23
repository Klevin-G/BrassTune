# Deployment
Project attribution: Kelvin Guo, Arya Salem.

BrassTune uses Vercel for the web app, Render for FastAPI, and Supabase for auth/storage/database. The canonical production web alias, once the exact-SHA deployment is verified, is `https://brasstune.vercel.app`.

## Local development

```bash
cd backend && APP_ENV=local uvicorn app.main:app --reload
cd frontend && npm run dev
```

Use `APP_ENV=local` for local backend runs. Never put provider secrets in frontend variables or commit local env files.

## Release sequence

1. Pass the final local backend fix, then exact-SHA self-hosted Backend, Frontend, Security, and Swift checks.
2. Apply the reviewed Supabase expand migrations and configuration; retain the privacy-aware backend rollback target.
3. Deploy Render at the merged SHA, verify `/api/live`, `/api/ready`, `/api/version`, REST, and WebSocket behavior.
4. Deploy Vercel at the same SHA and require its canonical alias/provider commit metadata to match.
5. Run hosted smoke and disposable account lifecycle tests. Create/apply the terminal privacy contract migration only after expand cleanup is proven.

## Auth deployment flags

Production deploys synchronize Google as enabled and Apple as `false` until live Apple configuration is ready. Both provider choices remain visible in the product; unavailable is a user-facing state. See `docs/deployment/VERCEL_ENVIRONMENT.md` and `docs/deployment/SUPABASE_AUTH_SETUP.md`.

## Avatar read abuse control

The authenticated `GET /api/users/me/avatar` route has a distinct per-client
read budget. Its optional backend environment setting is
`BRASSTUNE_AVATAR_READ_RATE_LIMIT_PER_MINUTE`; the safe default is `30` reads
per minute. A non-secret deployment example is:

```text
BRASSTUNE_AVATAR_READ_RATE_LIMIT_PER_MINUTE=30
```

This setting applies only to that `GET` route. `PUT /api/users/me/avatar` is an
account mutation and continues to use
`BRASSTUNE_EXPENSIVE_MUTATION_RATE_LIMIT_PER_MINUTE`, not the avatar-read
budget. Configure these values in the backend secret/environment store, never
in the frontend bundle or committed `.env` file.

## Boundaries

No local or hosted-web result proves physical iPhone/iPad microphone performance, Apple signing, archive validity, TestFlight, or App Store acceptance.
