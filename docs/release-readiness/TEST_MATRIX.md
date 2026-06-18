# Release Test Matrix

| Journey/Gate | Persona | Environment | Automation | Command | Result | Evidence | Blocker |
|---|---|---|---|---|---|---|---|
| Backend regression suite | API users | Local venv | Pytest | `cd backend && .venv/bin/python -m pytest` | Passed: `48 passed` | Terminal output | None |
| Web unit tests | Web user | Local | Vitest | `cd frontend && npm test` | Passed: `16 tests` | Terminal output | None |
| Web build/typecheck | Web app | Local | npm/Vite | `cd frontend && npm run build` | Passed | Terminal output | Large chunk warning only |
| Frontend dependency audit | Web app | Local | npm audit | `cd frontend && npm audit --omit=dev` | Passed: `0 vulnerabilities` | Terminal output | None |
| Browser critical routes | Guest | Local Chromium/Firefox/WebKit/mobile | Playwright | `cd frontend && CI=true npm run e2e:local` | Passed: `35 passed`, `30 skipped` | `frontend/e2e/release-journeys.spec.ts`, `hosted-smoke.spec.ts` | Hosted-only API/WS checks skipped in local mode |
| Auth reset/Apple surfaces | Guest/auth user | Local mocked Supabase config | Playwright | `npm run e2e:local` | Passed for disabled/mocked surfaces | `WEB_E2E_REPORT.md` | Live Supabase/Apple provider not configured |
| Demo tuner recording/session review | Guest | Local browser | Playwright | `npm run e2e:local` | Passed across desktop/mobile browser projects | `WEB_E2E_REPORT.md` | Real microphone quality not covered |
| Settings export before delete | Signed-in surface | Local browser | Playwright | `npm run e2e:local` | Passed | `WEB_E2E_REPORT.md` | Live deletion requires credentials |
| Server-side ensemble forbidden write | Student/director | Local backend | Playwright API request | `npm run e2e:local` | Passed: student 403, director 200 | `frontend/e2e/release-journeys.spec.ts` | Broader live personas unavailable |
| Web device simulation | Guest/demo | Local browser screenshots | Node/Playwright | `cd frontend && npm run simulate:devices` | Passed | `docs/device-simulation-report.md` | Generated screenshot diffs are artifacts |
| Swift package parity smoke | Domain logic | Local SwiftPM | XCTest | `cd swift/BrassTuneCore && swift test` | Passed: `3 tests` | Terminal output | Parity breadth still limited |
| Native Debug/unit/UI | Native app | Dynamically selected iPhone simulator | XCTest/XCUITest | `xcodebuild test ... -only-testing:BrassTuneAppTests -only-testing:BrassTuneAppUITests/...` | Passed: `3 unit`, `1 UI` | xcresult under Xcode DerivedData | Full suite breadth still early |
| Native Debug builds | iPhone/iPad | Dynamically selected iOS simulators | xcodebuild | `xcodebuild ... Debug ... CODE_SIGNING_ALLOWED=NO clean build` | Passed on iPhone 17 Pro and iPad Pro 13-inch simulators | `/tmp/brasstune-dd-debug-iphone-final`, `/tmp/brasstune-dd-debug-ipad-final` | No signing/archive |
| Native Release build | iPhone | Dynamically selected iOS simulator | xcodebuild | `xcodebuild ... Release ... CODE_SIGNING_ALLOWED=NO build` | Passed | Terminal output | No signing/archive |
| Vercel root/deep link | Public web | Hosted | curl | `curl -IL https://brass-tune.vercel.app[/settings]` | Passed: `HTTP/2 200` | Terminal output | None |
| Render health/CORS | Public API | Hosted | curl | `curl /api/health`, `OPTIONS /api/health` | Passed after cold start | Terminal output | Cold start latency |
| Hosted root/API/WS smoke | Public web/API | Hosted | Node script | `BRASSTUNE_WEB_BASE_URL=https://brass-tune.vercel.app BRASSTUNE_API_BASE_URL=https://brasstune.onrender.com BRASSTUNE_WS_BASE_URL=wss://brasstune.onrender.com npm run smoke:hosted` | Passed | Terminal output | Protected preview page automation separate |
| Hosted WebSocket handshake | Web/API | Hosted | Node WebSocket | `wss://brasstune.onrender.com/ws/pitch` | Passed: opens and returns auth-required app message | Terminal output | Live authenticated WS requires credentials |
| Protected Vercel preview routes | Guest | Hosted preview | Playwright | `E2E_BASE_URL=... E2E_VERCEL_SHARE_URL=... npm run e2e:hosted -- --project=chromium` | Partial: API/CORS/WS tests passed; page route tests received `401` | Terminal output | Requires Vercel automation bypass or unprotected preview |
| Supabase clean baseline | Backend data | Live Supabase project | Supabase migrations | `20260616_brasstune_baseline`, `20260617_brasstune_production_readiness` | Passed: nine public app tables, RLS enabled, zero rows | Supabase MCP output | None for baseline |
| Supabase RPC drift | Backend data | Live Supabase project | Supabase migration/query | `20260618_lock_down_rls_auto_enable` | Passed: `anon_execute=false`, `authenticated_execute=false` | Supabase MCP output | None for that finding |
| Local secret scan | Repo history | Local | Gitleaks | `gitleaks detect --redact --verbose` | Not run locally: tool unavailable | Terminal output | Rely on GitHub Security after final push |
| Backend security scans | Backend | Local | pip-audit/Bandit | `pip-audit ...`, `bandit -r app -x app/tests` | Not run locally: tools unavailable | Terminal output | Rely on GitHub Security after final push |
| Live Supabase auth lifecycle | User | Hosted/live Supabase | Environment-gated tests | Not run | Blocked | `HUMAN_ACTIONS.md` | Requires credentials and disposable project/users |
| App Store archive/signing | iOS app | Apple Developer/App Store Connect | xcodebuild/archive | Not run | Blocked | `APP_STORE_CHECKLIST.md` | Requires Apple credentials |
| Physical audio quality | Brass players | Physical devices | Manual protocol | Not run | Blocked | `PHYSICAL_DEVICE_PROTOCOL.md` | Requires hardware and players |
