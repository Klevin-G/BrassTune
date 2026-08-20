# Auth Provider Setup

Updated: 2026-08-19.

## Required configuration

| Provider/surface | Required configuration | Current state |
|---|---|---|
| Supabase browser auth | `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` | Required for deployed web auth. |
| Backend auth | Supabase URL/publishable key, provider-side secret/JWKS configuration as used by backend | Never expose secrets to browser/native bundles. |
| Google | Google OAuth client configuration, Supabase Google provider, callback allowlist | Native and web controls are enabled. Native Google completed once on a physical `.dev` build: callback, cold restore, sign-out, and signed-out relaunch were observed. Production web Google sign-in, session restore, and sign-out also passed with an authorized ordinary test identity. |
| Apple | Apple Team/Key/Services ID, native App ID capability, Supabase Apple provider, callback allowlist | The web Services ID is first in the provider client-ID list and the rotating secret is stored outside Git. A fresh Safari web lifecycle and an attended native physical lifecycle completed callback, restore, sign-out, and signed-out relaunch. |
| Native callbacks | Exact production and `.dev` Google callback allowlist entries plus matching app URL schemes | Keep the narrow, escaped Google callback entries and matching app URL schemes. Native Google and Apple callback/session lifecycles each have attended physical `.dev` evidence; both still require exact-candidate repetition. |

The authorized 2026-08-04 configuration pass enabled the Apple web Services ID
and updated the Supabase Apple provider without changing database schema,
Storage policy, or redirect entries. The checked-in config mirrors the public
client-ID order and references the rotating secret through
`SUPABASE_AUTH_APPLE_SECRET`; the secret itself remains outside Git. Do not place
Apple credentials, provider secrets, tokens, or signed URLs in repository
content or release evidence.

## Redirect URLs

Use narrowly scoped entries only:

- `https://brasstune.vercel.app/auth/callback`
- `https://brasstune.vercel.app/auth/reset-password`
- `http://localhost:5173/auth/callback`
- `http://localhost:5173/auth/reset-password`
- `https://*-kelvis-prject.vercel.app/auth/callback`
- `https://*-kelvis-prject.vercel.app/auth/reset-password`
- `com.brasstune.auth://oauth/google\?state=*`
- `com.brasstune.auth.dev://oauth/google\?state=*`

Never use a blanket `https://*.vercel.app` callback pattern.

The 2026-08-03 reconciliation removed a blanket Vercel callback pattern and retained only the narrow entries above, including escaped production/development native callbacks. Site URL and provider toggles/credentials were not changed. Keep this list narrow; changing it requires a separate security review and fresh provider-flow validation.

## Required live checks

Completed: native Google callback/cold-restore/sign-out/signed-out-relaunch on
physical `.dev`; production web Google sign-in/session restore/sign-out; fresh
Safari Apple callback/session restore/sign-out; and one attended native Apple
callback/restore/sign-out/signed-out-relaunch.

Still required: repeat both Apple lifecycles against the exact release candidate;
exercise cancel/error/relay-email and secret-rotation behavior; and complete
disposable-account email/reset, token refresh/expiry, export/delete,
cross-user-denial, Storage cleanup, and WebSocket first-message auth. Verify the
exact deployed revision and do not treat local behavior as hosted acceptance.
