# Release Test Matrix

Updated: 2026-07-24. All passing rows below are local or simulator evidence unless stated otherwise. No hosted deployment identity is recorded yet.

| Gate | Evidence | Status | Release meaning |
|---|---|---|---|
| Backend | `299 passed, 11 skipped` | Passed locally | Requires hosted backend verification after direct deployment. |
| Frontend units | `261` passed | Passed locally | Requires deployed-bundle smoke. |
| Frontend production build | Passed | Passed locally | Requires Vercel deployment identity check. |
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
| Hosted deployment and smoke | Not yet recorded | Pending | Record direct Render/Vercel identities, exact SHA, and smoke evidence. |
| Apple sign-in / native Google | Controls hidden | Intentional hold | Do not expose native third-party sign-in until Apple is configured and dual-provider behavior is verified. |
| Signed archive and TestFlight | Not yet recorded | Pending | Required for Apple distribution. |
| Physical device audio | Not yet recorded | Pending | Test Ring/Silent, microphone/brass input, Bluetooth/routes, interruptions, recording deletion, and file protection. |
| App Store Connect metadata | Not yet recorded | Pending | Privacy, review metadata/access, age rating, and export compliance remain owner gates. |

## Reproduction boundary

Later source changes, a deployment, or an archive require a fresh corresponding test/deployment record. Local and simulator passes do not establish hosted, signed, TestFlight, App Store, or physical-device success.
