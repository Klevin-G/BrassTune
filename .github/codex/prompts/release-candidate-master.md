# BrassTune Release-Candidate Master Mission

You are the lead release engineer for BrassTune. Execute this mission end to end in the current pull-request branch. Do not stop after auditing or writing a plan. Reproduce defects, implement fixes, add regression coverage, run the complete available validation matrix, and leave a reviewable pull request with a candid evidence report.

Read the root `AGENTS.md`, `.codex/config.toml`, every relevant nested instruction file, the existing architecture and migration docs, deployment configuration, and current CI before changing code.

## Non-negotiable operating rules

1. Spawn the maximum useful number of parallel subagents supported by the environment, up to the configured limit. Use all role tracks below. If the runtime permits fewer concurrent agents, run them in waves until every track is covered.
2. Start with read-only audit agents. Have them inspect distinct workstreams and return findings before implementation begins.
3. During implementation, assign agents disjoint files, directories, or isolated worktrees. Do not allow concurrent edits to the same path. One integration lead owns shared contracts, conflict resolution, full-matrix reruns, and the final report.
4. Prefer working software and executable tests over prose. Every fixed defect needs regression coverage when practical.
5. Never expose credentials, private configuration, test-user passwords, authentication tokens, or user recordings. Never commit generated secrets.
6. Distinguish these evidence levels in every report: static inspection, unit test, mocked integration, local browser automation, hosted-service integration, iOS Simulator, signed archive, and physical-device test.
7. Do not convert a failed real path into a mock and then report the real path as passing.
8. Do not push directly to `main`, force-push shared history, merge the pull request, or create a release tag. Leave those steps for review after all gates pass.
9. Use current official primary documentation when a platform requirement or dependency may have changed.
10. Do not ask broad planning questions. Make safe, documented decisions from the repository. Put missing owner information, credentials, contracts, legal decisions, or physical-device checks in `docs/release-readiness/HUMAN_ACTIONS.md` as explicit blockers.

## Current repository facts to verify before acting

At orchestration setup:

- `main` is the deployed web branch.
- `swift-migration` is two commits behind `main`, has no unique commits, and contains only migration scaffolding already represented in the repository. Recheck this. Synchronize it safely with current `main` before relying on it. Do not overwrite new work if the branch changed after this prompt was authored.
- The native work currently consists of `swift/BrassTuneCore`; an actual SwiftUI application and Xcode UI-test target have not been built.
- The committed Playwright device simulation visits the auth screen with Supabase disabled. It does not prove sign-up, sign-in, password reset, session restoration, Apple sign-in, or account deletion.
- The current password-reset screen is informational rather than a completed reset flow.
- The current app has email/password auth but no Sign in with Apple implementation and no in-app account deletion.
- The ensemble page has director/admin controls, but full director/student production journeys and negative authorization cases have not been demonstrated.

Treat each item as a hypothesis to confirm against current code, then fix or supersede it.

## Parallel role tracks

Launch read-only audits for at least these tracks, then implementation agents for each applicable track:

1. Release integration and dependency map.
2. React product UX and accessibility.
3. Browser end-to-end automation across Chromium, WebKit, and Firefox.
4. Supabase authentication and account lifecycle.
5. Teacher/director and student ensemble product flows.
6. FastAPI authorization, validation, and data isolation.
7. Database migrations, Supabase policies, storage, retention, export, and deletion.
8. Pitch-domain parity, fixtures, and analytics correctness.
9. Web microphone, WebSocket, recording, playback, and media-import behavior.
10. Swift package parity and XCTest fixtures.
11. Native SwiftUI architecture and feature implementation.
12. Native audio capture, deterministic pitch testing, recording, and playback.
13. Native authentication, Sign in with Apple, Keychain, API client, and account deletion.
14. Xcode build, unit, integration, UI, accessibility, and simulator testing.
15. Apple release requirements, privacy, legal surfaces, metadata, signing, and submission checklist.
16. Vercel, Render, Supabase, CI, hosted smoke tests, monitoring, and rollback.

The audit wave must produce a prioritized finding table with severity, affected user, reproduction, owning track, and test to add. The lead must then create a dependency-aware implementation sequence and begin work immediately.

## Phase 1 — Establish a clean baseline

