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

## Codex Project Snapshot

Purpose: Brass-practice analytics product with web, backend, Supabase, shared Swift domain, and native iOS work.

Stack: React 18, TypeScript, Vite, Vitest, Playwright, FastAPI, SQLAlchemy, SQLite, Supabase, Swift 6/SPM, SwiftUI, Vercel, Render, GitHub Actions.

Important directories:
- frontend/ - React/Vite app and Playwright journeys
- backend/ - FastAPI app, services, schemas, tests
- swift/BrassTuneCore/ - shared pitch/tuning package
- swift/BrassTuneApp/ - native SwiftUI app
- fixtures/ - shared domain fixtures
- docs/release-readiness/ - release audit and blocker docs
- .github/workflows/ - CI/deploy/security checks

Setup commands:
- cd frontend && npm install
- cd backend && python -m venv .venv && .venv/bin/python -m pip install -r requirements.txt
- Inspect .vercel/repo.json before assuming Vercel working directory.

Build commands:
- cd frontend && npm run build
- cd swift/BrassTuneCore && swift test
- xcodebuild -list -project swift/BrassTuneApp/BrassTuneApp.xcodeproj

Test commands:
- cd backend && .venv/bin/python -m pytest
- cd frontend && npm test
- cd frontend && npm run e2e:local
- cd frontend && npm run simulate:devices

Lint/typecheck commands:
- cd frontend && npm audit --omit=dev
- Backend security checks in CI include pip-audit and bandit where available.

Run/dev commands:
- cd backend && uvicorn app.main:app --reload
- cd frontend && npm run dev

Deployment commands:
- Vercel frontend and Render backend deploy through configured workflows; do not change production config or secrets without approval.
- cd frontend && E2E_BASE_URL=https://brass-tune.vercel.app E2E_API_BASE_URL=https://brasstune.onrender.com E2E_WS_BASE_URL=wss://brasstune.onrender.com npm run e2e:hosted

Coding and safety conventions:
- Never commit env files, Supabase service keys, Vercel tokens, Render hooks, Apple credentials, recordings, local DBs, Playwright traces, or Xcode derived data.
- Keep release-readiness docs honest about simulator versus physical-device evidence and hosted smoke blockers.
- Use linked Vercel metadata rather than guessing root/frontend deploy directory.

Git rules:
- Check `git status --short --branch` before edits and handoff.
- Do not use broad staging in dirty repos; stage only explicit paths when the user later asks for a commit.
- Do not commit, push, force-push, rewrite history, delete files, or mutate production infrastructure without explicit approval.
- Keep secrets, credentials, tokens, private keys, env files, build output, caches, downloaded data, model artifacts, and oversized generated files out of Git.

Known risks:
- Production auth/storage/deploy work requires external credentials and explicit approval.
- Hosted WebSocket/Render/Supabase behavior must be verified live before release claims.
- Native app and Apple release evidence are distinct from web/backend evidence.

## Codex Subagent Policy

Codex should use parallel subagents for nontrivial work, but fanout must be justified by independent workstreams. Prefer 4-8 agents for normal tasks. Use 8-12 only for large independent modules, audits, migrations, data pipelines, or test/review sweeps.

Do not spawn agents that edit the same file at the same time. Keep `max_depth = 1` unless the repo-specific config and setup notes explain why `2` is justified. Always use a read-only scout before major edits, and always use independent tester/reviewer agents before claiming completion.

Use CSV fanout for repeated independent tasks like file audits, package reviews, migration target reviews, route/component checks, artifact inventories, or per-module security reviews. Keep `max_concurrency` bounded so local builds, browser tests, Xcode, GPU work, or data pipelines do not overload the machine.

## Recommended Agent Roles

Use the global `repo_scout`, `architect`, `implementer`, `tester`, `reviewer`, `security_auditor`, `docs_writer`, and `release_manager` agents as the default team. This repo also defines project-scoped agents for:
- release integration lead
- web auth agent
- backend security agent
- data domain parity agent
- native ios agent
- deployment smoke agent
- artifact hygiene reviewer

Start meaningful work with a read-only scout, then split implementation by ownership area. Keep docs and validation agents independent from implementation agents.

## Definition Of Done

- The request is implemented or the blocker is documented with exact evidence.
- Relevant commands from this AGENTS.md were run, or skipped commands are listed with a reason.
- Diffs are reviewed for scope, secrets, large artifacts, generated files, and unsafe operations.
- Documentation and Codex setup notes are updated when commands, architecture, data flow, deployment, or risks change.
- Final handoff lists files changed, commands run, validation status, skipped tests, and remaining risks.
