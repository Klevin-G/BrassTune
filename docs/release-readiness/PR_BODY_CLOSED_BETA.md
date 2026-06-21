## Status

Web closed-beta candidate pending owner-approved Render deployment and final production smoke; native engineering parity in progress; external provider/App Store/device gates remaining.

Not full release ready until live provider, Apple/App Store/legal, native production-depth, protected preview automation, physical-device gates, owner-approved Render deployment, and final production smoke are completed.

## Current branch

`arya/release-readiness-hardening`

## Verified

- Backend tests and GitHub Action
- Frontend tests/build/audit/E2E and GitHub Action
- Security GitHub Action
- Swift package/native simulator checks locally after final fix
- GitHub Backend and Security were green on PR head `72bb5a4681b0e4710dedaaeeb3449e6ddd124f38`; Frontend and Swift were still running at the last poll before the local guest-fetch follow-up.
- Vercel status was green on that baseline PR head.
- Production root, Render health, CORS, and basic WebSocket connectivity passed as baseline checks.
- Enhanced production WebSocket hardening smoke currently fails because production Render is stale relative to the local backend hardening.

## Current CI gate

PR head `72bb5a4681b0e4710dedaaeeb3449e6ddd124f38` added ensemble pre-membership report scoping, a working Score Practice focus control, hosted-smoke copy alignment, a non-editable Settings threshold affordance, refreshed device-simulation artifacts, and updated release evidence. A protected Vercel preview for that SHA was READY and passed backend/API/WS hosted checks, but route smoke exposed guest-mode protected API `401` console noise. The current local follow-up gates protected cloud fetches for guests. Re-check the latest pushed SHA, exact-SHA preview, and hosted smoke before updating the live PR body, merging, or deploying.

## Remaining external gates

- Vercel preview automation bypass for protected page journeys
- Owner-approved Render deployment of the new backend commit and final post-deploy hosted smoke
- Disposable live Supabase/Apple provider credentials for auth/account lifecycle tests
- Apple Developer/App Store Connect/signing/legal metadata
- Physical iPhone/iPad microphone validation with real brass input
- Native app production-depth beyond simulator fixture coverage
- Alert ownership, backup/restore, incident contacts, and review/demo account decisions

Use: `web closed-beta candidate pending owner-approved Render deployment and final production smoke; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not call the full product release ready.
