# BrassTune Release Evidence
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-24. The historical report below retains its original evidence.

## Current release candidate — `5acfa2e`

PR 32 merged implementation/archive/deployment candidate
`5acfa2ecc6b7403d1572d7382d41357c8ccc2fb4`. A later SHA may contain this
docs-only follow-up; it does not change the candidate identity.

- Student views support joining/consenting, membership status, and a useful
  personal contribution summary.
- Owner views support a roster, invite/join controls, role-aware aggregate
  progress, and actionable participation follow-up; assistant views support
  the delegated roster/reporting surfaces allowed by their role.
- The deliberately narrow, benchmark-inspired classroom boundary is aggregate
  practice participation and timing/pitch progress. It excludes assignments,
  grading, raw audio, reflection text, score content, note events, and
  per-session detail.
- Local evidence: backend `356 passed, 13 skipped`; web `288/288` plus
  production build; class Playwright `55/55`; Swift Core `12/12`; native
  `278/278`; the implementation-snapshot full native UI suite `26/26`; and a
  dedicated final Classes student/owner/assistant UI check `1/1`.
  Localization, design, diff, and `npm audit` checks completed. Final
  correctness review and security re-scan are closed. These are local checks,
  not hosted evidence.
- Supabase migration `20260824031433` is applied and read back: all five
  constraints validated, UUID default present, RLS enabled, and direct anon/
  authenticated `SELECT` is false.
- Vercel production is Ready and Render is Ready at `5acfa2e`; hosted smoke
  passed `45` with `5` strict skips.
- Archive/export `1.0.1 (8)` uses canonical Supabase project `yznziwe`, bundle
  `com.aryasalem.BrassTune`, Apple Distribution team `8S79RLTSWV`,
  `get-task-allow=false`, `beta-reports-active=true`, and a privacy manifest.
  IPA SHA-256: `cade0c9842e99f2e77e1f1b27e408460a331b880beb59f59d7f11f8f579ffe8c`;
  app/dSYM UUID: `8378AB6E-EA6E-32B3-A26E-F781A481518D`.
- The archive evidence root is
  `/Users/aryasalem/Library/Application Support/BrassTune/ReleaseEvidence/AppStoreCandidate-2026-08-24-1.0.1-8`.
  Upload succeeded, processing is Complete/Ready to Submit, build 8 is
  selected, and metadata/review notes are updated. Submission
  `14b8ba6a-fe40-421f-ab61-790bbe51cb08` was submitted by Arya Salem on
  August 24 and is **Waiting for Review** with manual release.
- Nandy’s physical Classes fixture UI passed `1/1`; it remains fixture UI
  evidence, not live hosted multi-account synchronization evidence.

Build 7 is historical and removed/superseded. App Review acceptance remains
external.

## Historical 2026-08-23 evidence

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
- Historical build 7 upload succeeded, TestFlight reported **Ready to Submit**,
  and the earlier version was submitted. Build 7 is now removed/superseded by
  submitted build 8.
- The App Privacy declaration is published for Email Address, User ID, Other User Content, Name, and Photos or Videos: each is linked to the user, used for App Functionality, and not used for tracking. Guest sign-in-required is unchecked.

The individual developer-name result remains open: an individual cannot select `BrassTune`, and the existing name cannot be edited in the ordinary UI. Apple Developer Support or an eligible organization transfer is required; eligibility and legal DBA/trade-name treatment remain a human/Apple decision.

## Decision

The current candidate is `5acfa2e` / `1.0.1 (8)`, submitted and Waiting for
Review with manual release. App Review acceptance is external; calibration,
accessory-route, and complete assistive-technology coverage remain separate
boundaries.

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

- Render deployment `dep-da5su18u01pc738d2bgg` is live and `/api/version`
  reports `5acfa2ecc6b7403d1572d7382d41357c8ccc2fb4`; `/api/ready` is fully green.
- Vercel production deployment `dpl_3sjexExPziFZdivrwKHdak9mptud` is Ready at
  [brasstune.vercel.app](https://brasstune.vercel.app) for the same SHA.
- Hosted smoke passed `45/45` with `5` intentional strict-content skips across
  Chromium, Firefox, WebKit, mobile Chromium, and mobile WebKit. It verified
  immutable frontend identity, backend health/CORS, secure WebSocket behavior,
  auth surfaces, deep links, and hosted URL hygiene.
- Vercel returned no error logs for the final production deployment in the checked window.

## Security and dependency boundary

`npm audit --omit=dev` reports zero vulnerabilities. Independent correctness,
security, secret, and artifact reviews closed with no remaining release blocker.

## Current product/release configuration

- Vercel and Render serve implementation `5acfa2e`; hosted Playwright passed
  `45/45` with `5` intentional strict-content skips across five projects.
- Apple/Google provider configuration is deployed. Configuration is not proof of every live provider lifecycle, which remains separately bounded.
- Native local recordings remain distinct from signed-in web recordings. App
  Privacy is published for submitted build 8 and includes linked Other User
  Content for signed-in practice/class functionality.

## Point-in-time Supabase configuration evidence

The linked active/healthy Supabase project `yznziwewxrlwnwiynlvl` was checked
with the Supabase CLI. Local and remote migration histories match through
`20260824031433`. The Classes migration was applied and read back: five required
unique/check constraints are validated, `roster_row_id` has a UUID server
default, the three affected tables have RLS enabled, and `anon` and
`authenticated` have no direct SELECT grants.

Security advisors returned two warnings: the `pg_net` extension is installed in `public`, and leaked-password protection is disabled. Supabase documentation notes that leaked-password protection requires a Pro plan. This is point-in-time live configuration evidence, not a blanket security certification or proof of application behavior.

## Remaining external gates

- App Review outcome for submission `14b8ba6a-fe40-421f-ab61-790bbe51cb08`,
  version `1.0.1` build 8; manual release remains selected.
- Attended calibrated brass/acoustic accuracy; AirPlay/HomePod, Bluetooth, and wired audio routes; Files/Photos preseeded fixtures; timer/media-reset operator prerequisites; and full assistive-technology/iPad coverage.
- Human language review and developer-name action through Apple Support/entity/transfer path.

No claim in this report establishes App Review acceptance, calibrated acoustic accuracy, unavailable accessory-route behavior, full assistive-technology coverage, or signed-in private-audio lifecycle acceptance.
