# Release Test Matrix

Updated: 2026-07-13

This matrix describes the required validation for the integrated class lifecycle, security hardening, Play-Along catalog, support-contact, web, backend, and native changes. Local results below were recorded against the resolved integration tree on 2026-07-13; external CI, macOS/Xcode, live-provider, deployment, and physical-device gates remain separate.

## Integration Gates

| Gate | Command or evidence | Current status | Acceptance criteria |
|---|---|---|---|
| Backend bytecode compilation | `cd backend && python -m compileall app` | Passed | No Python compilation errors. |
| Backend full suite | `cd backend && python -m pytest -q` using a fresh temporary SQLite database | Passed: `160/160` | Includes multi-class join, self-leave, owner protection, role-reset rejoin, authorization isolation, quotas, abuse limits, races, and readiness behavior. |
| PostgreSQL migration execution | PostgreSQL 17 container with representative `groups`, `group_members`, browser roles, and Storage bucket | Passed | Unique membership, unambiguous eight-character legacy-code rotation, private/size/MIME-bounded audio bucket, and browser-role revocation checks all returned true. This is not proof of live-project application. |
| Backend dependency audit | Fresh temporary environment; `pip-audit -r requirements.txt -r requirements-dev.txt` | Passed: no known vulnerabilities | Local reproduction of the Security workflow dependency gate. |
| Backend source security scan | `bandit -r app -x app/tests` | Passed: zero issues in `4,689` lines | Seven deliberate `#nosec` skips were reported; no low, medium, or high findings. |
| Frontend unit suite | `cd frontend && npm test` with Node `24.14.0` | Passed: `77/77` in `12` files | Includes class switching/leaving, the grouped Play-Along catalog, enharmonic grading, API behavior, and support compose URL coverage. |
| Frontend production build/typecheck | `cd frontend && npm run build` | Passed | TypeScript and Vite production build completed successfully. |
| Frontend production dependency audit | `cd frontend && npm audit --omit=dev` | Passed: `0` vulnerabilities | No known production dependency vulnerability. |
| Local browser journeys | `cd frontend && npm run e2e:local` | Passed: `135/135` | `27/27` each on Chromium, Firefox, WebKit, Mobile Chromium, and Mobile WebKit, including contrast, multi-class lifecycle, stale-response, duplicate-mutation, and grouped Play-Along coverage. |
| Device simulation | `cd frontend && npm run simulate:devices` | Not rerun | The command intentionally rewrites tracked screenshots/report artifacts. The non-artifact browser release matrix above passed all five configured browser/device projects; refresh screenshots only for an explicit visual-evidence update. |
| Swift package | `cd swift/BrassTuneCore && swift test` | Pending | Shared pitch, tuning, and transposition tests pass. |
| Native design verification | `python swift/BrassTuneApp/scripts/verify_design_tokens.py` | Passed | Verified `15` adaptive colors, `3` shared anchors, and the centralized glass fallback. |
| Native Debug build | Dynamic simulator discovery followed by `xcodebuild ... -configuration Debug ... build` | Pending macOS/Xcode | App builds with code signing disabled on an available simulator destination. |
| Native Release build | Dynamic simulator discovery followed by `xcodebuild ... -configuration Release ... build` | Pending macOS/Xcode | Release configuration builds with code signing disabled; this is not a signed archive. |
| Native app unit suite | `xcodebuild test ... -scheme BrassTuneApp ... -only-testing:BrassTuneAppTests` | Pending macOS/Xcode | All tests pass, including live-only defaults, the `12` major / `12` natural-minor / `3` other catalog with `27` unique IDs, enharmonic intervals, class capabilities, join/leave API contracts, and stale-load protection. |
| Native UI smoke | `xcodebuild test ... -scheme BrassTuneAppUISmoke ... -only-testing:BrassTuneAppUITests` | Pending macOS/Xcode | Onboarding, four-tab navigation, Play-Along, Tuner, Progress, Settings, class selection/leave, legal, metronome, and destructive-alert journeys pass. |
| Diff and artifact hygiene | `git diff --check`, tracked conflict-marker scan, high-confidence secret scan, changed-file size scan, and `git lfs status` | Passed locally | `65` final-tree files reviewed; zero markers, whitespace errors, untracked files, high-confidence secret files, changed files over `1 MiB`, or LFS objects to commit. |
| Exact-SHA CI | Backend, Frontend, Security, and Swift workflows on the final integration SHA | Pending external CI | All relevant jobs complete successfully. Do not treat a queued workflow or absent check as a pass. |
| Vercel preview | Preview deployment/status for the final integration SHA | Pending external service | Preview builds successfully or an external access/configuration blocker is documented. |

## Native Reproduction Commands

Discover simulator identifiers with `xcrun simctl list devices available`, then run the following against the same revision:

- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests`

## External Release Gates

| Gate | Status | Required evidence |
|---|---|---|
| Live Supabase migrations and account lifecycle | Owner-gated | Applied migration records plus disposable-user join, switch, leave, deletion, and provider lifecycle evidence. |
| Production environment and workflow protections | Owner-gated | Production secrets restricted to trusted `main` executions and reviewed environment/deployment branch policy. |
| Hosted production smoke | Not run for integration | Protocol and browser smoke against the deployed final SHA after an authorized deployment. |
| Physical iPhone/iPad validation | Blocked until hardware is available | Live brass/microphone quality, route changes, interruptions, haptics, timing, bleed, Files/Photos, performance, and accessibility evidence. |
| Signed archive, TestFlight, and App Store | External | Apple Team/signing assets, successful archive/export/upload, TestFlight validation, approved metadata, and App Review. |
| Camera score capture | Future feature | Implemented camera flow, permission declaration, and physical-device validation; no camera capability is currently claimed. |

## Evidence Recording Rules

- Record the exact revision, command, environment, and pass/fail result.
- Keep focused reruns distinct from full-suite totals and do not add them together.
- Historical branch or deployed-release evidence does not validate the resolved integration tree.
- Simulator evidence does not validate physical microphone quality, signing, TestFlight, or App Store readiness.
