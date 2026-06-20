# Next Work

## Must Finish Before Closed-Beta Merge

- [P0] Verify post-fix GitHub Actions on PR #2
  - Owner type: repo
  - Acceptance criteria: latest PR head has Backend, Frontend, Security, and Swift Actions all green; Swift no longer fails at `Native app UI smoke test`.
  - Verification command or evidence: GitHub Actions for PR #2 on the latest pushed commit.

- [P0] Keep hosted smoke green after final push
  - Owner type: repo
  - Acceptance criteria: Render health, CORS, and hosted WebSocket still pass; Vercel preview protection is documented honestly if root returns `401`.
  - Verification command or evidence: `BRASSTUNE_WEB_BASE_URL=https://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted`.

- [P1] Keep release docs non-contradictory
  - Owner type: repo
  - Acceptance criteria: reports do not say the PR is ready to merge before latest Actions pass and do not call the product release ready.
  - Verification command or evidence: `grep -RIn "draft PR\|a77a669\|release ready\|bug-free\|fully secure" docs/release-readiness || true`.

## Should Finish During Closed Beta

- [P0] Run post-merge production smoke before inviting testers
  - Owner type: provider
  - Acceptance criteria: production Vercel and Render are on the merged commit; root, deep links, health, CORS, WebSocket, legal routes, export surfaces, and no-localhost checks pass.
  - Verification command or evidence: `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` or a green `.github/workflows/production-smoke.yml` run.

- [P0] Validate live Supabase auth and account lifecycle with disposable users
  - Owner type: provider
  - Acceptance criteria: sign-up, sign-in, duplicate/weak password handling, reset email, Apple OAuth, token refresh, export, account deletion, storage deletion, and Supabase identity cleanup are verified with disposable live accounts.
  - Verification command or evidence: completed `LIVE_AUTH_TEST_PLAN.md`; env-gated integration test run or recorded manual evidence tied to `HUMAN_ACTIONS.md`; Supabase logs/admin evidence with no secrets exposed.

- [P1] Close beta operations and data-policy setup
  - Owner type: product
  - Acceptance criteria: support contact, incident contacts, alert ownership, log access, backup/restore expectations, tester data policy, bug-report process, and triage labels are documented before external testers use the app.
  - Verification command or evidence: completed `HUMAN_ACTIONS.md` items 2 and 6 plus owner signoff on `CLOSED_BETA_HANDOFF.md` and `BETA_QA_GUIDE.md`.

- [P2] Unblock protected Vercel preview browser automation
  - Owner type: provider
  - Acceptance criteria: protected Vercel previews can be exercised by Playwright through an owner-approved bypass/share/public-preview decision.
  - Verification command or evidence: `cd frontend && E2E_BASE_URL=<preview> E2E_API_BASE_URL=https://brasstune.onrender.com E2E_WS_BASE_URL=wss://brasstune.onrender.com npm run e2e:hosted -- --project=chromium`.

- [P2] Improve teacher/student beta depth with real test personas
  - Owner type: product
  - Acceptance criteria: teacher, director, student, removed member, and non-member flows are exercised with realistic test accounts.
  - Verification command or evidence: browser journey evidence or beta tester checklist results with no real student data.

- [P2] Improve analytics and recommendation depth
  - Owner type: repo
  - Acceptance criteria: beta feedback identifies whether analytics, heat map, progress, and coach recommendations are understandable and useful.
  - Verification command or evidence: beta issue tracker, release journey updates, or product decision notes.

## Must Finish Before Public/App Store Release

- [P0] Complete Apple signing, archive, TestFlight, and App Store Connect setup
  - Owner type: Apple
  - Acceptance criteria: final bundle ID, team, profiles/certificates, App Store record, signed archive, TestFlight upload, review metadata, demo account or demo notes are complete.
  - Verification command or evidence: Xcode archive/export logs, App Store Connect/TestFlight processing evidence, completed `APP_STORE_CHECKLIST.md`.

- [P0] Validate physical iPhone/iPad microphone behavior with real brass input
  - Owner type: hardware
  - Acceptance criteria: supported iPhone and iPad pass quiet/noisy-room brass tests, permission denial, route changes, recording/playback/delete, and low/high brass cases.
  - Verification command or evidence: completed `PHYSICAL_DEVICE_PROTOCOL.md` with device models, OS versions, instruments, pass/fail notes.

