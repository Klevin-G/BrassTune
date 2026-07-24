# Supabase Auth Setup

Updated: 2026-07-23. Apply only as part of the reviewed post-merge rollout.

## Browser/native configuration

- Vercel: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`.
- Render: provider-side Supabase URL/publishable key/secret/JWKS configuration required by the backend. Do not expose provider-side keys in clients.
- Native Google: allow `com.brasstune.auth://oauth/google?state=*` in Supabase Auth redirect URLs.

## Narrow allowlist

- `https://brasstune.vercel.app/auth/callback`
- `https://brasstune.vercel.app/auth/reset-password`
- `http://localhost:5173/auth/callback`
- `http://localhost:5173/auth/reset-password`
- owner-restricted preview callback/reset patterns
- native Google callback above

Never permit a blanket `https://*.vercel.app/...` pattern.

## Provider state

Google is enabled on the linked project and its authorize-start redirect has been checked. Apple implementation is complete in the clients, but the linked Apple provider is disabled pending Apple Developer credentials and Supabase configuration. Keep production Apple UI disabled until live authorization is verified.

## Live verification

Use disposable accounts to verify sign-up, sign-in, reset, Google/Apple success/cancel/error, refresh, export/delete, storage cleanup, class authorization, and WebSocket first-message auth. Verify again after config pushes; local tests do not prove these provider outcomes.
