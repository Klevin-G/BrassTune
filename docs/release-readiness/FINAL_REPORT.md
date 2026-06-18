# BrassTune Final Release Report

Status: local release-hardening pass complete for exercised automated gates. BrassTune is not release ready until the failed/blocked hosted, live provider, App Store, and physical-device gates below are resolved.

## Summary

This pass hardened backend authorization/data lifecycle paths, completed web account-lifecycle surfaces, expanded browser journeys, added a native SwiftUI app with Supabase Auth REST wiring and simulator build/test coverage, added CI guardrails, and documented release blockers.

## Passed Local Gates

- Backend pytest: `41 passed`.
- Frontend Vitest: `13 tests passed`.
- Frontend build/typecheck: passed.
- Frontend dependency audit: `0 vulnerabilities`.
- Playwright browser journeys: `24 passed`.
- Device simulation: passed.
- Swift package tests: passed.
- Native Debug iPhone build: passed.
- Native Release iPhone build: passed.
- Native iPad Debug build: passed.
- Native app unit tests: passed.
- Native UI smoke: passed.
- Backend dependency/security scans: passed with five documented ignored advisories.
- Backend Bandit scan: passed.
- Secret pattern scan: passed.
- Vercel root/deep-link smoke: passed.
- Render health/CORS smoke: passed after cold start.

## Failed Or Blocked Gates

- Hosted Render WebSocket smoke failed with `404` for `/ws/pitch` and `/api/ws/pitch`.
- Live Supabase email/password, reset, Apple OAuth, token refresh, and account deletion tests are blocked by missing disposable live credentials/provider setup.
- Apple signed archive, TestFlight/App Store upload, and App Store Connect metadata are blocked by missing Apple credentials and owner/legal metadata.
- Physical microphone/brass quality validation is blocked by hardware and performers.
- Combined native `xcodebuild test` is not used as a gate because CoreSimulator returned `Busy` between unit/UI runner launches; unit and UI targets pass separately.

## Deployment Impact

- No production deployment was performed.
- Deploy workflow now refuses to deploy from branches other than `main`.
- Frontend CI now runs local browser release journeys.
- Swift CI now builds/tests the native app using dynamic simulator selection.

## Migration Impact

- No explicit database migration file was added.
- Account deletion changes operate through existing models and cascading deletes plus explicit cleanup.
- Production deploy should be paired with a clean-database startup/migration smoke and current-schema smoke.

## Rollback

- Use Vercel previous deployment promotion or redeploy previous commit for frontend rollback.
- Use Render previous deploy or redeploy previous commit for backend rollback.
- Avoid destructive DB rollback unless a reviewed reversible migration exists.

## Changed Areas

- Backend auth, routes, WebSocket, schemas, storage, CORS, hardening tests.
- Frontend auth, settings/account deletion, legal pages, ensemble selection, accessibility/layout, Playwright.
- Native SwiftUI app/project/tests.
- GitHub Actions, AGENTS, release-readiness docs.

## Required Before Calling Release Ready

Complete `HUMAN_ACTIONS.md`, fix hosted WebSocket routing, run live Supabase/provider tests, run physical-device protocol, and complete Apple signing/archive/App Store Connect validation.
