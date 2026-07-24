# Web / Native Parity Contract

Updated: 2026-07-24. Candidate source revision: `PENDING_FINAL_SHA`.

| Surface | Web | iOS | Evidence boundary |
|---|---|---|---|
| First use | Clear sign-in/onboarding and tuner-first workspace | Full-screen SwiftUI welcome/onboarding | Local browser and simulator only. |
| Practice | Warm-up, packs, builder, metronome presets, drills, reflections, favorites/recent | Matching focused-practice and local practice surfaces | Native physical audio remains unverified. |
| Tuning | Pitch feedback, drone/interval tools, Play-Along scoring | AVAudioEngine/local detector and shared scorer | Fixtures/simulator do not certify real brass input. |
| Classes | Create, join, invite, roster, aggregate practice summaries | Matching authenticated class surfaces | Hosted auth/class lifecycle remains pending. |
| Auth | Email/password, Google and Apple buttons with available/disabled state | Apple token exchange and Google PKCE browser session | Google live provider start only; Apple provider disabled. |
| Localization | 12 locales with lazy non-English web chunks | String Catalog covers the same 12 locales | Human language QA remains pending. |

## Rules

- Keep web and iOS claims separate from hosting, signing, and hardware evidence.
- Google/Apple buttons may remain visible when a provider is unavailable; unavailable is an explicit state, not a hidden feature.
- Do not expose individual student recordings, note events, or session detail through class aggregates.
- Do not call iOS distribution-ready without physical iPhone/iPad validation, signing, archive, and TestFlight evidence.
