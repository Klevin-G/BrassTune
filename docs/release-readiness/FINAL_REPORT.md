# BrassTune Release Evidence

Updated: 2026-07-24. Deployed application revision: `cfaa3c59d34676d180907c78d7cdd1b9de3299f7`.

## Decision

The web/backend production candidate is verified at the deployed revision above. Direct Render and Vercel identities report that exact SHA, hosted infrastructure smoke passed, and the strict hosted browser matrix passed. GitHub Actions was not used because its minutes are exhausted. This is not an Apple distribution or physical-device release decision.

## Verified evidence

| Surface | Result | Boundary |
|---|---:|---|
| Backend | `299 passed, 11 skipped` | Local automated suite. |
| Frontend units | `261` passed | Local automated suite. |
| Frontend production build | Passed | Local Vite production artifact. |
| Local Playwright | `443 passed, 7 expected skips` | Five browser/device projects; local only. |
| Device simulation | 12 viewports passed | Simulated browser coverage, not physical devices. |
| Swift Core | `3` passed | Shared-domain package coverage. |
| Native unit tests | `158` passed | Simulator evidence only. |
| Native UI tests | All 20 scenarios passed | Completed in bounded batches, not one monolithic run; simulator evidence only. |
| Simulator build/run | Zero warnings and errors | Unsigned simulator evidence only. |
| Localization | 12 locales, zero coverage gaps | Does not establish human linguistic review. |

## Production deployment evidence

- Render deployment `dep-d9i309jh2c0s7382bc8g` is live and reports `cfaa3c59d34676d180907c78d7cdd1b9de3299f7`.
- Vercel deployment `dpl_5TjKnoJ3cV5nwSjpiTCTmTEAPg8v` is READY in production at [brasstune.vercel.app](https://brasstune.vercel.app) and reports the same SHA.
- The frontend SHA injection was explicit for the prebuilt deployment, so the production bundle reports the intended revision rather than an inferred build identity.
- Hosted infrastructure smoke passed `8/8` checks.
- The strict hosted browser matrix passed `50/50` checks across five projects.
- Render returned no error-level or 5xx logs after the final deploy, and Vercel returned no error logs for the final production deployment in the checked window.

## Security and dependency boundary

`npm audit` continues to report two high-severity dependency entries: direct `react-router-dom` and its indirect `react-router` dependency. The identified React Router advisory `GHSA-qwww-vcr4-c8h2` is non-applicable to the current client-only Vite SPA because it does not use unstable React Server Components APIs. The audit findings remain tracked for dependency maintenance; this statement does not suppress the audit result.

## Current product/release configuration

- GitHub Actions remains unused for this candidate.
- Apple sign-in and native Google sign-in controls are hidden. They must remain hidden until Apple sign-in is configured and both native providers are verified together.
- Native local recordings are distinct from signed-in web recordings; App Store privacy answers must be reconciled against the signed build and live web behavior.

## Point-in-time Supabase configuration evidence

The linked active/healthy Supabase project `yznziwewxrlwnwiynlvl` was checked with the Supabase CLI. Local and remote migration histories matched through `20260724072904`. The `session-audio` bucket was private, had a 52,428,800-byte limit, allowed `webm`, `mp4`, `mpeg`, `wav`, and `ogg`, and had zero browser-facing storage policies. Every public table had RLS enabled, and `anon` and `authenticated` had no DML grants.

Security advisors returned two warnings: the `pg_net` extension is installed in `public`, and leaked-password protection is disabled. Supabase documentation notes that leaked-password protection requires a Pro plan. This is point-in-time live configuration evidence, not a blanket security certification or proof of application behavior.

## Remaining external gates

- Signed archive and TestFlight upload.
- Physical iPhone/iPad checks for Ring/Silent behavior, microphone/brass input, Bluetooth/audio routes, interruptions, local recording deletion, and file-protection behavior.
- Live App Store Connect privacy answers, review metadata, age rating, export compliance, and review access.
- Human language review.

No claim in this report establishes a signed archive, TestFlight build, App Store approval, signed-in private-audio lifecycle, or physical-device audio behavior.
