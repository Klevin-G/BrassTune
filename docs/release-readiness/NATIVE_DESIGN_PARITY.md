# Native Design Parity

Status: native visual polish upgraded locally; App Store, physical microphone, and provider gates remain open.

## Web Sources

- `frontend/src/styles/layout.css`
- `frontend/src/styles/responsive.css`
- `frontend/src/components/ui/AppPrimitives.tsx`
- `frontend/src/pages/DashboardPage.tsx`
- `frontend/src/pages/PracticePage.tsx`
- `frontend/src/pages/AnalyticsPage.tsx`
- `frontend/src/pages/SettingsPage.tsx`

## SwiftUI Equivalents

- `swift/BrassTuneApp/BrassTuneApp/DesignSystem/BrassTuneDesignSystem.swift`
- `swift/BrassTuneApp/BrassTuneApp/AppRootView.swift`
- `swift/BrassTuneApp/BrassTuneApp/SettingsViews.swift`

The native app now uses shared SwiftUI primitives for screens, cards, metric tiles, status pills, empty states, and branded buttons. The main screens use card-based scroll layouts rather than default scaffold lists.

## Current Native Behavior

- Home shows a beta account state and local-practice focus.
- Practice has a prominent local sample-take tuner, microphone permission state, and saved-take actions.
- Sessions supports review and delete for local demo sessions.
- Analytics derives metrics from local sessions.
- Ensemble clearly labels account-required/demo state.
- Settings exposes account, tuner, export, delete, legal, support, and beta limitations.

## Evidence

- Native unit tests pass.
- iPhone Debug/Release and iPad Debug simulator builds pass.
- `BrassTuneAppUISmoke` passes the first-launch, practice, record/stop, analytics, session review, delete, and settings journey.

Screenshot capture instructions live in `docs/release-readiness/native-screenshots/README.md`.

## Remaining Differences

- Native microphone quality is not validated on physical brass hardware.
- Native live cloud sync and Apple account flows remain provider/config gated.
- Visual tuning can continue after tester screenshots from real iPhone/iPad hardware.
