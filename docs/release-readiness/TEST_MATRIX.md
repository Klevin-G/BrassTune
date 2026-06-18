# Release Test Matrix

| Journey/Gate | Persona | Environment | Automation | Command | Result | Evidence | Blocker |
|---|---|---|---|---|---|---|---|
| Backend regression suite | API users | Local venv | Pytest | `cd backend && .venv/bin/python -m pytest` | Passed: `41 passed` | Terminal output | None |
| Web unit tests | Web user | Local | Vitest | `cd frontend && npm test` | Passed: `13 tests` | Terminal output | None |
| Web build/typecheck | Web app | Local | npm/Vite | `cd frontend && npm run build` | Passed | Terminal output | Large chunk warning only |
| Frontend dependency audit | Web app | Local | npm audit | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities` | Terminal output | None |
| Browser critical routes | Guest | Local Chromium/Firefox/WebKit/mobile | Playwright | `cd frontend && npm run e2e` | Passed in 24 tests | `frontend/e2e/release-journeys.spec.ts` | None |
| Auth reset/Apple surfaces | Guest/auth user | Local mocked Supabase config | Playwright | `npm run e2e` | Passed for disabled/mocked surfaces | `WEB_E2E_REPORT.md` | Live Supabase/Apple provider not configured |
| Demo tuner recording/session review | Guest | Local browser | Playwright | `npm run e2e` | Passed | `WEB_E2E_REPORT.md` | Real microphone quality not covered |
| Settings export before delete | Signed-in surface | Local browser | Playwright | `npm run e2e` | Passed | `WEB_E2E_REPORT.md` | Live deletion requires credentials |
| Server-side ensemble forbidden write | Student/director | Local backend | Playwright API request | `npm run e2e` | Passed: student 403, director 200 | `frontend/e2e/release-journeys.spec.ts` | Broader live personas unavailable |
| Web device simulation | Guest/demo | Local browser screenshots | Node/Playwright | `cd frontend && npm run simulate:devices` | Passed | `docs/device-simulation-report.md` | Generated screenshot diffs are artifacts |
| Swift package parity smoke | Domain logic | Local SwiftPM | XCTest | `cd swift/BrassTuneCore && swift test` | Passed: `3 tests` | Terminal output | Parity breadth still limited |
| Native Debug build | iPhone | iOS 26.2 simulator | xcodebuild | `xcodebuild ... Debug ... clean build` | Passed | `IOS_SIMULATOR_REPORT.md` | No signing/archive |
| Native Release build | iPhone | iOS 26.2 simulator | xcodebuild | `xcodebuild ... Release ... clean build` | Passed | `IOS_SIMULATOR_REPORT.md` | No signing/archive |
| Native iPad build | iPad | iOS 26.2 simulator | xcodebuild | `xcodebuild ... iPad Pro 11-inch (M5) ... build` | Passed | `IOS_SIMULATOR_REPORT.md` | No iPad physical-device proof |
| Native unit tests | Native app | iPhone 17 simulator | XCTest | `xcodebuild test ... -only-testing:BrassTuneAppTests` | Passed: `3 tests` | xcresult in `/tmp/brasstune-dd-unittest-final` | None |
| Native UI smoke | Native app | Temporary iPhone 17 simulator | XCUITest | `xcodebuild test ... -only-testing:BrassTuneAppUITests/...` | Passed: `1 test` | xcresult in `/tmp/brasstune-dd-uitest-final-fresh2` | Full suite breadth still early |
| Vercel root/deep link | Public web | Hosted | curl | `curl -IL https://brass-tune.vercel.app[/settings]` | Passed: `HTTP/2 200` | Terminal output | None |
| Render health/CORS | Public API | Hosted | curl | `curl /api/health`, `OPTIONS /api/health` | Passed after cold start | Terminal output | Cold start latency |
| Hosted WebSocket | Web/API | Hosted | Node/curl | `wss://brasstune.onrender.com/ws/pitch` | Failed: `404`/non-101 | Terminal output | Render deployment/routing mismatch |
| Live Supabase auth lifecycle | User | Hosted/live Supabase | Environment-gated tests | Not run | Blocked | `HUMAN_ACTIONS.md` | Requires credentials and disposable project/users |
| App Store archive/signing | iOS app | Apple Developer/App Store Connect | xcodebuild/archive | Not run | Blocked | `APP_STORE_CHECKLIST.md` | Requires Apple credentials |
| Physical audio quality | Brass players | Physical devices | Manual protocol | Not run | Blocked | `PHYSICAL_DEVICE_PROTOCOL.md` | Requires hardware and players |
