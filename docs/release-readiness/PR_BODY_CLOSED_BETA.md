## Status

Closed-beta candidate for owner-controlled hosted web/backend testing, pending final GitHub Actions success on the latest post-fix head.

Not full release ready until live provider, Apple/App Store/legal, native production-depth, protected preview automation, and physical-device gates are completed.

## Current branch

`arya/release-readiness-hardening`

## Verified

- Backend tests and GitHub Action
- Frontend tests/build/audit/E2E and GitHub Action
- Security GitHub Action
- Swift package/native simulator checks locally after final fix
- Vercel deploy
- Render health/CORS/WebSocket
- Hosted smoke

## Current CI gate

PR head `d05fe773499393ad50af15c59322f66adeb98c11` was not merge-ready because Swift failed at `Native app UI smoke test`. The local follow-up fixes the UI smoke root cause and must be verified by the next Swift GitHub Action before merge.

## Remaining external gates

- Vercel preview automation bypass for protected page journeys
- Disposable live Supabase/Apple provider credentials for auth/account lifecycle tests
- Apple Developer/App Store Connect/signing/legal metadata
- Physical iPhone/iPad microphone validation with real brass input
- Native app production-depth beyond simulator fixture coverage
- Alert ownership, backup/restore, incident contacts, and review/demo account decisions

Use: `closed-beta candidate, external provider/App Store/device gates remaining`.

Do not call the full product release ready.
