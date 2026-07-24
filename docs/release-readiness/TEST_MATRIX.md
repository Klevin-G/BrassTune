# Predeployment Test Matrix

Updated: 2026-07-23. Candidate source revision: `7c12b15`.

| Gate | Latest evidence | Status | Release meaning |
|---|---|---|---|
| Backend | `246 passed, 4 skipped` after `428a123` | Passed locally | Duplicate-identity PII race fixed; exact-SHA self-hosted CI still required. |
| Frontend units | `251/251` | Passed locally | Needs exact-SHA CI. |
| Frontend build | `npm run build` passed; 11 lazy non-English locale chunks | Passed locally | Needs deployed-bundle verification. |
| Frontend dependency audit | `npm audit --omit=dev`: 0 findings | Passed locally | Point-in-time dependency result. |
| Local browser journeys | `443 passed, 7 skipped, 0 failed` | Passed locally | Does not prove hosted services. |
| Swift Core | `3/3` | Passed locally | Shared-domain check only. |
| Native units/UI | `139/139`; `15/15`; affected welcome/auth checks `4/4` after `7c12b15` | Passed in simulator | Unsigned simulator only. |
| Native builds | Debug iPhone/iPad; Release iPhone, zero warnings | Passed locally | `7c12b15` follow-up build also reports zero warnings; not an archive or device test. |
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
