# Release Test Matrix

Updated: 2026-06-21T05:51:09Z

## Web Production Gates

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
| Native Swift phase | Allowed to start | Web production gate passed; native completion is still separate. |
| App Store/TestFlight | External | Requires Apple signing, App Store Connect, approved wording, and submission access. |
| Physical-device microphone/brass validation | External | Simulator and browser checks do not prove physical brass input quality. |
