# BrassTune Final Web-First Report

Updated: 2026-06-21T06:30:28Z

## Current State

Phase 1 web/backend production certification is complete for the guest-first beta release. The final web evidence commit on `main` is `1c998d5480f52b5fcf0e2c143f5078893caead66`.

`WEB_PRODUCTION_COMPLETION_GATE.md` contains the required pass line. Phase 2 Swift work has been completed locally on `arya/final-swift-completion`; `NATIVE_REPOSITORY_COMPLETION_GATE.md` contains the native repository engineering pass line.

## Implemented

### Web

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

### Native

- Native auth-first launch, session restoration, Continue as guest, sign-out to gateway, email/password, reset, and Apple token exchange surfaces.
- Shared generated native theme tokens, six themes, gateway/Settings selectors, and high-contrast/system handling.
- Liquid Glass wrappers with iOS 26 `glassEffect` and reduced-transparency/solid fallbacks.
- Five-tab iPhone shell plus iPad `NavigationSplitView`.
- Normal native recording path through `AVAudioSession` and `AVAudioEngine`; deterministic pitch generation remains UI-test-only.
- Local recording playback, text export, deletion, and persistent session metadata.
- Native metronome scheduler/click engine and persisted settings.
- Native Score Practice file/photo/camera import metadata with PDF page counting, VisionKit unavailable-state handling, markers, and local delete.
- Native analytics/progress/coach states derive from local recorded sessions.

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
- Swift package: `3` tests passed.
- Native Debug simulator build: passed, no warnings.
- Native app unit tests: `9` XCTest cases passed.
- Native UI smoke: `1` XCUITest passed.
- Native Release simulator build: passed, no warnings.
- Native screenshot: `docs/release-readiness/native-screenshots/iphone-home-tabs-2026-06-21.jpg`.

## Deployments

- Vercel production deployment: `dpl_6pScePaqbs8fYYD44wanhdgZkAPN`.
- Vercel final evidence production deployment: `dpl_CWTdt7Fhs9P69H5tayyKWW3zDQm7`.
- Vercel final evidence production SHA: `1c998d5480f52b5fcf0e2c143f5078893caead66`.
- Render deployment ID: not exposed by available tooling; backend production was verified live by new security headers and hosted smoke.
- Rollback target: Vercel `dpl_2T68p4MQo8VbbAst4f7gnbHKitnP`.
- Release tag: `web-beta-2026.06.21.1`.

## Still Gated

- Live Supabase/Google/Apple account lifecycle without owner credentials.
- Apple signing/TestFlight/App Store submission.
- Physical-device brass/microphone validation.
- Final native branch merge and post-merge web regression smoke.
