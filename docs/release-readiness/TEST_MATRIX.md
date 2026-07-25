# Release Test Matrix

Updated: 2026-07-24. Hosted web/backend evidence is recorded at `cfaa3c59d34676d180907c78d7cdd1b9de3299f7`; other passing rows are local or simulator evidence unless stated otherwise.

| Gate | Evidence | Status | Release meaning |
|---|---|---|---|
| Backend | `299 passed, 11 skipped` | Passed locally | Corroborated by the hosted exact-SHA identity and infrastructure smoke below; not a private-audio lifecycle check. |
| Frontend units | `261` passed | Passed locally | Corroborated by the strict hosted browser matrix below. |
| Frontend production build | Passed | Passed locally | Corroborated by Vercel's exact-SHA production identity below. |
| Local Playwright | `443 passed, 7 expected skips` across five browser/device projects | Passed locally | Local journey evidence only. |
| Device simulation | 12 viewports passed | Passed locally | Not physical-device evidence. |
| Swift Core | `3` passed | Passed locally | Shared-domain coverage only. |
| Native unit tests | `158` passed | Passed in simulator | Unsigned simulator evidence only. |
| Native UI tests | All 20 scenarios passed in bounded batches | Passed in simulator | Not a monolithic run; unsigned simulator evidence only. |
| Simulator build/run | Zero warnings and errors | Passed in simulator | Does not prove archive signing or hardware behavior. |
| Localization | 12 locales, zero coverage gaps | Passed locally | No human linguistic review recorded. |
| Dependency audit | Two high-severity entries remain: direct `react-router-dom` and indirect `react-router` | Pending maintenance | React Router `GHSA-qwww-vcr4-c8h2` is non-applicable to this client-only Vite SPA; audit remains open. |
| GitHub Actions | Disabled/unused | Not applicable | Direct provider deployment is required; Actions minutes are exhausted. |
| Supabase live configuration | Active/healthy project checked by CLI; migrations match through `20260724072904`; private `session-audio` bucket and RLS/grant boundaries verified | Passed point-in-time | Advisors still warn on `pg_net` in `public` and disabled leaked-password protection; not a blanket security certification. |
| Render deployment | `dep-d9i309jh2c0s7382bc8g` live; exact SHA reported | Passed | Web/backend production identity verified. |
| Vercel deployment | `dpl_5TjKnoJ3cV5nwSjpiTCTmTEAPg8v` READY; [canonical production URL](https://brasstune.vercel.app); exact SHA reported | Passed | Explicit frontend SHA injection used for the prebuilt deployment. |
| Hosted infrastructure smoke | `8/8` passed | Passed | Infrastructure boundary only; not a signed-in private-audio lifecycle check. |
| Strict hosted browser matrix | `50/50` across five projects | Passed | Hosted browser evidence; not physical-device audio evidence. |
| Post-deploy error scan | No Render error-level/5xx logs and no Vercel error logs in the checked window | Passed | Point-in-time provider evidence only. |
| Apple sign-in / native Google | Controls hidden | Intentional hold | Do not expose native third-party sign-in until Apple is configured and dual-provider behavior is verified. |
| Signed archive and TestFlight | Not yet recorded | Pending | Required for Apple distribution. |
| Physical device audio | Not yet recorded | Pending | Test Ring/Silent, microphone/brass input, Bluetooth/routes, interruptions, recording deletion, and file protection. |
| App Store Connect metadata | Not yet recorded | Pending | Privacy, review metadata/access, age rating, and export compliance remain owner gates. |

## Reproduction boundary

Later source changes, a deployment, or an archive require a fresh corresponding test/deployment record. Hosted passes do not establish signed, TestFlight, App Store, signed-in private-audio lifecycle, or physical-device success.
