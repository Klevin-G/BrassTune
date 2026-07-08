# Vercel Environment

Status: required before real account/sync testing.

## Required Frontend Variables

```text
VITE_API_BASE_URL=https://brasstune.onrender.com
VITE_WS_BASE_URL=wss://brasstune.onrender.com
VITE_SUPABASE_URL=<from Supabase>
VITE_SUPABASE_PUBLISHABLE_KEY=<from Supabase>
```

Optional provider buttons are hidden unless explicitly enabled in Vercel:

```text
VITE_AUTH_GOOGLE_ENABLED=true
VITE_AUTH_APPLE_ENABLED=true
```

Only set those flags after the matching Supabase Auth provider is configured and the redirect allowlist includes the production and approved preview callback URLs.

## Setup Steps

1. Open the Vercel project settings.
2. Add the variables for Production and any approved Preview environments.
3. Redeploy Vercel so the variables are baked into the frontend bundle.
4. Verify `/auth/sign-in` no longer shows account-disabled mode when Supabase is configured.
5. Verify Supabase redirect URLs include production and any approved preview callback/reset-password URL.

The frontend has a beta-safe Render fallback only for known BrassTune production/preview hostnames. Unknown hosted origins must use explicit environment configuration rather than silently calling production Render.

Do not add secret values to this file, `.env.example`, screenshots, logs, PR text, or chat.
