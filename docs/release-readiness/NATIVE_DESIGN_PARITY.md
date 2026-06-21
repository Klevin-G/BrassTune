# Native Design Parity

Updated: 2026-06-21T06:30:28Z

Status: repository-actionable native design parity is implemented for the current engineering scope. App Store, physical microphone, and live provider gates remain external.

## Shared Sources

- Web tokens: `design/brasstune-tokens.json`
- Native generated tokens: `swift/BrassTuneApp/BrassTuneApp/DesignSystem/GeneratedThemeTokens.swift`
- Native primitives: `swift/BrassTuneApp/BrassTuneApp/DesignSystem/BrassTuneDesignSystem.swift`
- Native shell/screens: `swift/BrassTuneApp/BrassTuneApp/AppRootView.swift`

## SwiftUI Equivalents

- `ThemeManager`, `BTThemeHost`, and `BTThemeSelector` provide System, Brass Night, Brass Day, Liquid Brass Clear, Liquid Brass Tinted, and High Contrast.
- `BTBentoGrid`, `BTBentoCard`, `BTHeroCard`, `BTMetricCard`, `BTQuickActionCard`, `BTStatusCard`, `BTChartCard`, `BTGlassToolbar`, `BTGlassCapsule`, and `BTAdaptiveSection` provide native Bento-style layout primitives.
- `BTLiquidGlassModifier` uses iOS 26 `glassEffect` where available and falls back to solid/material-like surfaces when transparency or contrast settings require it.

## Current Native Behavior

- Home uses a branded hero, status pill, and tab-clear first viewport.
- Practice uses the real native audio path for normal recording and deterministic test injection only during UI tests.
- Score Practice provides local file/photo/camera import metadata, PDF page limits, local markers, and conservative page/time review copy.
- Sessions supports review, local playback, export, and deletion of retained recordings.
- Metronome exposes native tempo, meter, subdivision, accent, mute, and recording-aware bleed messaging.
- Analytics, Progress, and Coach derive from local recorded sessions; insufficient-data states stay honest.
- Ensemble shows account-required or account-backed states without generated roster data.
- Settings exposes theme, account, tuner, export/delete, legal, and support controls.

## Evidence

- `swift/BrassTuneCore`: `swift test` passed, `3` tests.
- `BrassTuneAppTests`: passed, `9` XCTest cases.
- `BrassTuneAppUISmoke`: passed, `1` XCUITest.
- Debug and Release simulator builds passed with no warnings.
- Screenshot: `docs/release-readiness/native-screenshots/iphone-home-tabs-2026-06-21.jpg`.

## Remaining Differences

- Physical microphone quality and acoustic click bleed require real iPhone/iPad brass-device validation.
- Live cloud sync and provider sign-in require owner-approved Supabase/Google/Apple credentials.
- Visual tuning can continue after real tester screenshots from iPhone/iPad hardware.
