# Web Production Completion Gate

Updated: 2026-07-23. Candidate source revision: `428a123`.

The web candidate has local unit/build/audit and browser evidence, but it is not a production completion claim. Completion requires final backend race-fix validation, exact-SHA self-hosted CI, Supabase expand/config rollout, same-SHA Render/Vercel deployments, and hosted smoke.

Google and Apple provider buttons remain visible in the UI. Google is enabled in the linked Supabase project. Apple remains visible but unavailable because the live provider is disabled; the deployment workflow keeps `VITE_AUTH_APPLE_ENABLED=false` until Apple Developer and Supabase setup plus a live authorize test are complete.

Require the canonical alias `https://brasstune.vercel.app` and the Vercel provider commit identity to match the deployed SHA before reporting web production completion.
