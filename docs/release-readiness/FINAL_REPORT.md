# BrassTune Release Candidate Evidence

Updated: 2026-07-23. Pre-push code/test revision: `a3f436ea7442c471760e06ed1422ec3ddbbf1217`.

## Decision

Ready to push for exact-SHA self-hosted CI; not deployed or merged. Web, native, shared-domain, accessibility, and privacy work has current local evidence. `428a123` fixes the duplicate-identity PII race and the full backend suite passes `246 passed, 4 skipped`. The self-hosted SQLite runner fix in `c66be02` still requires live exact-head CI evidence.

## Verified local evidence

| Surface | Result | Boundary |
|---|---|---|
| Backend | `246 passed, 4 skipped` after the `428a123` duplicate-identity PII race correction | Local result; exact-SHA self-hosted CI remains required. |
| Web unit/build/dependency audit | `251/251`, production build, `11` lazy non-English locale chunks, `npm audit --omit=dev` with `0` findings | Local only. |
| Web browser journeys | `443 passed, 7 skipped, 0 failed` | Local automation only. |
| Shared pitch domain | Swift Core `3/3` | Does not prove physical audio capture. |
| Native unit/UI | `140/140` units; `17/17` UI tests in one invocation, result bundle `/tmp/brasstune-final-a3f436e-all-ui.xcresult` | Unsigned simulator only. |
| Native builds | Debug iPhone/iPad and Release iPhone passed with zero warnings | Not an archive, signing, or device result. |

## Product scope represented in the candidate

- A focused tuner-first practice workspace, five-minute guided warm-up, custom Play-Along builder, named metronome presets, favorites/recent shortcuts, weekly goals/reflections, weak-transition drills, drone/interval tuning, and offline packs.
- Class creation, join/invite workflows, role-aware aggregate practice summaries, and an aggregate-only privacy contract.
- Twelve production locales: English, Spanish, Simplified Chinese, Traditional Chinese, Arabic, French, German, Russian, Portuguese (Brazil), Japanese, Korean, and Vietnamese. The web loads eleven non-English catalogs lazily.
- Web and iOS email/password auth plus Google and Apple sign-in surfaces. Google is live on the linked Supabase project; independent Google branding review approved the current native treatment. Apple implementation is complete but the live provider is disabled pending Apple Developer credentials and Supabase setup.

## Release blockers and order

1. Push the exact candidate and run required Backend, Frontend, Security, and Swift checks on the configured self-hosted runners. Confirm the `c66be02` SQLite runner fix in live exact-head CI.
2. Apply the three additive Supabase migrations, then deploy the privacy-aware backend and verify expand cleanup before creating or applying the terminal contract migration.
3. Sync approved Supabase redirect URLs/configuration, deploy Render and Vercel from the same merged SHA, and pass hosted REST, WebSocket, auth, class, audio, and offline smoke.
4. Complete human/device gates separately: Apple provider setup, signed archive/TestFlight, physical microphone/audio, accessibility, and localization checks.
5. Reconnect the outreach Gmail integration as `brasstune1@gmail.com` before creating professor drafts; the currently connected account is not the planned sender and must not receive duplicate drafts.

No claim in this report establishes production deployment, Apple provider enablement, signed native delivery, or physical-device microphone quality.