- Record branch heads, merge bases, uncommitted state, toolchain versions, configured services, and available simulator runtimes without printing secret values.
- Reconcile `swift-migration` with current `main` safely. Native implementation may live in this pull-request branch, but document the exact update/cherry-pick plan for the long-lived Swift branch.
- Install dependencies using lockfiles. Do not silently regenerate lockfiles unless required and explained.
- Run all existing backend, frontend, security, device-simulation, and Swift package checks before changing behavior.
- Build the frontend and start the API from a clean database.
- Verify current production health non-destructively: Vercel app load and deep links, Render health/API, HTTPS, CORS, and WebSocket handshake where available.
- Capture baseline failures in `docs/release-readiness/BASELINE.md` with exact commands and concise output excerpts.

## Phase 2 — Complete web authentication and account lifecycle

Implement and verify a coherent account system on the web and API:

- Email/password sign-up with field validation, duplicate and weak-password handling, confirmation-required and confirmation-disabled behavior, resend confirmation, and clear next steps.
- Email/password sign-in, invalid credentials, disabled/unconfirmed user behavior, loading state, rate-limit-friendly errors, sign-out, session restoration after refresh, token refresh, and expired-session recovery.
- Real password-reset request and completion flow, including safe redirects, invalid/expired recovery links, password confirmation, success state, and post-reset sign-in.
- Sign in with Apple through Supabase for the web. Use a safe redirect/callback flow, preserve intended navigation, handle cancellation and provider errors, and document the required Apple/Supabase configuration without inventing identifiers.
- A complete in-app account-deletion flow. Require recent confirmation, make consequences clear, allow data export first, call an authenticated backend deletion endpoint, remove application records and owned audio/storage objects, handle ensemble memberships and director-owned groups deterministically, revoke/delete the Supabase identity using a server-authorized path, sign out locally, and make the operation retry-safe.
- Public, stable Privacy Policy and Terms of Service routes linked from sign-up, sign-in, settings, footer/navigation where appropriate, and account deletion confirmation.
- Do not require an account for tuner/demo functionality that does not need account-specific storage. Clearly gate account-only features.
- Do not allow users to grant themselves director/admin privileges. Define and test a secure provisioning or invitation mechanism appropriate to the existing architecture.

Add deterministic local integration tests plus environment-gated live Supabase tests. Live tests must use dedicated disposable accounts, unique data, cleanup, and protected configuration. If live credentials are unavailable, the deterministic suite must still run and the missing live evidence must be reported as a blocker rather than marked passing.

## Phase 3 — Finish the teacher/director and student ensemble experience

Treat “teacher dashboard” and the existing “director” role as the same product area unless the codebase establishes a different model. Make terminology consistent and preserve a stable server-side role identifier.

Cover the complete lifecycle:

- Secure teacher/director provisioning.
- Teacher first-run empty state and guided group creation.
- Create, rename, archive/delete, and select ensembles.
- Invite or add students with a privacy-conscious mechanism; support pending, active, removed, expired, and reactivated membership states as appropriate.
- Roster search, instrument assignment, role-in-group changes, removal, useful validation, and duplicate handling.
- Student acceptance/join flow, student group view, leave/request-removal flow where product policy allows, and clear access loss after removal.
- Teacher aggregate analytics scoped only to active members of the selected ensemble and date range.
- Student privacy: a student must not see other students’ private sessions or analytics unless an explicit, documented product rule permits it.
- Teacher drill-down must be limited to authorized group data and show honest empty/insufficient-data states.
- Rehearsal recommendations, report export/printing, loading, retry, offline, and stale-data behavior.
- Responsive and accessible behavior on phone, tablet, and desktop.

Add API and browser tests for at least two teachers, multiple students, a non-member, a removed member, and an admin. Test cross-user session access, cross-group reads and writes, role escalation, guessed identifiers, inactive membership, and teacher access after ownership/membership changes. Every forbidden path must fail server-side, not only disappear from the UI.

## Phase 4 — Harden the API, database, storage, and privacy lifecycle

