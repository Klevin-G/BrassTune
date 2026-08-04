# Vercel Environment

Updated: 2026-08-04. Production deployment remains pending exact-SHA CI and the rollout checklist.

## Required production variables

```text
VITE_API_BASE_URL=https://brasstune-u8qj.onrender.com
VITE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com
VITE_SUPABASE_URL=<Supabase project URL>
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key only>
VITE_AUTH_GOOGLE_ENABLED=true
VITE_AUTH_APPLE_ENABLED=true
```

The checked-in deployment workflow synchronizes these values without logging them, validates the production pull, builds, deploys, and verifies the canonical alias plus `githubCommitSha` against the exact workflow SHA.

## Provider behavior

Provider buttons are not hidden when a provider is disabled: they remain visible with an unavailable state. Google and Apple are deliberately synchronized enabled. Apple must remain `true` after the owner-confirmed Apple Developer configuration and Supabase Apple provider enablement. A fresh web authorize/callback test is still required after redeploy; changes to either production variable require a redeploy and a fresh hosted sign-in smoke.

## Redirect boundaries

Allow only production, localhost, and owner-restricted preview callback/reset URLs in Supabase. Do not use a blanket `*.vercel.app` pattern. The native Google callback requires its configured custom-scheme allowlist separately.

Never store backend secrets, provider keys, or service-role credentials in a `VITE_*` variable.
