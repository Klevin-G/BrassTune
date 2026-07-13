# Release Test Matrix

Updated: 2026-07-12

Current native boundary: the redesigned Swift source implements the four-tab Play-Along/Tuner/Progress/Settings app, live-microphone-only shipping behavior, UI-test-only fixtures, audible metronome defaults, adaptive light/dark surfaces, scoped iOS 26 Liquid Glass, a grouped 12-major/12-natural-minor Play-Along library, and authenticated multi-class join/switch/leave under Settings. `BrassTuneCore` executed successfully (`3/3`). The current app unit suite passed `40/40` and the full UI smoke passed `2/2` on dynamically discovered iOS 26.5 simulators. Physical-device and signed-release claims remain separate gates.

## Native Swift Local Gates

| Gate | Command or evidence | Result | Notes |
|---|---|---|---|
| BrassTuneCore Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3/3` Swift Testing tests | Pitch math, transposition, and confidence semantics executed locally. |
| Native design tokens and glass scope | `python3 swift/BrassTuneApp/scripts/verify_design_tokens.py` | Passed | Verified `15` adaptive Swift theme colors, `3` shared brand anchors, and the centralized glass fallback. |
| Four-tab information architecture | Passed native unit and UI suites | Passed in simulator | The `2/2` UI smoke executed the Play-Along, Tuner, Progress, and Settings tabs. Home, Practice, Analytics, Coach, and More are removed from the tab bar. |
| Native app unit tests | `xcodebuild test ... -scheme BrassTuneApp ... CODE_SIGNING_ALLOWED=NO` | Passed: `40/40` | Includes live-only shipping defaults, fixture guards, Play-Along grading/catalog, class API contracts and capabilities, stale-load cancellation, auth errors, persistence, score cleanup, analytics, transposition, and native pitch detector cases. |
| Native UI test suite | `xcodebuild test ... -scheme BrassTuneAppUISmoke ... CODE_SIGNING_ALLOWED=NO` | Passed: `2/2` | Covers onboarding plus the four-tab, Play-Along, Tuner, Progress, Settings, multi-class selection/leave accessibility, advanced A4, legal, metronome, fixture isolation, and destructive-alert journey. |
| Play-Along live grader | Passed native unit and UI suites | Passed with deterministic simulator input; physical microphone unverified | Uses `NativeAudioEngine` pitch frames, written-pitch-class matching, sustained holds, median cents, per-note ratings, percentage, and stars. Normal launches use the real microphone; deterministic frames require a UI-test launch flag. |
| Real-microphone shipping boundary | Source audit of `NativeTestFixtures`, `PracticeSessionSource.allCases`, `NativeAudioEngine`, and restore filtering | Implemented; physical validation blocked | Normal launches expose only `.live`; sample recording/score/ensemble fixtures require `UITEST_FIXTURES` or legacy `UITEST_DEMO`. Legacy sample persistence is filtered from normal restores. |
| Metronome defaults | Passed native unit and UI suites | Passed in simulator | Defaults are sound on, not visual-only, volume `0.6`; effective output is muted only during an active live recording. Physical speaker/headphone bleed remains unverified. |
| Adaptive design / Liquid Glass | Design verification script plus passed UI smoke | Passed in simulator; physical visual QA pending | System light/dark appearance is respected. Content uses solid adaptive surfaces. Custom glass is centralized and limited to floating transports, primary Start/Record actions, and the score viewer top controls, with iOS 17–25 fallbacks. |
| Simulator build/test execution | `xcodebuild test` on dynamically discovered iOS 26.5 simulators | Passed | Unit and UI schemes rebuilt the app and passed. A separate Release-configuration archive was not produced. |
| Physical iPhone/iPad validation | `xcrun devicectl list devices` / `xcrun xctrace list devices` | Blocked | No authorized physical-device run was available. Microphone, real brass input, route changes, interruptions, haptics, Files/Photos, thermals, timing, and speaker/headphone bleed remain unverified. |
| Apple signing/archive/TestFlight | Xcode project/signing audit | Blocked | The bundle ID remains development-scoped, `DEVELOPMENT_TEAM` is empty, project signing is disabled, and no App Store Connect/TestFlight authorization was available. |
| Diff hygiene | `git diff --check -- docs/release-readiness/NATIVE_PARITY_SURFACES.md docs/release-readiness/TEST_MATRIX.md docs/release-readiness/APP_STORE_CHECKLIST.md` | Passed | No whitespace errors in the native documentation update. |

## Reproduction Commands

Discover simulator identifiers with `xcrun simctl list devices available`, then run all of the following on the same working-tree revision:

- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests`

