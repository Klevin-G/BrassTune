# BrassTune Release Evidence
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. The historical report below retains its original evidence. Current live and local facts are recorded separately and do not certify physical-device audio behavior or App Review acceptance.

## 2026-08-23 verified current evidence

- Apple Developer membership: **Enrolled as Individual**.
- The public [iTunes lookup for app 6795688588](https://itunes.apple.com/lookup?id=6795688588) returns BrassTune `1.0`, `sellerName`/`artistName` `Arya Salem`, and release date `2026-08-18`.
- The deployed release implementation is `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0` (PR #28). The native follow-up archive source is `d371100` on `arya/final-physical-release-20260823`; it is distinct from the deployed implementation and any future merge SHA must be recorded separately.
- Backend validation: `346 passed, 13 skipped`; targeted Bandit and `pip-audit` passed. A disposable PostgreSQL 17 run passed the new avatar migration constraints and concurrent replacement regression.
- Web validation: `279/279` units and the production build passed; local Playwright passed `548` with `7` capability skips across five projects; the offline production-build suite passed `3/3`.
- Native validation: simulator units passed `272/272`; localization passed with `889` static keys and `1,027` catalog entries, zero violations; design/privacy/diff checks passed.
- Physical-device validation: automation canary `1/1` in 14.058 s, strict accessibility `1/1` in 79.342 s, standard suite `26/26` in 774.943 s, and expanded audio stress `1/1` in 511.046 s. The latter exercised 20 tuner listener reinstall cycles, three explicit take/save cycles, remaining tools, and tab switching. An earlier sustained-120-BPM check passed `1/1` in about 209.963 s.
- Broad physical XCUI detector findings were audited as false positives using screenshots and token-ratio checks; that audit does not substitute for unavailable attended or assistive-technology validation.
- Vercel and Render both serve release implementation `98fd1d9e7b85add63537e2d386a3b2e2e3dfe6d0`; the strict hosted Playwright matrix passed `50/50` across five projects.
- Build `1.0.1 (7)` from native source `d371100` was archived and exported. The IPA has a strict valid Apple Distribution signature (`Apple Distribution: Arya Salem`, team `8S79RLTSWV`), production environment/API configuration, bundle `com.aryasalem.BrassTune`, matching app/dSYM UUID `77D84475-6D50-3D94-B842-290431F0D74D`, and SHA-256 `640511f5a15f579500f86710393a6f661ced4cff87a64f00b8ccbe689bea2782`.
- Build 7 upload succeeded, TestFlight reports **Ready to Submit**, and App Store Connect version `1.0.1` has build 7 attached. Stale review notes were replaced; the version was submitted and now reports **Waiting for Review** with manual release selected.
- The App Privacy declaration is published for Email Address, User ID, Other User Content, Name, and Photos or Videos: each is linked to the user, used for App Functionality, and not used for tracking. Guest sign-in-required is unchecked.

The individual developer-name result remains open: an individual cannot select `BrassTune`, and the existing name cannot be edited in the ordinary UI. Apple Developer Support or an eligible organization transfer is required; eligibility and legal DBA/trade-name treatment remain a human/Apple decision.

## Decision

The hosted exact-release gate is closed for implementation SHA `98fd1d9`. The submitted native candidate is build `1.0.1 (7)` from `d371100`, whose signed/archive/TestFlight/App Store state is independently recorded above. It is Waiting for Review with manual release; App Review acceptance is external. Physical automation is strong for the listed runs, but unavailable attended and route-specific gates remain open.

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

- Vercel and Render serve implementation `98fd1d9`; strict hosted Playwright passed `50/50` across five projects.
- Apple/Google provider configuration is deployed. Configuration is not proof of every live provider lifecycle, which remains separately bounded.
- Native local recordings remain distinct from signed-in web recordings. App Privacy is published for submitted build 7 and must be reconciled with future signed builds and live cloud behavior.

## Point-in-time Supabase configuration evidence

The linked active/healthy Supabase project `yznziwewxrlwnwiynlvl` was checked with the Supabase CLI. Local and remote migration histories matched through `20260724072904`. The `session-audio` bucket was private, had a 52,428,800-byte limit, allowed `webm`, `mp4`, `mpeg`, `wav`, and `ogg`, and had zero browser-facing storage policies. Every public table had RLS enabled, and `anon` and `authenticated` had no DML grants.

Security advisors returned two warnings: the `pg_net` extension is installed in `public`, and leaked-password protection is disabled. Supabase documentation notes that leaked-password protection requires a Pro plan. This is point-in-time live configuration evidence, not a blanket security certification or proof of application behavior.

## Remaining external gates

- App Review outcome for submitted version `1.0.1` build 7; manual release remains selected.
- Attended calibrated brass/acoustic accuracy; AirPlay/HomePod, Bluetooth, and wired audio routes; Files/Photos preseeded fixtures; timer/media-reset operator prerequisites; and full assistive-technology/iPad coverage.
- Human language review and developer-name action through Apple Support/entity/transfer path.

No claim in this report establishes App Review acceptance, calibrated acoustic accuracy, unavailable accessory-route behavior, full assistive-technology coverage, or signed-in private-audio lifecycle acceptance.
