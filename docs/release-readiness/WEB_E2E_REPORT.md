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
- Hosted read-only smoke checks root/deep links, backend health/CORS, secure WebSocket URL configuration, and the raw `/ws/pitch` upgrade/app-level auth response when hosted variables are supplied.

## Results

- `cd frontend && CI=true npm run e2e:local`
- Current local CI entrypoint result: `30 passed` across Chromium, Firefox, WebKit, mobile Chromium, and mobile WebKit. `npm run e2e:local` is scoped to `release-journeys.spec.ts`; hosted smoke remains an explicit command.
- `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted`
- Current production baseline root/API/CORS/basic WebSocket result: passed; enhanced query-token and bad-Origin WebSocket hardening checks fail until production Render is deployed to the new backend commit.
- `BRASSTUNE_WEB_BASE_URL=https://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted`
- Branch-preview hosted smoke result: passed with `15 passed`, `20 skipped`; Render health, CORS, and raw WebSocket upgrade passed, while preview page journeys and page-derived WebSocket URL checks were skipped because Vercel Authentication returns the Vercel login page without a share URL or automation bypass.
- `cd frontend && E2E_BASE_URL=https://brass-tune-9f0sicpxl-aryaswebsites.vercel.app E2E_API_BASE_URL=https://brasstune.onrender.com E2E_WS_BASE_URL=wss://brasstune.onrender.com npm run e2e:hosted -- --project=chromium`
- Protected preview Playwright result: backend health, CORS, secure WS URL, and raw WS upgrade tests passed; preview page route tests received `401` from Vercel Authentication. Vercel connector fetch verified the fresh preview deployment is accessible to the connected account.
- Current local pass on top of `36b29c8cff85f3364648763fd36d6472fb1ef8a3`: `CI=true npm run e2e:local` passed `75` tests across Chromium, Firefox, WebKit, mobile Chromium, and mobile WebKit after the ensemble privacy, Score Practice focus, hosted-smoke copy, and Settings affordance fixes. `npx playwright test e2e/hosted-smoke.spec.ts --project=chromium` passed locally with hosted-only checks skipped. Remote CI and exact-SHA preview must be rerun after committing and pushing this worktree. Production WebSocket hardening smoke must be rerun only after owner-approved Render deployment.

## Not Covered

- Live Supabase email confirmation, reset email delivery, Apple OAuth provider exchange, and identity deletion are not covered without a disposable live Supabase project and Apple provider configuration.
- Hosted production browser mutation tests were not run to avoid mutating ordinary users.
- Protected Vercel preview page automation needs an automation bypass or temporarily public preview access.
