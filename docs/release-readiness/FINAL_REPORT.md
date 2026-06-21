# BrassTune Final Web-First Report

Updated: 2026-06-21T05:51:09Z

## Current State

Phase 1 web/backend production certification is complete for the guest-first beta release. The final web main SHA is `6acb91d54a734e722ed937590aecb51dec53543c`.

`WEB_PRODUCTION_COMPLETION_GATE.md` contains the required pass line, so Phase 2 Swift work may begin from `main` after this evidence commit and tag are published.

## Implemented

- `/` is the authentication gateway; `/home` is the dashboard.
- Unsigned private deep links redirect to `/` with a safe `next` value; Continue as guest enters the intended route or `/home`.
- Returning signed-in users are held in a neutral restoration state before private routes render.
- Account-disabled builds show guest-first copy and hide account/provider controls unless configured.
- Provider buttons are gated by explicit provider env flags.
- Shared `design/brasstune-tokens.json`, `ThemeProvider`, pre-paint theme initialization, CSS custom-property themes, and Settings/gateway theme selectors were added.
- Visible dead/no-op controls were fixed across heat maps, microphone monitoring, guest session delete, export/copy status, ensemble forms, and score file inputs.
- Vercel security headers and API security headers were added.
- Backend JSON body limits, audio upload format validation, WebSocket deployed-origin behavior, unauthenticated socket limits, and production smoke defaults were hardened.
- Device simulation and hosted smoke were updated for the auth-gateway route model.

## Evidence

- Backend: `77 passed`.
- Backend hardening: `61 passed`.
- Frontend unit: `40 passed`.
- Frontend build: passed.
- Local E2E/accessibility: `80 passed`.
- Device simulation: passed.
- `npm audit --omit=dev`: 0 vulnerabilities.
- Bandit: no issues.
- Clean `uv` Python 3.12 `pip-audit`: no known vulnerabilities.
- PR #3 CI: Backend, Frontend, Security, Vercel passed.
- PR #4 CI: Frontend, Security, Vercel passed.
- Final production `npm run smoke:hosted`: passed.
- Final strict hosted Playwright: `7 passed`.

## Deployments

- Vercel production deployment: `dpl_6pScePaqbs8fYYD44wanhdgZkAPN`.
- Vercel production SHA: `6acb91d54a734e722ed937590aecb51dec53543c`.
- Render deployment ID: not exposed by available tooling; backend production was verified live by new security headers and hosted smoke.
- Rollback target: Vercel `dpl_2T68p4MQo8VbbAst4f7gnbHKitnP`.
- Release tag: `web-beta-2026.06.21.1`.

## Still Gated

- Live Supabase/Google/Apple account lifecycle without owner credentials.
- Apple signing/TestFlight/App Store submission.
- Physical-device brass/microphone validation.
- Native SwiftUI repository completion, now allowed to start as Phase 2 but not yet complete.
