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
- GitHub Backend, Frontend, Security, Swift, and Vercel checks were green on PR head `9b3766bc4241843c52b2a703c7ec923b4105f540` before the current local microphone/auth/smoke changes.
- Vercel status was green on that baseline PR head.
- Production root, Render health, CORS, and basic WebSocket connectivity passed as baseline checks.
- Enhanced production WebSocket hardening smoke currently fails because production Render is stale relative to the local backend hardening.

## Current CI gate

PR head `9b3766bc4241843c52b2a703c7ec923b4105f540` was verified green before this local pass. The current local worktree adds browser-local guest microphone pitch detection, safer provider identity linking, Google OAuth wiring, and stricter hosted WebSocket smoke checks. Re-check the latest pushed SHA and hosted smoke before updating the live PR body, merging, or deploying.

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
