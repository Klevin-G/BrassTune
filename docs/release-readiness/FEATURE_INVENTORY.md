# Feature Inventory

Updated: 2026-07-23. This is an implementation inventory, not a hosted-release claim.

| Area | Candidate capability | Evidence boundary |
|---|---|---|
| Tuner and focused practice | Tuner-first workspace, local-first practice paths, progress, favorites, recents, and offline packs | Local web/native tests and simulator evidence. |
| Guided practice | Five-minute warm-up, custom Play-Along builder, named metronome presets, weekly goals/reflections, weak-transition drills, drone and interval tuning | Local feature and journey coverage. |
| Scoring | Shared pitch-domain scoring and focused QA fixtures | No physical microphone or real brass performance claim. |
| Classes | Create/join/invite/roster workflows and role-aware aggregate summaries | Aggregate scope intentionally excludes raw practice detail. |
| Authentication | Email/password/reset plus Google and Apple affordances on web/iOS | Google live provider start is verified; Apple remains disabled live. |
| Localization | 12 locales; web non-English catalogs are lazy-loaded | Professional linguistic review remains a human gate. |
| Native | SwiftUI iPhone/iPad experience, auth/class/practice parity, Keychain, AVAudioEngine path | Simulator evidence only; no signing/device acceptance. |
| Data lifecycle | Export/delete, privacy scrub/tombstone rollout support | Disposable live lifecycle testing and migration application remain pending. |

## Explicit limits

Audio recordings and score sources are local-first unless the user explicitly uses a supported cloud path. Class reporting is aggregate-only; it is not a surveillance or raw-recording review feature.
