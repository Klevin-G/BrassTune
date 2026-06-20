# Auth Provider Setup

Updated: 2026-06-20 UTC.

## Required Provider Configuration

No secret values belong in this file or in Git.

| Provider | Required Names | Notes |
|---|---|---|
| Supabase Auth | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, backend secret key, JWKS URL | Backend production startup now requires Supabase URL and a secret/API key. |
| Frontend Supabase | `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` | Browser bundles must never receive Supabase service-role or secret keys. |
| Apple | Apple Team ID, Services ID, native bundle ID, redirect URLs | Configure Supabase Apple provider and Apple Developer capability before live tests. |
| Google | Web/iOS OAuth client IDs, redirect URLs | Web code now exposes a Supabase Google OAuth path with `openid email profile`; provider credentials, callback allowlist, branding review, and native Google setup remain owner-blocked. |
| Vercel/Render origins | `CORS_ALLOWED_ORIGINS`, `FRONTEND_ORIGIN`, `VITE_API_BASE_URL`, `VITE_WS_BASE_URL` | WebSocket origin checks require explicit origins, not only regex. |

## Local Development

- Use `APP_ENV=local` for local backend runs.
- Local tests set `APP_ENV=local` through `backend/app/tests/conftest.py`.
- Playwright and device simulation launch the backend with local CORS origins.

## Required Live Tests

- Email sign-up and duplicate account handling.
- Weak password and provider error copy.
- Email confirmation and reset email delivery.
- Apple OAuth success, cancel, and callback error.
- Google OAuth success, cancel, callback error, and minimal-scope verification.
- Token refresh and expired-token recovery.
- Account export before delete.
- Account deletion across backend rows, audio objects, memberships/invitations, and Supabase identity cleanup.
- WebSocket first-message auth with a live Supabase token.

## Blocker

These tests require disposable live users and owner-approved Supabase/Apple/Google provider configuration. Do not run destructive lifecycle tests on ordinary production accounts.
