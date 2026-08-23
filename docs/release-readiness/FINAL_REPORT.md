# BrassTune Release Evidence
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. The historical report below retains its original evidence. Current live and local facts are recorded separately and do not certify physical-device audio behavior or App Review acceptance.

## 2026-08-23 verified current evidence

- Apple Developer membership: **Enrolled as Individual**.
- The public [iTunes lookup for app 6795688588](https://itunes.apple.com/lookup?id=6795688588) returns BrassTune `1.0`, `sellerName`/`artistName` `Arya Salem`, and release date `2026-08-18`.
- The release implementation was merged through [PR #28](https://github.com/Klevin-G/BrassTune/pull/28) at `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`. Later documentation-only evidence commits do not change the candidate code.
- Backend validation: `346 passed, 13 skipped`; targeted Bandit and `pip-audit` passed. A disposable PostgreSQL 17 run passed the new avatar migration constraints and concurrent replacement regression.
- Web validation: `279/279` units and the production build passed; local Playwright passed `548` with `7` capability skips across five projects; the offline production-build suite passed `3/3`.
- Native validation: Swift Core passed `12/12`; the exact simulator app-unit suite passed `270/270`; the exact-current monolithic UI suite passed `26/26` in 790.802 test seconds on iPhone 17 Pro / iOS 26.5 simulator.
- Connected iPhone validation: the Debug app initially exposed a missing Swift-package runtime search path, which was repaired with `@executable_path/Frameworks`. The signed physical app-unit suite then passed `259`, skipped `11` source-tree-only audits, and failed `0` on the connected iPhone 15 Pro Max / iOS 26.6.1. Physical UI automation reached a device authorization timeout before any scenario executed; that is not counted as an app test failure or a pass.
- Static/release validation: localization passed with `890` static keys and `1,027` catalog entries; the design-token and privacy-manifest checks passed; documentation credits passed for `91` owned Markdown files. The Supabase avatar migration was applied to the linked project and its private bucket/schema constraints were verified.
- Vercel deployment `dpl_JAMX7E6udEZ5atVD8EPZrcnEo1pS` is **READY** at [brasstune.vercel.app](https://brasstune.vercel.app) and its production metadata reports the exact release-implementation SHA `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`.
- Render remains stale at `1cd195ed75dee61420d497438f4a4b54c07be25f`. Dashboard deployment is blocked by its GitHub authentication handoff, and the exact-SHA GitHub Actions deployment dispatch is queued without a runner. Therefore no hosted smoke is claimed for the merged backend.
- Build `1.0.1 (6)` was archived, exported, distribution-signed, and uploaded. TestFlight processing completed and build 6 is **Ready to Submit**. App Store Connect version `1.0.1` exists with build 6 attached and metadata saved. Its final Add for Review/submit action is intentionally held until Render serves the exact backend SHA and hosted smoke passes.
- The App Privacy declaration is published for Email Address, User ID, Other User Content, Name, and Photos or Videos: each is linked to the user, used for App Functionality, and not used for tracking. Guest sign-in-required is unchecked.

The individual developer-name result remains open: an individual cannot select `BrassTune`, and the existing name cannot be edited in the ordinary UI. Apple Developer Support or an eligible organization transfer is required; eligibility and legal DBA/trade-name treatment remain a human/Apple decision.

## Decision

The source is committed and the web production deployment, Supabase migration, signed `1.0.1 (6)` archive, TestFlight processing, App Store version/metadata, and privacy declaration are current. Submission remains held because Render does not yet serve the exact backend revision and hosted smoke has not been rerun against that revision. Physical app-unit execution passed after the runtime-path repair; attended microphone/speaker quality and physical UI automation remain separate gates.

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

- Deploy Render at release implementation `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`, then run and retain hosted smoke evidence.
- Complete the connected-iPhone UI suite after the device authorizes UI automation; conduct attended physical microphone/brass, Ring/Silent, Bluetooth/wired-route, interruption, local-recording deletion, and file-protection checks.
- Add for Review/submit version `1.0.1` only after the backend/hosted gate; App Review acceptance remains external.
- Human language review and developer-name action through Apple Support/entity/transfer path.

No claim in this report establishes hosted exact-backend behavior, App Review acceptance, signed-in private-audio lifecycle acceptance, or physical-device audio behavior.
