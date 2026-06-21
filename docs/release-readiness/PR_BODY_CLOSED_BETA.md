## Status

Web/backend closed-beta production path deployed and smoke-passed in guest/auth-disabled mode; native engineering parity in progress; external provider/App Store/device gates remaining.

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
- Enhanced production WebSocket hardening smoke passed after Render deploy `dep-d8rmafreo5us73di4as0` and Vercel production deploy `dpl_5jR3Qnv71v58YfWN77VxrLihYPk9`.

## Current CI gate

PR #2 head `ede7960fb0f543a8d0b329357199d782257a0d46` passed Backend, Frontend, Security, Swift, and Vercel checks before merge. PR #2 was merged into `main` as `4bda5691a05988471e412519bbfdcf4078430ee0`, then Vercel and Render production were deployed and hosted smoke passed. Re-check exact-SHA CI/deploy/smoke for any future hotfix commit.

## Remaining external gates

- Vercel preview automation bypass for protected page journeys
- Disposable live Supabase/Apple provider credentials for auth/account lifecycle tests
- Apple Developer/App Store Connect/signing/legal metadata
- Physical iPhone/iPad microphone validation with real brass input
- Native app production-depth beyond simulator fixture coverage
- Alert ownership, backup/restore, incident contacts, and review/demo account decisions

Use: `web/backend closed-beta production path deployed and smoke-passed in guest/auth-disabled mode; native engineering parity in progress; external provider/App Store/device gates remaining`.

Do not call the full product release ready.
