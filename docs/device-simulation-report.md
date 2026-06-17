# Device Simulation Report

Generated: 2026-06-17T19:15:27.809Z

The committed Playwright harness was used for repeatable multi-viewport browser automation.

## Summary

| Viewport | Size | Routes Visited | Result | Issues |
| --- | ---: | --- | --- | --- |
| Tiny phone | 320x568 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Phone small | 360x740 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| iPhone modern | 393x852 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Large phone | 430x932 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Foldable narrow tablet | 540x720 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| iPad portrait | 768x1024 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| iPad landscape | 1024x768 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| iPad Pro landscape | 1366x1024 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Laptop | 1440x900 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Wide desktop analytics | 1728x1117 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Desktop HD | 1920x1080 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |
| Ultra-wide desktop | 2560x1440 | Home, Practice, Session Review, Analytics, Coach, Sessions, Progress, Ensemble, More, Settings | Pass | None |

## Screenshots Generated

- tiny-phone-practice.png (Tiny phone)
- phone-home.png (iPhone modern)
- phone-practice.png (iPhone modern)
- phone-session-review.png (iPhone modern)
- phone-analytics.png (iPhone modern)
- ipad-portrait-practice.png (iPad portrait)
- ipad-landscape-practice.png (iPad landscape)
- ipad-landscape-analytics.png (iPad landscape)
- desktop-home.png (Laptop)
- desktop-practice.png (Laptop)
- desktop-session-review.png (Laptop)
- desktop-ensemble.png (Laptop)
- desktop-analytics-dashboard.png (Wide desktop analytics)
- ultrawide-analytics-dashboard.png (Ultra-wide desktop)

## Remaining Risks

- Playwright Chromium covers layout and interaction behavior, but not Safari/WebKit rendering differences on physical iPad hardware.
- Demo recording creates local sample sessions during simulation; this is expected for the current local MVP database.
- Tables are intentionally allowed to scroll horizontally only inside `.table-wrap` when the advanced mobile table is opened.
