# Auth Provider Setup

Updated: 2026-07-24.

## Required configuration

| Provider/surface | Required configuration | Current state |
|---|---|---|
| Supabase browser auth | `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` | Required for deployed web auth. |
| Backend auth | Supabase URL/publishable key, provider-side secret/JWKS configuration as used by backend | Never expose secrets to browser/native bundles. |
| Google | Google OAuth client configuration, Supabase Google provider, callback allowlist | Linked provider is enabled; complete live lifecycle verification remains pending. |
| Apple | Apple Team/Key/Services ID, native App ID capability, Supabase Apple provider, callback allowlist | Code complete; provider disabled pending credentials/setup. |
| Native callbacks | `com.brasstune.auth://oauth/google?state=*` allowlist and app URL scheme | The Supabase TOML glob escapes the literal query marker as `google\\?state=*`; push it before live iOS Google QA. |

The Supabase CLI is already authenticated for project and migration reads; no Supabase account password or database password is required for those checks. Apple enablement still starts in Apple Developer because Supabase cannot generate the required Apple Team/App/Services/Key credentials. Do not give Codex an Apple login or password.

## Redirect URLs

Use narrowly scoped entries only:

- `https://brasstune.vercel.app/auth/callback`
- `https://brasstune.vercel.app/auth/reset-password`
- `http://localhost:5173/auth/callback`
- `http://localhost:5173/auth/reset-password`
- owner-restricted Vercel preview patterns for both callback and reset-password
- `com.brasstune.auth://oauth/google?state=*`

Never use a blanket `https://*.vercel.app` callback pattern.

## Required live checks

Run only with disposable users: email signup/sign-in/reset, Google and Apple success/cancel/error paths, token refresh and expiration, export/delete, and WebSocket first-message auth. Verify the exact deployed revision and do not treat local OAuth tests as live provider evidence.