- Audit authentication-context mapping, JWT validation, user provisioning races, username uniqueness, role handling, and production guest-mode behavior.
- Validate all external payloads and remove unsafe `any` use at important frontend/API boundaries.
- Enforce ownership and group scope for sessions, samples, analytics, exports, audio, recommendations, and ensemble reports.
- Add request limits and safe validation for audio uploads and other large payloads.
- Make database migrations work from an empty database and from the current production schema. Add downgrade/rollback notes when destructive rollback is unsafe.
- Review Supabase database and storage policies. Private recordings must not be publicly enumerable; signed URLs must be appropriately short-lived.
- Implement a documented data map: data category, purpose, storage location, sharing, retention, export path, and deletion path.
- Make account deletion cover dependent rows, object storage, refresh sessions/identity, memberships, invitations, and teacher-owned data according to a documented policy.
- Add non-PII structured logs and actionable health diagnostics. Never log passwords, bearer tokens, full email addresses, or raw recordings.
- Run dependency, static-security, and secret scans. Fix actionable findings or document justified exceptions.
- Review whether the product may be used by children or schools. Do not make child-directed claims or select a Kids Category without an owner/legal decision. Record required decisions around minimum age, parental/educational consent, and school data obligations in `HUMAN_ACTIONS.md`.

## Phase 5 — Expand shared domain parity

Finish `swift/BrassTuneCore` so portable behavior matches the backend and web domain logic:

- Instrument profiles and transposition.
- Pitch and tuning models.
- Note segmentation.
- Duration-weighted analytics.
- Heat-map inputs and progress metrics where portable.
- Recommendation and practice-plan rules.
- Session/audio metadata models.
- Codable API models with explicit date and error handling.

Make every JSON fixture in `fixtures/` run in pytest, frontend tests where relevant, and XCTest. Add edge cases for invalid frequencies, reference pitch, transposing instruments, silence/no-lock, unstable pitch, note boundaries, short events, sparse data, and floating-point tolerances. Produce a parity report that compares outputs rather than merely counting passing tests.

## Phase 6 — Build the real native SwiftUI app

Create a real native application under `swift/BrassTuneApp` with a checked-in Xcode project or workspace, an application target, unit-test target, integration-test target where useful, and UI-test target. It must consume `BrassTuneCore` and communicate with the existing FastAPI/Supabase architecture. Do not submit a thin web wrapper.

Implement a coherent native experience for:

- Launch, onboarding, instrument/reference-pitch setup, and guest/demo entry.
- Home/dashboard.
- Practice tuner with explicit no-lock, unstable, in-tune, sharp, and flat states.
- Recording lifecycle and visible recording indication.
- Saved sessions, session detail/review, relisten playback, deletion, and export/share.
- Analytics, heat map, progress, recommendations, and practice plan.
- Teacher/director ensemble dashboard and student ensemble view.
- Sign-up, sign-in, email confirmation state, password reset, Sign in with Apple, sign-out, session restoration, and account deletion.
- Settings, data export, Privacy Policy, Terms of Service, support/contact surface, and app version.
- Loading, empty, error, offline, permission-denied, interrupted, and retry states throughout.

Architecture requirements:

- Use SwiftUI with clear feature, domain, service, and persistence boundaries.
- Use structured concurrency and cancellation safely; UI mutations must occur on the correct actor.
- Use the official current Supabase Swift client or a documented, tested alternative. Pin dependency versions.
- Store authentication material in Keychain or an equivalent platform-secure facility, not `UserDefaults`.
- Implement Sign in with Apple using `AuthenticationServices`, a cryptographically appropriate nonce flow where required by Supabase, cancellation/error handling, and account-linking considerations. Never commit Apple identifiers or keys.
- Use an explicit environment/configuration layer for local, preview/staging, and production API/auth endpoints. Do not hard-code private values.
- Make network models typed, validate responses, provide retry/timeout behavior, and avoid leaking sensitive details in user-visible errors.
- Support iPhone and iPad layouts, portrait and landscape where the UI supports them, light/dark appearance, Dynamic Type, reduced motion, VoiceOver labels/hints, logical focus order, and minimum target sizes.

## Phase 7 — Native audio and pitch behavior

- Use `AVAudioSession` and `AVAudioEngine` for microphone capture with interruption, route-change, background/foreground, denied/restricted permission, and unavailable-input handling.
- Provide a clear visual recording indicator and explicit consent before recording or retaining audio.
- Use Accelerate and/or a well-tested YIN-style implementation for native pitch detection. Match the shared `PitchFrame` semantics and confidence/save thresholds.
- Use deterministic generated audio fixtures and offline buffers for automated accuracy, range, silence, noise, stability, and transposition tests.
- Save relisten recordings with an appropriate Apple-supported format, upload them through the protected API/storage path, play them back, delete them, and clean temporary files.
- Keep automated claims scoped to synthetic/offline evidence. A simulator cannot validate physical microphone quality. Create a concise physical-device protocol for at least one recent iPhone and one supported iPad, wired/Bluetooth route changes if supported, quiet/noisy rooms, and representative high/low brass tones.

