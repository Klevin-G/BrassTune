# Web E2E Report

## Implementation

- Added `frontend/playwright.config.ts`.
- Added `frontend/e2e/release-journeys.spec.ts`.
- Added `frontend/e2e/hosted-smoke.spec.ts`.
- Added `npm run e2e:local` and `npm run e2e:hosted`.
- CI now installs backend dependencies and Playwright browsers before running the browser release journeys.

## Covered Journeys

- Guest route rendering for home, practice, sessions, analytics, progress, coach, ensemble, settings, audio lab, auth, and legal pages.
- Password reset request surface and Apple OAuth cancel/error callback surface.
- Onboarding focus trap and Escape close.
- Demo record/stop flow, saved session link, session review, relisten heading, note-performance heading.
- Settings legal links, account export button, disabled account deletion until confirmation/auth.
- Server-side ensemble authorization: student forbidden write returns `403`; director write returns `200`.
- Browser matrix: Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit.
- Hosted read-only smoke checks root/deep links, backend health/CORS, and secure WebSocket URL configuration.

## Results

- `cd frontend && npm run e2e:local`
- Final local result: `35 passed`, `10 skipped` for hosted-only optional API/WS checks.
- `cd frontend && E2E_BASE_URL=https://brass-tune.vercel.app E2E_API_BASE_URL=https://brasstune.onrender.com E2E_WS_BASE_URL=wss://brasstune.onrender.com npm run e2e:hosted`
- Final hosted read-only result: `15 passed`.
- A strict hosted legal/content run is intentionally opt-in with `E2E_STRICT_HOSTED_CONTENT=1` because current Vercel production has not deployed this branch yet.

## Not Covered

- Live Supabase email confirmation, reset email delivery, Apple OAuth provider exchange, and identity deletion are not covered without a disposable live Supabase project and Apple provider configuration.
- Hosted production browser mutation tests were not run to avoid mutating ordinary users.
- Raw hosted WebSocket handshake is still not passing; the hosted smoke only verifies secure URL configuration until Render routing/deployment is fixed.
