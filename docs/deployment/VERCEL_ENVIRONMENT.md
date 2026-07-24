# Vercel Environment

Updated: 2026-07-23. Production deployment remains pending exact-SHA CI and the rollout checklist.

## Required production variables

```text
VITE_API_BASE_URL=https://brasstune-u8qj.onrender.com
VITE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com
VITE_SUPABASE_URL=<Supabase project URL>
VITE_SUPABASE_PUBLISHABLE_KEY=<publishable key only>
VITE_AUTH_GOOGLE_ENABLED=true
VITE_AUTH_APPLE_ENABLED=false
```

The checked-in deployment workflow synchronizes these values without logging them, validates the production pull, builds, deploys, and verifies the canonical alias plus `githubCommitSha` against the exact workflow SHA.

## Provider behavior

Provider buttons are not hidden when a provider is disabled: they remain visible with an unavailable state. Google is deliberately synchronized enabled. Apple is deliberately synchronized as `false` until Apple Developer configuration, Supabase Apple provider enablement, and a disposable live authorize test have succeeded. Change Apple only through the protected production variable and redeploy.

## Redirect boundaries

Allow only production, localhost, and owner-restricted preview callback/reset URLs in Supabase. Do not use a blanket `*.vercel.app` pattern. The native Google callback requires its configured custom-scheme allowlist separately.

Never store backend secrets, provider keys, or service-role credentials in a `VITE_*` variable.
