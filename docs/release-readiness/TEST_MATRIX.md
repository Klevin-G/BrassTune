# Predeployment Test Matrix

Updated: 2026-07-23. Candidate source revision: `428a123`.

| Gate | Latest evidence | Status | Release meaning |
|---|---|---|---|
| Backend | `244 passed, 4 skipped` | Re-run pending | A duplicate-identity PII race correction is in progress; final exact result is required. |
| Frontend units | `251/251` | Passed locally | Needs exact-SHA CI. |
| Frontend build | `npm run build` passed; 11 lazy non-English locale chunks | Passed locally | Needs deployed-bundle verification. |
| Frontend dependency audit | `npm audit --omit=dev`: 0 findings | Passed locally | Point-in-time dependency result. |
| Local browser journeys | `443 passed, 7 skipped, 0 failed` | Passed locally | Does not prove hosted services. |
| Swift Core | `3/3` | Passed locally | Shared-domain check only. |
| Native units/UI | `139/139`; `15/15` | Passed in simulator | Unsigned simulator only. |
| Native builds | Debug iPhone/iPad; Release iPhone, zero warnings | Passed locally | Not an archive or device test. |
| Self-hosted CI | Linux and macOS runner variables/labels are configured | Pending exact SHA | Required checks must run and pass. |
| Supabase | Three expand migrations pending | Pending | No provider mutation has been claimed here. |
| Hosted smoke | Render/Vercel same-SHA smoke | Pending | Must include REST, WS, auth, class, audio, and offline paths. |
| Physical iOS | Microphone, routes, accessibility, localization, signing | Pending | Required for native distribution claims. |

## Reproduction commands

```bash
cd backend && .venv/bin/python -m pytest
cd frontend && npm test
cd frontend && npm run build
cd frontend && npm audit --omit=dev
cd frontend && npm run e2e:local
cd swift/BrassTuneCore && swift test
```

Use dynamically discovered simulators for Xcode tests/builds. Re-run all relevant gates from the final commit before merge.
