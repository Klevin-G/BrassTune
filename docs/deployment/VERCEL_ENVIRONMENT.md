# Vercel Environment

Status: required before real account/sync testing.

## Required Frontend Variables

```text
VITE_API_BASE_URL=https://brasstune-u8qj.onrender.com
VITE_WS_BASE_URL=wss://brasstune-u8qj.onrender.com
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

1. Store the required Production values in the matching GitHub Actions repository secrets.
2. Run the checked-in frontend deployment workflow. It synchronizes those values into Vercel Production without logging them, re-pulls the Vercel environment, and fails before build if any required value is empty.
3. Use Vercel project settings only to inspect the synchronized names/status or to configure an approved Preview environment; do not replace the Production values with blanks.
4. The deploy command records `githubCommitSha`, captures the immutable deployment ID/URL, then inspects Vercel provider metadata and `https://brasstune.vercel.app`. Require both the metadata SHA and canonical alias deployment ID to match the workflow's full `GITHUB_SHA`.
5. Retain the workflow's token-free `production-deployment-evidence` artifact for hosted smoke. It contains IDs, URLs, revision, target, and readiness only; it must never contain the Vercel token or frontend environment values.
6. Verify `/` and `/auth/sign-in` expose Google and email/password sign-in from fresh browser storage.
7. Verify Supabase redirect URLs include production and any approved preview callback/reset-password URL.

The frontend has a beta-safe Render fallback only for known BrassTune production/preview hostnames. Unknown hosted origins must use explicit environment configuration rather than silently calling production Render.

Do not add secret values to this file, `.env.example`, screenshots, logs, PR text, or chat.
