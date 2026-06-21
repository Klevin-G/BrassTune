# Release Test Matrix

Updated: 2026-06-21T05:24:54Z
Branch: `arya/final-web-completion`
Base SHA: `a8ce933a8ccfdac75b4244fe1c1bb2630655d14b`

## Current Branch Gates

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
| Diff hygiene | `git diff --check` | Passed | No whitespace errors. |
| Read-only hosted smoke of current production | explicit production `BRASSTUNE_* npm run smoke:hosted` | Passed: `7/7` | Applies to currently deployed `main`, not this unmerged branch. |

## Pending Release Gates

| Gate | Status | Reason |
|---|---|---|
| PR CI | Pending | Branch has not been pushed/opened as PR. |
| Vercel exact-SHA preview | Pending | Requires push/preview deploy. |
| Render matching backend deploy | Pending | Requires merge/deploy or authorized branch deployment path. |
| Production exact-SHA smoke | Pending | Must run after Vercel and Render serve the merge SHA. |
| Beta tag and GitHub prerelease | Pending | Must happen after production smoke passes. |
| Live Supabase account lifecycle | Owner-gated | Requires disposable provider credentials/users. |
| Swift/native phase | Blocked | Requires `WEB PRODUCTION COMPLETION GATE: PASSED`. |
