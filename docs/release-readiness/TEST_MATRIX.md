# Predeployment Test Matrix

Updated: 2026-07-23

This matrix applies to implementation tree `0273347b7ab32da3031a13abaa4b751730c46c1b`. Historical counts elsewhere do not validate this candidate. The containing evidence commit changes only documentation and generated screenshots.

| Gate | Current evidence | Status | Release boundary |
|---|---|---|---|
| Backend suite | Local `pytest`: `221 passed`, `4` PostgreSQL-only skips; account-deletion focus `23/23`. | Passed locally | The isolated PostgreSQL expand/legacy-writer harness remains for CI because Docker/PostgreSQL was unavailable locally. |
| Backend SAST | Bandit reported clean. | Passed locally | Does not replace provider or runtime review. |
| Backend dependencies | `pip-audit` reported clean. | Passed locally | Must remain tied to the tested environment and final revision. |
| Frontend units | `npm test`: `175/175` passed. | Passed locally | Local unit evidence only. |
| Frontend build and locale chunks | Production build passed; lazy-load assertion found `11` locale chunks. | Passed locally | Does not validate a Vercel deployment or translation quality. |
| Frontend production dependency audit | `npm audit --omit=dev`: `0` vulnerabilities. | Passed locally | Re-run if production dependency inputs change. |
| Full browser matrix | `315` total: `308 passed`, `7` intentional Chromium/PDF fixture skips. | Passed locally | Local Playwright evidence across Chromium, Firefox, WebKit, mobile Chromium, and mobile WebKit. |
| Offline production smoke | `2/2` passed. | Passed locally | Local offline production-mode evidence only. |
| Targeted browser repeats | WebKit skip-link keyboard path `20/20`; Firefox reflection persistence `10/10`; restored-session recovery Chromium/WebKit `2/2`. | Passed locally | Supporting reruns overlap the full matrix and are not additional release-test totals. |
| Device simulation | `12/12` viewport profiles reported Pass with Issues=None from clean SHA `0273347...`; changed session screenshots and narrow-phone labels were visually reviewed. | Passed locally | Chromium viewport automation is synthetic and does not validate physical Safari/iPad behavior. |
| Swift package | BrassTuneCore `3/3`. | Passed locally | Shared-package evidence only. |
| Native app units | `104/104`, including pending/active tuner release on scene deactivation and duplicate-transition suppression. | Passed locally | Simulator unit evidence; no physical audio or provider lifecycle claim. |
| Native UI smoke | `8/8`. | Passed locally | Fixture-backed simulator UI evidence. |
| Native simulator builds and launch frames | Debug and Release iPhone/iPad builds plus launch-frame checks passed. | Passed locally | Unsigned simulator evidence; not archive, signing, TestFlight, or physical-device evidence. |
| Native localization | `556` source keys, `562` catalog entries, `159` sentinels, `1,511` locale assertions; zero violations. | Passed locally | Static coverage evidence; human linguistic and RTL review remains required. |
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
