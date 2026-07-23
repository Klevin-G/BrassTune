# Predeployment Test Matrix

Updated: 2026-07-23

This matrix applies to implementation tree `3ec585ec8b604b9a04cb7708872c66bef963fe3f`. Historical counts elsewhere do not validate this candidate. Device-evidence commit `9003cf4282f8aef5d1e4d5900454d57862e1519e` records the clean responsive simulation; the containing documentation commit changes reports only.

| Gate | Current evidence | Status | Release boundary |
|---|---|---|---|
| Backend suite | Local `pytest`: `223 passed`, `4` PostgreSQL-only skips. | Passed locally | The isolated PostgreSQL expand/legacy-writer harness remains for CI because Docker/PostgreSQL was unavailable locally. |
| Backend SAST and dependencies | Production-code Bandit passed; current-environment `pip-audit --local` found no known vulnerabilities. | Passed locally | The direct requirements-file resolver still hits the documented local `ensurepip` crash; exact lockfile auditing remains a remote security-workflow gate. |
| Frontend units | `npm test`: `35` test files / `188` unit tests passed. | Passed locally | Local unit evidence only. |
| Frontend build, typecheck, PWA, and locale chunks | Production build/typecheck and PWA checks passed; lazy-load assertion found `11` locale chunks. | Passed locally | Does not validate a Vercel deployment or translation quality. |
| Frontend production dependency audit | `npm audit --omit=dev`: `0` vulnerabilities. | Passed locally | Re-run if production dependency inputs change. |
| Full browser matrix | `365` total: `358 passed`, `7` intentional PDF-engine skips; no React cross-render warning emitted. | Passed locally | Local Playwright evidence across configured projects; absence of the warning is local-run evidence only. |
| Offline production smoke | `2/2` passed. | Passed locally | Local offline production-mode evidence only. |
| Device simulation | `12/12` viewport profiles reported Pass with Issues=None from clean SHA `3ec585e`. | Passed locally | Chromium viewport automation is synthetic and does not validate physical Safari/iPad behavior. |
| Swift package | Fresh BrassTuneCore package run: `3/3` passed. | Passed locally | Shared-package evidence only. |
| Native app units and simulator builds | Prior exact evidence: `104/104` app units and Release iPhone/iPad simulator builds passed; the native app tree is unchanged for this candidate. | Previously passed locally | Unsigned simulator evidence; not archive, signing, TestFlight, or physical-device evidence. |
| Supabase migrations | Linked dry-run lists only `20260716201825` and expand-only `20260723021828`; linked lint reports no schema errors. | Pending authorized PR1 apply | Contract migration is deliberately absent until the privacy-aware PR1 backend is deployed and retained. |
| Hosted Vercel/Render smoke | Exact candidate revision plus hosted endpoints/browser smoke. | Pending | No deployment identity or hosted pass is claimed. |
| Physical-device validation | Microphone/brass, audio routes, interruptions, Files/Photos, accessibility, localization. | Unverified | Simulator and fixtures are not physical-device evidence. |
| Apple distribution | Signed archive, TestFlight, App Store Connect, review. | Unverified | Excluded from this candidate decision. |
| Independent review | Exact evidence revision plus completed diff/security/audio/localization/deployment/artifact review. | Pending | Required before push/merge/deploy. |

## Reproduction Commands

- `cd backend && .venv/bin/python -m pytest`
- `cd frontend && npm test`
- `cd frontend && npm run build`
- `cd frontend && npm audit --omit=dev`
- `cd frontend && CI=true npm run e2e:local`
- `cd swift/BrassTuneCore && swift test`
- Discover a simulator with `xcrun simctl list devices available` before the native `xcodebuild` commands in `AGENTS.md`.

## Recording Rule

Do not combine counts from separate reruns, branches, simulators, or historical reports. A release decision requires the exact revision, command, environment, result, and applicable provider/device boundary.
