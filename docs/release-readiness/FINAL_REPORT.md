# BrassTune Final Release Report

Status: local release-hardening continuation complete for exercised automated gates. BrassTune is not release ready until the failed/blocked hosted WebSocket, live provider, App Store, Supabase project-drift, migration, and physical-device gates below are resolved.

## Summary

This continuation fixed the PR #2 Security and Frontend failure causes, hardened backend authorization/data lifecycle paths, removed WebSocket tokens from URLs, stabilized recording/import/playback behavior, cleaned production-facing web copy/internal controls, expanded browser journeys to mobile WebKit and hosted smoke, added CI artifacts/timeouts, and refreshed release blockers.

## Passed Local Gates

- Backend pytest: `46 passed`.
- Frontend Vitest: `15 tests passed`.
- Frontend build/typecheck: passed.
- Frontend dependency audit: `0 vulnerabilities`.
- Playwright local browser journeys: `35 passed`, `10 skipped` hosted-only checks.
- Hosted read-only Playwright smoke: `15 passed`.
- Device simulation: passed.
- Swift package tests: passed.
- Native app unit/UI test command: passed on dynamically selected iPhone simulator (`3 unit`, `1 UI`).
- Native Debug simulator builds: passed unsigned on dynamically selected iPhone and iPad simulators.
- Native Release simulator build: passed unsigned on dynamically selected iPhone simulator with `CODE_SIGNING_ALLOWED=NO`.
- Backend dependency/security scans: passed with five documented ignored advisories.
- Backend Bandit scan: passed.
- Gitleaks secret scan: passed locally, `25 commits` scanned with no leaks.
- Vercel root/deep-link smoke: passed.
- Render health/CORS smoke: passed after cold start.

## Failed Or Blocked Gates

- Hosted Render WebSocket handshake failed at connection level for `wss://brasstune.onrender.com/ws/pitch`.
- Supabase advisor reports live-project drift: public `SECURITY DEFINER` RPC executable by `anon`/`authenticated`.
- Existing Supabase migration is not a standalone clean-database baseline.
- Live Supabase email/password, reset, Apple OAuth, token refresh, and account deletion tests are blocked by missing disposable live credentials/provider setup.
- Apple signed archive, TestFlight/App Store upload, and App Store Connect metadata are blocked by missing Apple credentials and owner/legal metadata.
- Physical microphone/brass quality validation is blocked by hardware and performers.

## Deployment Impact

- No production deployment was performed.
- Deploy workflow still refuses to deploy from branches other than `main`, now with `environment: production`, concurrency, minimal permissions, and Render hook timeout.
- Frontend CI now runs local browser release journeys with bounded runtime and uploads Playwright artifacts.
- Security CI now grants Gitleaks the PR read permission it needs.
- Swift CI builds/tests the native app using dynamic simulator selection.

## Migration Impact

- No full baseline Supabase schema migration was added.
- Account deletion changes operate through existing models and explicit cleanup; Supabase cleanup is preflighted before local deletion, but no durable outbox exists.
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

Complete `HUMAN_ACTIONS.md`, fix hosted WebSocket routing, remediate Supabase advisor/migration blockers, run live Supabase/provider tests, run physical-device protocol, and complete Apple signing/archive/App Store Connect validation.
