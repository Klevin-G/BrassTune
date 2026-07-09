# Supabase Auth Setup

Status: owner action required before live account creation. Guest practice works without this setup.

## Frontend Environment

Set these in Vercel for Production and any approved Preview environment:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Do not commit values to Git.

## Backend Environment

Set these in Render:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SECRET_KEY`
- `SUPABASE_JWKS_URL` if the backend is configured to validate JWTs through JWKS
- `BRASSTUNE_ACCOUNT_DELETION_RETRY_SECRET`

Keep the secret key provider-side only. It must never be exposed to the browser or committed.

## Redirect URLs

Configure Supabase Auth redirect allowlist for:

- Local development: `http://localhost:5173/auth/callback`
- Local development: `http://localhost:5173/auth/reset-password`
- Production: `https://brass-tune.vercel.app/auth/callback`
- Production: `https://brass-tune.vercel.app/auth/reset-password`
- Approved preview: the exact Vercel preview URL, only while that preview is in use

Apple provider setup remains an external owner task through Apple Developer and Supabase provider settings.

## Verification

After setting env vars, redeploy Vercel and Render, then verify:

1. Sign-in no longer shows account-disabled mode.
2. Sign-up, sign-in, callback, refresh, password reset, export, and deletion pass with disposable accounts.
3. Browser responses never expose service keys or raw provider tokens.
4. Guest practice still works when signed out.
