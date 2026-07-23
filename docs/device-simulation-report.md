# Device Simulation Report

Generated: 2026-07-23T06:46:47.253Z
Checkout: f83108422d7ca8c76267a337297e627762ab028a (clean worktree)

The committed Playwright harness was used for repeatable multi-viewport browser automation.

## Summary

| Viewport | Size | Routes Visited | Result | Issues |
| --- | ---: | --- | --- | --- |
| Tiny phone | 320x568 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Phone small | 360x740 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| iPhone modern | 393x852 | Auth Gateway, Sign In, Onboarding, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Large phone | 430x932 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Foldable narrow tablet | 540x720 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| iPad portrait | 768x1024 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| iPad landscape | 1024x768 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| iPad Pro landscape | 1366x1024 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Laptop | 1440x900 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Wide desktop | 1728x1117 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Desktop HD | 1920x1080 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |
| Ultra-wide desktop | 2560x1440 | Auth Gateway, Sign In, Tuner, Play-Along, Metronome, Sheet Music, Session Review, Progress, Sessions, Class, Settings | Pass | None |

## Screenshots Generated

- tiny-phone-practice.png (Tiny phone)
- phone-auth.png (iPhone modern)
- phone-onboarding.png (iPhone modern)
- phone-practice.png (iPhone modern)
- phone-session-review.png (iPhone modern)
- phone-progress.png (iPhone modern)
- phone-session-playback.png (iPhone modern)
- ipad-portrait-practice.png (iPad portrait)
- ipad-landscape-practice.png (iPad landscape)
- ipad-landscape-progress.png (iPad landscape)
- desktop-practice.png (Laptop)
- desktop-session-review.png (Laptop)
- desktop-ensemble.png (Laptop)
- desktop-settings.png (Laptop)
- desktop-progress-dashboard.png (Wide desktop)
- ultrawide-progress-dashboard.png (Ultra-wide desktop)

## Remaining Risks

- Playwright Chromium covers layout and interaction behavior, but not Safari/WebKit rendering differences on physical iPad hardware.
- Demo recording creates local sample sessions during simulation; this is expected for the current local MVP database.
- CI cannot exercise native iOS camera pickers or choose a physical local video from Photos; those checks remain in the manual phone test plan.
- Tables are intentionally allowed to scroll horizontally only inside `.table-wrap` when the advanced mobile table is opened.
