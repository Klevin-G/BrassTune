# BrassTune Release Engineering Instructions

## Goal
Build and verify a release candidate for the hosted web app, FastAPI service, and native SwiftUI iOS app. Do not call the product releasable only because it compiles or its screens render. Follow `.github/codex/prompts/release-candidate-master.md` and record test evidence in `docs/release-readiness/`.

## Work model
For broad tasks, spawn the maximum useful number of specialized subagents supported by the environment. Cover all role tracks in the master prompt, using waves when concurrency is limited. Begin with read-only audits, then give implementation agents separate files, directories, or worktrees. A lead agent owns integration and the complete final test run.

Each agent reports what it inspected, reproducible issues, changes and commits, commands and results, and remaining risks.

## Evidence
Clearly distinguish browser automation, hosted-service testing, mock integration tests, iOS Simulator tests, and physical-device tests. Do not claim microphone quality, native pickers, production Apple authentication, or App Store Connect configuration was verified without the correct real environment. Do not hide failures, flaky checks, warnings, missing configuration, or placeholders. Keep evidence sanitized and do not commit private configuration or user data.

## Branch safety
- `main` is production. Use a reviewed pull request with green checks rather than pushing directly.
- `swift-migration` is stale and must be synchronized with current `main` before native work.
- Preserve and reverify Vercel and Render deployment behavior.
- Keep commits cohesive and avoid unrelated history changes.
- Do not merge or tag while a release gate is failing or unknown.

## Test gates
- Backend: full pytest suite, clean-database migrations, dependency checks, authorization tests, and account-data lifecycle tests.
- Frontend: TypeScript build, Vitest, dependency audit, Playwright user journeys, accessibility checks, and hosted smoke tests.
- Auth: real environment-gated sign-up, confirmation behavior, sign-in, sign-out, session restoration, completed password reset, invalid states, and account deletion. Merely opening the auth page is not an auth test.
- Ensemble: director and student accounts, group and roster lifecycle, analytics, exports, and negative authorization cases.
- Swift core: `swift test` and parity fixtures for every portable module.
- iOS: Xcode build, unit, integration, and UI tests on dynamically discovered phone and iPad simulators, including orientations, appearance, Dynamic Type, and accessibility identifiers.
- Hosted stack: Vercel, Render API health, WebSocket behavior, CORS, Supabase redirects/auth/storage, and cleanup of test records.

## Privacy and product quality
Enforce permissions on the server and test cross-user, cross-group, and role-escalation attempts. Implement complete in-app account deletion for account-creating apps. Provide public privacy and terms pages at stable URLs and expose them in both clients. Audit App Store privacy disclosures, retention, SDK behavior, privacy manifests, required-reason APIs, purpose strings, encryption declarations, age rating, and review notes. Legal placeholders are release blockers.

Every shipping flow needs sensible loading, empty, error, offline, permission-denied, and retry behavior. Support keyboard use, screen readers, contrast, Dynamic Type, reduced motion, and focus management. Validate external data at API boundaries.

## Completion
Complete implementation rather than stopping at a plan. The final report must list defects fixed, commits and pull requests, exact test evidence, production checks, App Store readiness, and all remaining human-only actions. Use the phrase `release ready` only when all gates and external requirements are truly complete.