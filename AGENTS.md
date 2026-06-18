# AGENTS.md - BrassTune

## Project

BrassTune is a brass-practice analytics product with a React/Vite web app, FastAPI backend, Supabase auth/storage integration, shared Swift pitch-domain package, and native SwiftUI iOS app work under `swift/BrassTuneApp`.

## Stack

- Frontend: React 18, TypeScript, Vite, Vitest, Playwright.
- Backend: FastAPI, SQLAlchemy, SQLite for local/dev tests, Supabase Auth/Storage for production identity and object storage.
- Native: Swift 6, Swift Package Manager, SwiftUI, Xcode simulator tests.
- Deployment: Vercel frontend, Render backend, Supabase project configuration, GitHub Actions.

## Commands

- Backend tests: `cd backend && .venv/bin/python -m pytest` or `cd backend && python -m pytest` when a venv is not present.
- Frontend unit tests: `cd frontend && npm test`.
- Frontend build/typecheck: `cd frontend && npm run build`.
- Frontend dependency audit: `cd frontend && npm audit --omit=dev`.
- Local browser journeys: `cd frontend && npm run e2e:local`.
- Hosted read-only smoke: `cd frontend && E2E_BASE_URL=https://brass-tune.vercel.app E2E_API_BASE_URL=https://brasstune.onrender.com E2E_WS_BASE_URL=wss://brasstune.onrender.com npm run e2e:hosted`.
- Device simulation: `cd frontend && npm run simulate:devices`.
- Swift package tests: `cd swift/BrassTuneCore && swift test`.
- Native app schemes: `xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj`.
- Native simulator build: use dynamically discovered simulators from `xcrun simctl list`; do not hard-code devices without checking availability.

## Directory Map

- `backend/app`: FastAPI API, schemas, services, auth, WebSocket, tests.
- `frontend/src`: React app, routes, state, components, legal/account lifecycle pages.
- `frontend/e2e`: Playwright release journeys.
- `fixtures`: shared domain fixtures where portable.
- `swift/BrassTuneCore`: shared pitch/tuning domain package.
- `swift/BrassTuneApp`: native SwiftUI iOS app, unit tests, UI tests.
- `.github/workflows`: CI, security, deploy, device simulation, Swift checks.
- `docs/release-readiness`: release audit reports and human-action blockers.

## Safety Rules

- Never commit `.env`, Supabase service keys, Vercel tokens, Render hooks, Apple credentials, signing identities, real user data, or recordings.
- Do not push directly to `main`, merge PRs, create tags, force-push, or change production infrastructure without explicit owner approval.
- Treat live Supabase, Vercel, Render, Apple Developer, and App Store Connect work as externally blocked unless credentials and explicit authorization are present.
- Do not claim physical microphone quality, Apple archive signing, or App Store readiness from simulator-only evidence.
- Keep raw large datasets, recordings, model artifacts, caches, Playwright traces, and Xcode derived data out of Git.

## Agent Fanout For Nontrivial Work

- Release integration lead: owns plan, branch, final matrix, docs, and commit.
- Web/auth agent: React flows, accessibility, browser journeys, Supabase client behavior.
- Backend/security agent: FastAPI auth, authorization, account lifecycle, payload limits, logging, storage privacy.
- Data/domain agent: pitch fixtures, backend/frontend/Swift parity, analytics rules.
- Native iOS agent: SwiftUI architecture, Keychain/auth surfaces, audio fixtures, simulator tests.
- Deployment agent: Vercel/Render/Supabase config names, CI, smoke tests, rollback notes.
- Reviewer agent: diff review, secret scan, large-file scan, remaining blockers.

## Definition Of Done

- Relevant automated checks pass locally, or failures are documented with exact blocker and evidence.
- Backend authorization and data-lifecycle changes have regression tests.
- Browser journeys exercise real local routes and backend authorization, not only route visits.
- Native claims distinguish Swift package tests, app builds, unit tests, UI tests, signed archives, and physical-device evidence.
- Release-readiness docs are updated when behavior, deployment, data handling, App Store readiness, or test status changes.
- `git status` is reviewed; only intentional files are staged.