The unit and UI test commands executed successfully on this working-tree revision. Debug/Release build-only reruns remain useful before an Apple release.

## Current-Candidate Local Web and Backend Gates

The rows below were rerun on 2026-07-12 against the current uncommitted working-tree candidate. They are local evidence only: they are not exact-SHA CI results, hosted-production verification, or proof that the pending Supabase migrations have been applied live.

| Gate | Command or evidence | Current result | Notes |
|---|---|---|---|
| Backend full suite | Full pytest suite against a fresh SQLite database | Passed: `160/160` | Current local backend regression result. |
| Focused backend proxy/WebSocket/export/security selection | Focused pytest rerun covering proxy trust, WebSocket boundaries, export limits, and security behavior | Passed: `40/40` | Targeted current-candidate evidence; this is not an additional full-suite count. |
| Backend abuse-limit file | Final rerun of `backend/app/tests/test_abuse_limits.py` | Passed: `31/31` | Covers request, proxy, connection, frame, compute, pending-session, and quota abuse boundaries. |
| Backend bytecode compilation | Python `compileall` over the backend application | Passed | No Python compilation errors. |
| Backend source security scan | Bandit scan | Passed: no findings | Local static scan only. |
| Backend dependency audit | `pip-audit` | Passed: no known vulnerabilities | Result reflects the dependency set audited locally. |
| Frontend unit tests | `cd frontend && npm test` | Passed: `75/75` in `11` files | Current Vitest result. |
| Frontend production build/typecheck | `cd frontend && npm run build` | Passed: `2262` modules transformed | TypeScript and Vite production build completed. |
| Frontend production dependency audit | `cd frontend && npm audit --omit=dev` | Passed: `0` vulnerabilities | Local npm audit result. |
| Complete local browser/device E2E matrix | `cd frontend && npm run e2e:local` | Passed: `125/125` | `25/25` each on Chromium, Firefox, WebKit, Mobile Chromium, and Mobile WebKit. |
| Firefox synchronization regression target | Focused Firefox rerun of the synchronization-fix target | Passed: `5/5` | Focused diagnostic result; included within the final complete matrix rather than additive to it. |
| Firefox release journeys | Full Firefox `release-journeys` suite | Passed: `11/11` | Confirms the synchronization fix across the complete Firefox release journey set. |
| Targeted WebKit focus regression | Focused WebKit rerun before the final matrix | Passed: `2/2` | Focused diagnostic result; the later complete WebKit project passed `25/25`. |

## Historical Hosted Web Evidence

The prior hosted production smoke passed `7/7`. That result is retained only as historical evidence of the previously deployed web/backend release; hosted or production smoke was not rerun for this uncommitted candidate and the historical result does not validate it.

## Remaining External Gates

| Gate | Status | Reason |
|---|---|---|
| Native simulator execution on current redesign | Passed locally | `40/40` unit tests and `2/2` UI smoke tests passed on dynamically discovered iOS 26.5 simulators. |
| Native physical-device validation | Blocked | Requires a real iPhone/iPad and live brass input for microphone quality, acoustics, route/interruption behavior, haptics, timing, bleed, Files/Photos, performance, and accessibility checks. |
| Current-candidate hosted/production smoke | Not rerun | The candidate is still an uncommitted working tree. The historical hosted `7/7` result is not current-candidate evidence. |
| Exact-SHA CI | Not claimed | No CI result tied to a final candidate commit exists yet. |
| Live Supabase/account lifecycle | Owner-gated | Requires production native configuration and disposable provider users; pending Supabase migrations have not been applied live, and no provider behavior is inferred from local guest mode. |
| Google/Apple provider lifecycle | Owner-gated | Provider configuration, redirects, entitlements, and disposable users are external. |
| Signed archive/TestFlight/App Store | External | Requires Apple Team/signing assets, App Store Connect authorization, a successful archive/export/upload, TestFlight validation, approved metadata, and App Review. |
| Camera score capture | Future native feature | Camera import remains absent and no camera permission is declared until a real flow is implemented and device-tested. |
