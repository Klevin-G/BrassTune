# Native Swift Parity Surfaces

Updated: 2026-07-10

## Scope

This document describes the current local SwiftUI redesign under `swift/BrassTuneApp`. It does not certify web production state, provider configuration, a signed Apple build, or App Store readiness.

## Current Native Product Surface

The app now has four focused tabs with one primary home for each workflow:

- **Play-Along** is the default tab and flagship action. A musician chooses one of six written-note exercises, starts the microphone inline, and holds each highlighted note steady. The grader uses the existing native pitch stream, matches written pitch class across octave and enharmonic spelling, collects a sustained hold, and reports per-note cents, a plain-language rating, an overall percentage, and stars. A completed live exercise can save a real-microphone practice session.
- **Tuner** is the live chromatic tuner. Its shipping UI has no source picker or Sample option. It begins with “Play a note” / “Listening…” and reports flat, in tune, or sharp with a single tuning meter. The first tap of **Start listening** requests microphone access; a denied permission produces an **Open iOS Settings** recovery action.
- **Progress** replaces the duplicate Analytics, Coach, Progress, and session-summary surfaces. It shows a friendly zero state or local tuning metrics, a single practice suggestion, recent recordings, and a link to the complete practice history.
- **Settings** owns instrument choice, advanced A4 reference pitch, metronome defaults and the full metronome, the sheet-music library, local export/deletion, account state, and the single Privacy/Terms/Support entry points.

Home-as-launcher, the More bento grid, the standalone Analytics and Coach tabs, Audio Lab, `NativeToolShell`, duplicate legal tiles, and the demo Ensemble dead end are no longer shipping navigation surfaces.

## Real-Microphone and Fixture Boundary

- Shipping recording defaults to `PracticeSessionSource.live`, and the shipping source list contains only the real microphone.
- Play-Along and Tuner both use `NativeAudioEngine` live pitch frames. The app does not synthesize practice results when launched normally.
- Deterministic pitch recordings, Play-Along frames, sample score import, and demo ensemble data are available only when the test process launches with `UITEST_FIXTURES` or the legacy `UITEST_DEMO` flag.
- Fixture entry points are guarded in the model and audio engine. Normal-state restoration also filters legacy sample sessions and sample scores so fabricated historical data cannot reappear in the shipping UI.
- The metronome defaults to audible output (`muted: false`, `visualOnly: false`, volume `0.6`). Its persisted user defaults remain intact; output is muted only while a real live-microphone recording is active.

## Beginner-First Interaction and Copy

- Onboarding asks only for an instrument and a **Start** action. A4/reference pitch lives behind **Advanced tuner settings**.
- User-facing copy describes what to do and avoids detector, validation, provider, OMR, frame, and click-bleed narration.
- Destructive data/account actions use standard destructive alerts with Cancel/Delete choices instead of typed confirmation phrases.
- Score import is described as local Files or Photos work. The score library supports PDF and image viewing, page controls, annotations, export, and local deletion without claiming optical music recognition.

## Adaptive Design and Liquid Glass Scope

- The app respects the system light/dark appearance; no view forces dark mode.
- Content cards, tuner readouts, score pages, charts, forms, and notation use quiet adaptive system surfaces with a subtle border and minimal shadow. They are not glass.
- One centralized `.brassGlass(...)` modifier gates custom glass behind `if #available(iOS 26.0, *)` and falls back to `.ultraThinMaterial` plus shape/border treatment on iOS 17–25.
- One `BrassGlassButtonStyle` wrapper maps primary floating actions to `.glassProminent` on iOS 26 and bordered system styles on older iOS. The deployment target remains iOS 17.
- Custom glass is limited to the floating Play-Along and Tuner transport controls, primary Start/Record actions, and the score full-page viewer top controls. `TabView` and `NavigationStack` retain system chrome so iOS 26 can apply its automatic treatment.
- The live tuner readout, tuning meter, continuously changing pitch content, score pages, progress metrics, cards, and Settings forms never receive custom glass.

## Current Validation Boundary

The current redesign has the following local evidence:

- `cd swift/BrassTuneCore && swift test`: passed, `3/3` tests.
- Native app test source contains `35` app unit tests and `2` UI tests covering the four-tab IA, onboarding, fixture isolation, audible metronome defaults, Play-Along grading, destructive alerts, and existing persistence/audio behavior.
- The app and test sources were source/typecheck-validated, but the `35` app tests and `2` UI tests were **not executed** in this environment. `xcodebuild`/CoreSimulator access is blocked by the sandbox, so no current simulator test or build pass is claimed.

When an unrestricted macOS/Xcode environment is available, run:

- `python3 swift/BrassTuneApp/scripts/verify_design_tokens.py`
- `xcrun simctl list devices available`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests`

Always discover an available simulator dynamically instead of hard-coding a device name.

## Explicit Non-Claims

- The current redesign has not completed simulator test execution in this environment.
- No physical-device microphone, brass-room acoustic, interruption/route, haptic, metronome timing, speaker/headphone bleed, Files, or Photos validation is claimed.
- No signed archive, Apple Developer signing, App Store Connect upload, TestFlight run, App Review, or App Store readiness is claimed.
- Camera score capture remains absent; no camera capability or validation is implied.
- Native account/provider lifecycle behavior remains external and unverified until production configuration and authorized disposable accounts are available.