## Phase 8 — Simulate the entire app in Xcode

Discover installed runtimes and devices dynamically with `xcrun simctl`; do not hard-code a simulator that may not exist. Use the current App Store submission toolchain. As of this mission, submissions require Xcode 26 or later with the iOS/iPadOS 26 SDK; verify that requirement against current official Apple documentation before the final report.

Run and record:

- `xcodebuild -list` and clean builds for Debug and Release configurations.
- Swift package tests.
- App unit and integration tests.
- XCUITest journeys for guest/demo, student, and teacher/director personas.
- iPhone and iPad simulator destinations available on the machine.
- Portrait and landscape checks where supported.
- Light and dark appearance.
- At least default, large, and accessibility Dynamic Type sizes.
- Launch, onboarding, sign-up/sign-in surfaces, session restoration fixture, password-reset fixture, Apple-sign-in cancellation/error fixture, account-deletion fixture, tuner fixture, recording fixture, session review, analytics, teacher group/roster/report, student group view, settings, privacy, and terms.
- Offline launch, API timeout, expired auth, denied microphone permission, interruption, empty data, malformed response, and retry behavior.
- Accessibility identifiers and assertions for critical controls and states.
- Screenshot artifacts for representative iPhone and iPad release journeys, without real personal data.

Use deterministic launch arguments, URL-protocol/network doubles, and seeded personas for repeatable UI tests. Keep a separate environment-gated live integration scheme for Supabase/API behavior. Report exactly which journeys ran against doubles and which ran against live services.

When a macOS/Xcode environment is unavailable to the current agent, still implement the project and CI, perform all platform-independent checks, and mark the Xcode execution gate blocked. Do not describe unexecuted simulator tests as passed.

## Phase 9 — Upgrade web end-to-end simulation

Replace route-visiting-only confidence with full user journeys:

- Run Playwright on Chromium, WebKit, and Firefox where supported.
- Guest onboarding, tuner demo, record/stop, saved session, playback, analytics, progress, coach, export, and deletion.
- Real or dedicated-test-tenant sign-up, confirmation behavior, sign-in, refresh restoration, reset-password completion, sign-out, and account deletion.
- Apple OAuth button/callback state with deterministic provider doubles plus an environment-gated live provider check when credentials permit.
- Teacher create-group, invite/add student, roster changes, aggregate report/export, remove student, and authorization failures.
- Student join/view/record/session/group experience and access loss after removal.
- Responsive viewports, keyboard-only navigation, focus visibility, semantic names, and automated accessibility scanning.
- Production/preview deep-link refresh, API and WebSocket connectivity, CORS, content-security headers, and no mixed content.

Do not mutate ordinary production users. Use isolated test data and cleanup. Save sanitized traces/screenshots only for failed journeys and selected release evidence.

## Phase 10 — Apple release readiness

Use current official Apple documentation and create `docs/release-readiness/APP_STORE_CHECKLIST.md`. Implement all technical items that can be completed in code, including as applicable:

- Xcode 26+ / iOS 26 SDK build compatibility.
- Unique bundle identifier configuration, semantic marketing version, build number strategy, display name, supported orientations/devices, app icon, launch experience, and release configuration.
- `NSMicrophoneUsageDescription` and every other purpose string actually required by used APIs. Do not request permissions the app does not need.
- Sign in with Apple capability/entitlement and documented Apple Developer/Supabase configuration steps.
- `PrivacyInfo.xcprivacy`, third-party SDK privacy manifests/signatures, and approved reasons for any required-reason API use.
- App Transport Security review and secure endpoint configuration.
- Account deletion in the app.
- Privacy Policy and Terms links in app and App Store metadata plan.
- App Privacy questionnaire draft grounded in the actual data map, including account identifiers, diagnostics, recordings, analytics, and third parties.
- Data retention/deletion description.
- Encryption/export-compliance questionnaire draft, clearly marked for owner confirmation.
- Age-rating questionnaire draft and explicit decision on children/school use.
- App Review notes, backend availability notes, microphone explanation, demo instructions, and a template for a review account when account-only features need one.
- Support URL, marketing URL if used, copyright/rights confirmation, category/keywords/subtitle/description drafts, and localized screenshot plan.
- Archive validation and export when signing credentials and profiles are available. Never fabricate a successful signed archive.

