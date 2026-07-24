# BrassTune Release Candidate Evidence

Updated: 2026-07-23. Candidate source revision: `7c12b15`.

## Decision

Do not deploy or merge yet. Web, native, shared-domain, accessibility, and privacy work has current local evidence. `428a123` fixes the duplicate-identity PII race and the full backend suite now passes `246 passed, 4 skipped`. Exact-SHA self-hosted CI and live rollout evidence remain pending.

## Verified local evidence

| Surface | Result | Boundary |
|---|---|---|
| Backend | `246 passed, 4 skipped` after the `428a123` duplicate-identity PII race correction | Local result; exact-SHA self-hosted CI remains required. |
| Web unit/build/dependency audit | `251/251`, production build, `11` lazy non-English locale chunks, `npm audit --omit=dev` with `0` findings | Local only. |
| Web browser journeys | `443 passed, 7 skipped, 0 failed` | Local automation only. |
| Shared pitch domain | Swift Core `3/3` | Does not prove physical audio capture. |
| Native unit/UI | `139/139` units, `15/15` UI tests, plus `4/4` affected welcome/auth UI checks after `7c12b15` | Unsigned simulator only. |
| Native builds | Debug iPhone/iPad and Release iPhone passed with zero warnings | Not an archive, signing, or device result. |

## Product scope represented in the candidate

- A focused tuner-first practice workspace, five-minute guided warm-up, custom Play-Along builder, named metronome presets, favorites/recent shortcuts, weekly goals/reflections, weak-transition drills, drone/interval tuning, and offline packs.
- Class creation, join/invite workflows, role-aware aggregate practice summaries, and an aggregate-only privacy contract.
- Twelve production locales: English, Spanish, Simplified Chinese, Arabic, French, German, Russian, Portuguese, Japanese, Korean, Hindi, and Italian. The web loads eleven non-English catalogs lazily.
- Web and iOS email/password auth plus Google and Apple sign-in surfaces. Google is live on the linked Supabase project; Apple implementation is complete but the live provider is disabled pending Apple Developer credentials and Supabase setup.

## Release blockers and order

1. Run independent review and required Backend, Frontend, Security, and Swift checks on the configured self-hosted runners for the exact candidate.
2. Apply the three additive Supabase migrations, then deploy the privacy-aware backend and verify expand cleanup before creating or applying the terminal contract migration.
3. Sync approved Supabase redirect URLs/configuration, deploy Render and Vercel from the same merged SHA, and pass hosted REST, WebSocket, auth, class, audio, and offline smoke.
4. Complete human/device gates separately: Apple provider setup, signed archive/TestFlight, physical microphone/audio, accessibility, and localization checks.

No claim in this report establishes production deployment, Apple provider enablement, signed native delivery, or physical-device microphone quality.
