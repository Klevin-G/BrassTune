# Predeployment Test Matrix

Updated: 2026-07-23

This matrix applies to the active predeployment candidate only. Historical counts elsewhere in the documentation do not validate this candidate. These results were recorded before the final commit; preserve them with the exact revision after commit and review.

| Gate | Current evidence | Status | Release boundary |
|---|---|---|---|
| Backend suite | Local `pytest`: `219 passed`, `2 skipped`. | Passed locally | Not hosted or provider evidence. |
| Backend SAST | Bandit reported clean. | Passed locally | Does not replace provider or runtime review. |
| Backend dependencies | `pip-audit` reported clean. | Passed locally | Must remain tied to the tested environment and final revision. |
| Frontend units | `npm test`: `156/156` passed. | Passed locally | Local unit evidence only. |
| Frontend build and locale chunks | Production build passed; lazy-load assertion found `11` locale chunks. | Passed locally | Does not validate a Vercel deployment or translation quality. |
| Frontend production dependency audit | `npm audit --omit=dev`: `0` vulnerabilities. | Passed locally | Re-run if production dependency inputs change. |
| Full browser matrix | `310` total: `303 passed`, `7` intentional synthetic-harness skips. | Passed locally | Local Playwright evidence; skips remain explicit and physical/browser-provider behavior remains separate. |
| Offline production smoke | `2/2` passed. | Passed locally | Local offline production-mode evidence only. |
| Targeted browser repeats | WebKit redirect repeat `20/20`; Chromium and WebKit journey repeat `30/30`. | Passed locally | Supporting reruns overlap the full matrix and are not additional release-test totals. |
| Device simulation | `12/12` viewport profiles reported Pass with Issues=None. | Passed locally | Chromium viewport automation is synthetic and does not validate physical Safari/iPad behavior. |
| Swift package | BrassTuneCore `3/3`. | Passed locally | Shared-package evidence only. |
| Native app units | `99/99`. | Passed locally | Simulator unit evidence; no physical audio or provider lifecycle claim. |
| Native UI smoke | `8/8`. | Passed locally | Fixture-backed simulator UI evidence. |
| Native simulator builds and launch frames | Debug and Release iPhone/iPad builds plus launch-frame checks passed. | Passed locally | Unsigned simulator evidence; not archive, signing, TestFlight, or physical-device evidence. |
| Native localization | `556` source keys, `562` catalog entries, `159` sentinels, `1,511` locale assertions; zero violations. | Passed locally | Static coverage evidence; human linguistic and RTL review remains required. |
| Supabase migrations | `20260716201825` and `20260723021828`. | Pending authorized apply | Repository files are unapplied; no provider mutation is recorded. |
| Hosted Vercel/Render smoke | Exact candidate revision plus hosted endpoints/browser smoke. | Pending | No deployment identity or hosted pass is claimed. |
| Physical-device validation | Microphone/brass, audio routes, interruptions, Files/Photos, accessibility, localization. | Unverified | Simulator and fixtures are not physical-device evidence. |
| Apple distribution | Signed archive, TestFlight, App Store Connect, review. | Unverified | Excluded from this candidate decision. |
| Final commit and independent review | Exact revision plus completed diff/security/release review. | Pending | Precommit results must be tied to the final revision before a release decision. |

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