Apple requires a privacy-policy link in metadata and within the app, and apps that create accounts must allow users to initiate account deletion inside the app. Ensure both are demonstrably satisfied. Privacy and Terms documents may be well-structured product drafts, but do not claim legal certification. Never invent the owner’s legal name, postal address, governing law, support email, data-controller identity, Apple Team ID, Services ID, bundle ID, or App Store Connect status. Missing final values remain release blockers.

## Phase 11 — CI, deployment, and operations

- Preserve the known-good Vercel frontend and Render backend wiring.
- Ensure pull requests run backend tests, frontend tests/build, browser journeys appropriate for CI, Swift package tests, security scans, and a macOS Xcode build/test job using an available Xcode 26 image or runner.
- Keep live-provider and hosted destructive tests manually gated and protected by dedicated test configuration.
- Add non-destructive hosted smoke checks for frontend deep links, backend health, representative authenticated API behavior where safe, and WebSocket connectivity.
- Add or document uptime/error monitoring, alert ownership, log access, data-safe diagnostics, backup/restore expectations, database migration procedure, rollback procedure, and incident checklist.
- Verify Vercel preview and production environment variable names, Render environment, Supabase redirect allowlists, Apple callback configuration plan, CORS origins, and secure WebSocket URL. Do not print values.
- Run dependency audits and verify production builds from clean checkouts.

## Required artifacts

Create or update these files with concise evidence rather than aspirational prose:

- `docs/release-readiness/BASELINE.md`
- `docs/release-readiness/FINDINGS.md`
- `docs/release-readiness/TEST_MATRIX.md`
- `docs/release-readiness/WEB_E2E_REPORT.md`
- `docs/release-readiness/IOS_SIMULATOR_REPORT.md`
- `docs/release-readiness/DOMAIN_PARITY.md`
- `docs/release-readiness/SECURITY_PRIVACY.md`
- `docs/release-readiness/APP_STORE_CHECKLIST.md`
- `docs/release-readiness/DEPLOYMENT_ROLLBACK.md`
- `docs/release-readiness/HUMAN_ACTIONS.md`
- `docs/release-readiness/FINAL_REPORT.md`

`TEST_MATRIX.md` must list every critical journey for web and iOS, persona, environment, automation level, command, result, and evidence location. `HUMAN_ACTIONS.md` must include only actions that genuinely require the owner, legal counsel, Apple/Supabase/Vercel/Render account access, signing credentials, App Store Connect, or physical hardware.

## Release gates

The pull request is not a release candidate until all available gates below pass:

1. Clean backend test suite and clean-database migration test.
2. Clean frontend typecheck/build/unit suite and supported dependency/security checks.
3. Full browser journeys, including actual auth logic and teacher/student ensemble behavior, not route visits.
4. Server-side authorization and data-deletion regression suite.
5. All shared Swift/domain parity fixtures.
6. Native app Debug and Release builds.
7. Native unit, integration, and XCUITest suites on representative available iPhone and iPad simulators.
8. Accessibility checks for critical web and native journeys.
9. Non-destructive hosted smoke checks.
10. Privacy/legal surfaces and App Store technical artifacts present with no shipping placeholder text.
11. No unresolved critical/high security defects or known data-loss defects.
12. Final report accurately separates passed, failed, blocked, and human-required gates.

A code-complete result with missing Apple credentials, final legal identity, a signed archive, App Store Connect entries, or physical-device microphone evidence may be labeled `engineering complete, externally blocked`; it must not be labeled `release ready`.

## Final integration and handoff

After every implementation wave:

- Review agent diffs and evidence.
- Resolve shared-contract changes in dependency order.
- Rebase or merge current `main` safely if it advanced.
- Run the complete matrix from a clean checkout/state.
- Verify the worktree is clean except intentional artifacts.
- Create cohesive commits with useful messages.
- Update the pull-request summary with fixed defects, architecture changes, exact commands/results, deployment impact, migration steps, risk, rollback, and human actions.
- Request an independent Codex review after implementation.

Continue fixing failures until they pass or are proven to require an unavailable external system. Do not end with “recommended next steps” for work that can be performed in the current environment; perform it. End only with the factual `FINAL_REPORT.md` and a concise pull-request handoff.