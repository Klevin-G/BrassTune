# Device Simulation Report

Generated: 2026-06-21T05:24:19.038Z

The committed Playwright harness was used for repeatable multi-viewport browser automation.

## Summary

| Viewport | Size | Routes Visited | Result | Issues |
| --- | ---: | --- | --- | --- |
| Tiny phone | 320x568 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Phone small | 360x740 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| iPhone modern | 393x852 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Large phone | 430x932 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Foldable narrow tablet | 540x720 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| iPad portrait | 768x1024 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| iPad landscape | 1024x768 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| iPad Pro landscape | 1366x1024 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Laptop | 1440x900 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Wide desktop analytics | 1728x1117 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Desktop HD | 1920x1080 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |
| Ultra-wide desktop | 2560x1440 | Auth Gateway, Home, Onboarding, Practice, Metronome, Score Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings, Audio Lab | Pass | None |

## Screenshots Generated

- tiny-phone-practice.png (Tiny phone)
- phone-auth.png (iPhone modern)
- phone-home.png (iPhone modern)
- phone-onboarding.png (iPhone modern)
- phone-practice.png (iPhone modern)
- phone-session-review.png (iPhone modern)
- phone-analytics.png (iPhone modern)
- phone-session-playback.png (iPhone modern)
- ipad-portrait-practice.png (iPad portrait)
- ipad-landscape-practice.png (iPad landscape)
- ipad-landscape-analytics.png (iPad landscape)
- desktop-home.png (Laptop)
- desktop-practice.png (Laptop)
- desktop-session-review.png (Laptop)
- desktop-ensemble.png (Laptop)
- audio-lab.png (Laptop)
- desktop-analytics-dashboard.png (Wide desktop analytics)
- ultrawide-analytics-dashboard.png (Ultra-wide desktop)

## Remaining Risks

- Playwright Chromium covers layout and interaction behavior, but not Safari/WebKit rendering differences on physical iPad hardware.
- Demo recording creates local sample sessions during simulation; this is expected for the current local MVP database.
- CI cannot exercise native iOS camera pickers or choose a physical local video from Photos; those checks remain in the manual phone test plan.
- Tables are intentionally allowed to scroll horizontally only inside `.table-wrap` when the advanced mobile table is opened.
