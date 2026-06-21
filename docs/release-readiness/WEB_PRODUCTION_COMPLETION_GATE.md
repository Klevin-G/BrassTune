# Web Production Completion Gate

Updated: 2026-06-21T05:51:09Z

## Status

Phase 1 web/backend production certification is complete for the guest-first beta release.

## Release Identity

| Field | Value |
|---|---|
| Web completion branch SHA | `a642508ab638233e1fe297653147b8ccd3ceaf54` |
| Web completion merge SHA | `b956cf5bc6914fcb07fc6a18c83eac75c1d70446` |
| Hosted-smoke hotfix branch SHA | `d0cce2614710e17b955ae8f81815141ea6281df5` |
| Final web main SHA | `6acb91d54a734e722ed937590aecb51dec53543c` |
| Production auth mode | `disabled` guest-first release |
| Web version | `0.1.0-beta.1` |
| Release tag | `web-beta-2026.06.21.1` |
| GitHub Release URL | `https://github.com/aryasalem09/BrassTune/releases/tag/web-beta-2026.06.21.1` |

## Deployment Evidence

| Field | Value |
|---|---|
| Vercel production deployment ID | `dpl_6pScePaqbs8fYYD44wanhdgZkAPN` |
| Vercel production SHA | `6acb91d54a734e722ed937590aecb51dec53543c` |
| Vercel production aliases | `brass-tune.vercel.app`, `brass-tune-aryaswebsites.vercel.app`, `brass-tune-git-main-aryaswebsites.vercel.app` |
| Render deployment ID | Not exposed by available tooling; production backend was verified live by new API security headers and hosted smoke after the merge. |
| Render production evidence | `https://brasstune.onrender.com/api/health` returned `200` with `content-security-policy`, `permissions-policy`, `strict-transport-security`, `x-content-type-options`, and `x-frame-options`; observed `rndr-id` `3d161b7d-d73f-4d77`. |
| Rollback target | Vercel previous production deployment `dpl_2T68p4MQo8VbbAst4f7gnbHKitnP`; earlier baseline rollback candidate `dpl_9edFrpDGQgTgaaXNCUXJdKDMwwct` remains visible in Vercel history. |

## Local And CI Evidence

| Gate | Result |
|---|---|
| Backend full suite | `77 passed` |
| Backend hardening suite | `61 passed` |
| Frontend unit tests | `9 files`, `40 tests passed` |
| Frontend build/typecheck | Passed |
| Local E2E/accessibility | `80 passed` across Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit |
| Device simulation | Passed; report at `docs/device-simulation-report.md` |
| Frontend audit | `npm audit --omit=dev`: 0 vulnerabilities |
| Backend Bandit | No issues identified |
| Backend dependency audit | Direct `.venv` requirements audit failed during resolver venv `ensurepip`; clean `uv` Python 3.12 audit found no known vulnerabilities |
| PR #3 CI | Backend, Frontend, Security, and Vercel passed for `a642508ab638233e1fe297653147b8ccd3ceaf54` |
| PR #4 CI | Frontend, Security, and Vercel passed for `d0cce2614710e17b955ae8f81815141ea6281df5` |
| Diff hygiene | `git diff --check`: passed |

## Production Smoke

| Gate | Result |
|---|---|
| `npm run smoke:hosted` | Passed: root, Render health, CORS read/write preflights, WebSocket app response, query-token rejection, bad-Origin rejection |
| Strict hosted Playwright | `7 passed` with `E2E_STRICT_HOSTED_CONTENT=1` against `https://brass-tune.vercel.app` |
| Vercel headers | CSP, Permissions-Policy, Referrer-Policy, HSTS, and `X-Content-Type-Options` observed |
| Render headers | API CSP, Permissions-Policy, Referrer-Policy, HSTS, `X-Frame-Options`, and `X-Content-Type-Options` observed |
| Localhost/mixed-content check | Passed in hosted Playwright |

## Remaining External Gates

- Live Supabase, Google, and Apple account lifecycle remain owner-credential gated and are intentionally hidden/disabled in this guest-first release.
- Native SwiftUI implementation and App Store/TestFlight readiness remain separate Phase 2 gates.
- Physical-device microphone/brass validation remains hardware gated.

WEB PRODUCTION COMPLETION GATE: PASSED
