# Locked Release Scope

Updated: 2026-06-21T00:13:54Z
Branch: `arya/release-readiness-hardening`
Base SHA for this pass: `eef7f865085859d877703c7652b941aaf6815134`

This is the release-scope freeze for the final stabilization pass. New P2/P3 ideas belong in `POST_RELEASE_BACKLOG.md`; only new P0/P1 security, data-loss, deployment, critical-journey, dead-control, accessibility-blocking, or explicitly required native parity findings may enter this file.

## P0/P1 Web And Backend Scope

| ID | Scope item | Status | Evidence |
|---|---|---|---|
| LRS-001 | Backend must not trust browser-supplied note labels, cents, status, or instrument metadata for saved pitch samples. | Fixed locally | Server canonicalizes saved frames from frequency/session instrument/reference pitch; hardening tests passed. |
| LRS-002 | Pitch sample API must reject frames whose instrument differs from the session instrument. | Fixed locally | `test_pitch_frame_instrument_must_match_session_instrument` passed. |
| LRS-003 | Guest/local pitch frames must enforce selected instrument ranges. | Fixed locally | Frontend music/local detector tests passed. |
| LRS-004 | Account deletion must not delete external identity before local media/data cleanup succeeds or is durably queued. | Fixed locally | Deletion job ledger and ordering regressions passed. |
| LRS-005 | Ensemble analytics must not expose sessions from before membership or during removed membership intervals. | Fixed locally | Membership interval fields and reactivation regression passed. |
| LRS-006 | Auth/provider UI must not show raw Supabase, provider, URL, env, or stack errors to normal users. | Fixed locally | Friendly auth error mapper added; frontend build passed. |
| LRS-007 | Failed signed-in recording start must not leave an opened microphone stream active. | Fixed locally | Practice start failure cleanup added; frontend build passed. |
| LRS-008 | PDF Score Practice must use a real local PDF reader, not iframe-only browser PDF behavior. | Fixed locally | Lazy PDF.js canvas reader added; frontend build passed. |
| LRS-009 | Metronome running controls must update live and UI must not label scheduled queue math as acoustic measurement. | Fixed locally | Live refs and queue-stat wording added; frontend build passed. |
| LRS-010 | Production Render must serve current WebSocket hardening behavior. | Red gate | Hosted smoke against production still showed stale query-token and bad-Origin behavior before this patch; must redeploy and re-smoke. |
| LRS-011 | Vercel production must serve merged `main` at the final SHA. | Red gate | Current production was still `0e5eea2...` before this patch. |
| LRS-012 | Exact-SHA PR CI and preview must be green after the final commit is pushed. | Red gate | Current local changes are not yet committed/pushed. |

## Native Scope

| ID | Scope item | Status | Evidence |
|---|---|---|---|
| LRS-101 | Native app must not present fixture/demo sessions as measured user performance. | Red gate | Read-only native audit found fixture-backed practice data still shown downstream. |
| LRS-102 | Native metronome, score reader, repository-side mic path, and auth paths must be production-equivalent before native parity claims. | Red gate | Current evidence is simulator build/tests only; physical-device and real native feature parity are not proven. |
| LRS-103 | Native visual language must be closer to web before claiming parity. | Red gate | Native audit found functional but plain light screens versus web dark/gold cockpit design. |

## Deployment And Release Gates

Do not merge PR #2, tag, create a GitHub release, invite testers, or declare production current until:

- Latest pushed PR head SHA is verified immediately before merge.
- Required GitHub checks are green on that exact SHA.
- Vercel exact-SHA preview is browser-verified through an owner-approved protection bypass/share flow.
- Render production is deployed to the final backend commit and hosted WebSocket hardening smoke passes.
- Vercel production serves merged `main`.
- Final hosted production smoke passes.
- Rollback targets are recorded.
