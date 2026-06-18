# Web E2E Report

## Implementation

- Added `frontend/playwright.config.ts`.
- Added `frontend/e2e/release-journeys.spec.ts`.
- Added `npm run e2e`.
- CI now installs backend dependencies and Playwright browsers before running the browser release journeys.

## Covered Journeys

- Guest route rendering for home, practice, sessions, analytics, progress, coach, ensemble, settings, audio lab, auth, and legal pages.
- Password reset request surface and Apple OAuth cancel/error callback surface.
- Onboarding focus trap and Escape close.
- Demo record/stop flow, saved session link, session review, relisten heading, note-performance heading.
- Settings legal links, account export button, disabled account deletion until confirmation/auth.
- Server-side ensemble authorization: student forbidden write returns `403`; director write returns `200`.
- Browser matrix: Chromium, Firefox, WebKit, mobile Chromium.

## Results

- `cd frontend && npm run e2e`
- Final local result: `24 passed`.
- Earlier run exposed selector/wait issues and missing browser binaries; after `npx playwright install firefox webkit` and test fixes, all projects passed.
- WebKit produced transient dev-server load warnings during a passing run; no browser journey failed.

## Not Covered

- Live Supabase email confirmation, reset email delivery, Apple OAuth provider exchange, and identity deletion are not covered without a disposable live Supabase project and Apple provider configuration.
- Hosted production browser mutation tests were not run to avoid mutating ordinary users.
- Production WebSocket is not passing hosted smoke; see `FINDINGS.md`.