- [P0] Replace or explicitly scope native fixture-backed product flows
  - Owner type: repo
  - Acceptance criteria: native practice/audio/analytics/ensemble/auth flows use production API/audio/auth paths or are explicitly scoped out of release claims.
  - Verification command or evidence: Xcode unit/UI/integration tests plus manual simulator/device evidence; no fixture-only claims in release docs.

- [P1] Finalize legal, privacy, SDK, and required-reason audits
  - Owner type: legal
  - Acceptance criteria: public Privacy Policy, Terms, support URL/email, age rating, export compliance, SDK privacy manifests/signatures, and required-reason API declarations are final.
  - Verification command or evidence: completed App Store privacy questionnaire, `PrivacyInfo.xcprivacy` review, dependency audit after final SDKs are pinned.

- [P1] Complete live account deletion verification
  - Owner type: provider
  - Acceptance criteria: app data, storage objects, memberships/invitations, exports where applicable, and Supabase identity/session cleanup are verified in a disposable live environment.
  - Verification command or evidence: env-gated live test output and redacted provider admin evidence.

## Security/Privacy Follow-Up

- [P1] Make account deletion cleanup durable
  - Owner type: repo
  - Acceptance criteria: deletion has retry/outbox behavior for Supabase identity/storage cleanup and recoverable partial-failure handling.
  - Verification command or evidence: backend regression tests covering Supabase failure/retry paths.

- [P1] Add repeatable live-provider integration coverage
  - Owner type: provider
  - Acceptance criteria: non-production Supabase project can run auth/export/delete/storage lifecycle tests without real user data.
  - Verification command or evidence: CI/manual env-gated test command documented; disposable project evidence redacted.

- [P2] Revisit WebSocket auth hardening after live auth stabilizes
  - Owner type: repo
  - Acceptance criteria: decide whether first-message auth is enough or short-lived WebSocket tickets are needed.
  - Verification command or evidence: threat-model update and WebSocket auth regression tests.

- [P2] Keep Supabase/RLS/CORS drift checks scheduled
  - Owner type: provider
  - Acceptance criteria: exact production origins remain configured; Supabase advisors and RLS grants are reviewed after migrations.
  - Verification command or evidence: Supabase advisor output, migration state, `anon_execute=false`, `authenticated_execute=false`, hosted CORS smoke.

- [P2] Run periodic dependency and incident-response reviews
  - Owner type: product
  - Acceptance criteria: dependency review cadence, audit logging policy, incident checklist, and drill owner are documented.
  - Verification command or evidence: completed review notes and updated `DEPLOYMENT_ROLLBACK.md` if process changes.

## Product/Engagement Follow-Up

- [P1] Deepen teacher/director workflows
  - Owner type: product
  - Acceptance criteria: rename/archive/delete ensembles, invitation acceptance, roster search, role/instrument edits, and report download are production-grade.
  - Verification command or evidence: Playwright journey coverage and beta tester task completion notes.

- [P1] Validate live auth error and recovery UX
  - Owner type: product
  - Acceptance criteria: confirmation, reset, Apple cancel/error, expired token, and deletion failure states are understandable to testers.
  - Verification command or evidence: disposable live-auth test notes plus E2E/manual screenshots with no secrets.

- [P2] Build closed-beta feedback loop
  - Owner type: product
  - Acceptance criteria: tester personas, bug-report template, severity triage, and weekly beta issue review are in place.
  - Verification command or evidence: completed `BETA_QA_GUIDE.md` run notes, beta tracker/report examples, and linked resolved issues.

- [P2] Define native parity roadmap
  - Owner type: product
  - Acceptance criteria: clear decision on whether native ships as simulator/demo shell, TestFlight beta, or waits for API/audio parity.
  - Verification command or evidence: updated release notes/checklist and native scope signoff.

- [P2] Run accessibility pass with real assistive tech
  - Owner type: product
  - Acceptance criteria: keyboard, screen-reader, Dynamic Type, VoiceOver, and mobile Safari behavior are checked by a human tester.
  - Verification command or evidence: completed `BETA_QA_GUIDE.md` accessibility checklist and filed follow-up issues.
