# Release Test Matrix

Updated: 2026-07-08

Current native release boundary: Swift package, design-token verification, app unit tests, and unsigned simulator builds pass, and PR #8 now contains a local AVAudioEngine live microphone capture path with on-device pitch detection. The native app is still not release-complete because current UI smoke execution is blocked before the test body by CoreSimulator runner preflight failures, no physical iPhone/iPad was available for microphone/brass validation, and Apple signing/archive/TestFlight/App Store gates remain unavailable.

## Native Swift Local Gates

| Gate | Command | Result | Notes |
|---|---|---|---|
| BrassTuneCore Swift package | `cd swift/BrassTuneCore && swift test` | Passed: `3` Swift Testing tests | Pitch math, transposition, and confidence semantics. |
| Native design tokens | `python3 swift/BrassTuneApp/scripts/verify_design_tokens.py` | Passed | Verified `15` Swift theme colors against `design/brasstune-tokens.json`. |
| Native app unit tests | `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination 'platform=iOS Simulator,id=F05D449A-5102-489A-913A-8CD9BB37EF5E' -only-testing:BrassTuneAppTests CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO` | Passed: `18` tests | Covers local persistence, score cleanup, metronome state, session export, analytics, transposition fixtures, live/sample source separation, and native pitch detector sine/silence/no-lock cases. |
| Native UI smoke execution | `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination 'platform=iOS Simulator,id=F05D449A-5102-489A-913A-8CD9BB37EF5E' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests/BrassTuneAppUITests/testLaunchPracticeAndSettingsSurfaces` | Blocked | The test body was patched for the current live/sample labels, but the runner still blocked before launch with the CoreSimulator `SBMainWorkspace` preflight `Busy` failure. |
| iPhone Debug simulator build | `xcodebuild build -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination 'platform=iOS Simulator,id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO` | Passed | Simulator build only, unsigned. |
| iPhone Release simulator build | `xcodebuild build -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination 'platform=iOS Simulator,id=4B4489C4-295C-4565-9544-30812B4EA0EB' CODE_SIGNING_ALLOWED=NO` | Passed | Simulator build only, unsigned. |
| iPad Debug simulator build | `xcodebuild build -quiet -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination 'platform=iOS Simulator,id=CEC7E3E1-8B2E-4C6B-8E8E-486657046FCE' CODE_SIGNING_ALLOWED=NO` | Passed | iPad (A16) simulator discovered dynamically. |
| Live acoustic microphone capture | Static source audit and simulator build | Implemented locally; physical validation blocked | `NativeAudioEngine` now has a live AVAudioEngine input tap, microphone permission handling, PCM buffer capture, RMS/frequency/confidence detection, no-lock/unstable statuses, transposition/reference-pitch handling, and route/interruption notices. Simulator-safe sample mode remains available and clearly labeled. |
| Physical iPhone/iPad validation | `xcrun devicectl list devices` / `xcrun xctrace list devices` | Blocked | No physical iPhone/iPad was connected; microphone, brass-room acoustics, route changes, haptics, Photos/Files, heat, and click bleed remain untested. |
| Apple signing/archive/TestFlight | Xcode project/signing audit | Blocked | Bundle ID is still development-scoped, `DEVELOPMENT_TEAM` is empty, signing was disabled for simulator builds, and no App Store Connect/TestFlight authorization was available. |
| Native launch screenshot | `xcrun simctl io D0C0647A-4B09-41B2-A434-ABB37D8095A5 screenshot /tmp/brasstune-native-launch.png` | Captured | Simulator launch evidence only. |
| Diff hygiene | `git diff --check` | Passed | No whitespace errors. |
| Dirty-diff artifact scan | Dirty-file size and high-confidence secret-pattern scan | Passed | No dirty files over 1MiB and no high-confidence secrets observed in the dirty diff. |

## Web Production Gates

Web production work is paused by owner direction as of 2026-07-04. The following rows are retained as historical web evidence only and were not rerun during the native-only pass.

| Gate | Command | Result | Notes |
|---|---|---|---|
| Backend full suite | `cd backend && .venv/bin/python -m pytest` | Passed: `77 passed` | Warnings are existing datetime/TestClient deprecations. |
| Backend hardening | `cd backend && .venv/bin/python -m pytest app/tests/test_hardening.py` | Passed: `61 passed` | Covers WebSocket hardening, audio spoof rejection, JSON limits, headers, account/deletion, ensemble auth. |
| Backend Bandit | `cd backend && .venv/bin/python -m bandit -r app -x app/tests` | Passed | No issues identified. |
| Backend direct pip-audit | `cd backend && .venv/bin/python -m pip_audit -r requirements.txt -r requirements-dev.txt` | Blocked | Resolver venv `ensurepip` crashed before vulnerability analysis. |
| Backend uv pip-audit fallback | clean `uv` Python 3.12 venv, install `requirements-dev.txt`, run `pip_audit -r requirements.txt -r requirements-dev.txt` | Passed | No known vulnerabilities found. |
| Frontend unit tests | `cd frontend && npm test` | Passed: `9` files, `40` tests | Includes domain/API/theme-adjacent coverage. |
| Frontend build/typecheck | `cd frontend && npm run build` | Passed | Vite production build completed. |
| Frontend dependency audit | `cd frontend && npm audit --omit=dev` | Passed | `0 vulnerabilities`. |
| Local E2E/accessibility | `cd frontend && CI=true npm run e2e:local` | Passed: `80 passed` | Chromium, Firefox, WebKit, mobile Chromium, mobile WebKit. |
| Device simulation | `cd frontend && npm run simulate:devices` | Passed | Report: `docs/device-simulation-report.md`. |
| PR #3 CI | GitHub Actions and Vercel for `a642508ab638233e1fe297653147b8ccd3ceaf54` | Passed | Backend, Frontend, Security, and Vercel passed. |
| PR #4 CI | GitHub Actions and Vercel for `d0cce2614710e17b955ae8f81815141ea6281df5` | Passed | Frontend, Security, and Vercel passed. |
| Production smoke | `npm run smoke:hosted` | Passed: `7/7` | Root, health, CORS, WebSocket app response, query-token rejection, bad-Origin rejection. |
| Strict hosted Playwright | `E2E_STRICT_HOSTED_CONTENT=1 npm run e2e:hosted -- --project=chromium` | Passed: `7 passed` | Production browser smoke after final main deploy. |
| Vercel headers | `curl -I https://brass-tune.vercel.app` | Passed | CSP, HSTS, Permissions-Policy, Referrer-Policy, `X-Content-Type-Options`. |
| Render headers | `curl -D - -H 'Origin: https://brass-tune.vercel.app' https://brasstune.onrender.com/api/health` | Passed | API security headers observed. |
| Diff hygiene | `git diff --check` | Passed | No whitespace errors. |

## Remaining External Gates

| Gate | Status | Reason |
|---|---|---|
| Live Supabase account lifecycle | Owner-gated | Requires disposable provider credentials/users. |
| Google/Apple provider lifecycle | Owner-gated | Provider configuration and disposable users are external. |
| Native Swift physical-device validation | Blocked | Requires real iPhone/iPad for microphone, brass-room acoustics, Photos/Files import, haptics, speaker/headphone click-bleed, and route changes. Local AVAudioEngine implementation is not physical-device proof. |
| App Store/TestFlight | External | Requires Apple signing, App Store Connect, approved wording, and submission access. |
| Camera score capture | External/future native feature | Camera import is hidden and no camera permission string is declared until a real native flow is implemented and device-tested. |
