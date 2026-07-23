# Native Swift Parity Surfaces

Updated: 2026-07-23

## Scope

This document describes the integrated SwiftUI source under `swift/BrassTuneApp`. It does not certify web production state, provider configuration, a signed Apple build, or App Store readiness.

## Current Native Product Surface

The app has five focused tabs with one primary home for each workflow. **Tuner is the default tab.**

- **Tuner** is the default live chromatic tuner. Its shipping UI has no source picker or Sample option. It begins with "Play a note" / "Listening..." and reports flat, in tune, or sharp with a single tuning meter. The first tap of **Start listening** requests microphone access; denied permission produces an **Open iOS Settings** recovery action.
- **Play-Along** is the flagship exercise surface. A musician chooses from `12` major scales, `12` natural-minor scales, and `3` other exercises, starts the microphone inline, and holds each highlighted note steady. The shared scorer contract treats ±5 cents as centered and ±15 cents as accepted, requires a 2-second hold with confidence/sample/dropout safeguards, and counts only centered notes toward the in-tune percentage and stars. A completed live exercise can save a real-microphone practice session.
- **Progress** replaces the duplicate Analytics, Coach, Progress, and session-summary surfaces. It shows a friendly zero state or local tuning metrics, a single practice suggestion, recent recordings, and a link to the complete practice history.
- **Class** is the top-level teacher-managed membership surface. It presents class selection, join, switch, leave, and refresh flows for authenticated users.
- **Settings** owns instrument choice, advanced A4 reference pitch, metronome defaults and the full metronome, the sheet-music library, local export/deletion, account state, and the single Privacy/Terms/Support entry points.

Home-as-launcher, the More bento grid, standalone Analytics and Coach tabs, Audio Lab, `NativeToolShell`, duplicate legal tiles, and the demo Ensemble dead end are not shipping navigation surfaces.

## Local-first Practice And Language Scope

- The eight local-first practice features are custom Play-Along exercises, guided warm-up, metronome presets, weekly goals, weak-transition drills, short reflections, drone/interval practice, and offline practice packs.
- The native String Catalog supports 12 production locales: `en`, `es`, `zh-Hans`, `zh-Hant`, `ar`, `fr`, `de`, `ru`, `pt-BR`, `ja`, `ko`, and `vi`. `System Default` is a preference rather than an additional locale. In-context linguistic and RTL review remains a human release gate.

## Authenticated Class Membership

- The Class tab presents every class returned for the signed-in user instead of collapsing membership to one class. A musician can select or switch classes, open **Join another class**, and refresh the membership list after joining.
- Join codes are normalized before the authenticated API request. Leaving calls the self-scoped membership endpoint for the selected class and refreshes the authoritative list after success.
- The UI uses explicit backend `viewer_role`, `viewer_can_leave`, and `viewer_can_manage` capabilities. It does not infer authorization from join-code visibility. Owners are not offered self-leave when the backend reports that they cannot leave.
- Class loading is generation-aware so an older in-flight response cannot replace a newer post-join result. Validation details remain user-visible, while view-lifecycle cancellation is not presented as a network failure.
- These surfaces require configured native authentication and API access. Guest-mode source behavior does not validate a live Supabase or provider lifecycle.

## Real-Microphone and Fixture Boundary

- Shipping recording defaults to `PracticeSessionSource.live`, and the shipping source list contains only the real microphone.
- Play-Along and Tuner both use `NativeAudioEngine` live pitch frames. The app does not synthesize practice results when launched normally.
- Deterministic pitch recordings, Play-Along frames, sample score import, and demo ensemble data are available only when the test process launches with `UITEST_FIXTURES` or the legacy `UITEST_DEMO` flag.
- Fixture entry points are guarded in the model and audio engine. Normal-state restoration filters legacy sample sessions and sample scores so fabricated historical data cannot reappear in the shipping UI.
- The metronome defaults to audible output (`muted: false`, `visualOnly: false`, volume `0.6`). Persisted user defaults remain intact; output is muted only while a real live-microphone recording is active.

## Beginner-First Interaction and Copy

- Onboarding asks only for an instrument and a **Start** action. A4/reference pitch lives behind **Advanced tuner settings**.
- User-facing copy describes what to do and avoids detector, validation, provider, OMR, frame, and click-bleed narration.
- Destructive data/account actions use standard destructive alerts with Cancel/Delete choices instead of typed confirmation phrases.
- Score import is described as local Files or Photos work. The score library supports PDF and image viewing, page controls, annotations, export, and local deletion without claiming optical music recognition.

## Adaptive Design and Liquid Glass Scope

- The app respects system light/dark appearance; no view forces dark mode.
- Content cards, tuner readouts, score pages, charts, forms, and notation use quiet adaptive system surfaces with a subtle border and minimal shadow. They are not glass.
- One centralized `.brassGlass(...)` modifier gates custom glass behind `if #available(iOS 26.0, *)` and falls back to `.ultraThinMaterial` plus shape/border treatment on iOS 17-25.
- One `BrassGlassButtonStyle` wrapper maps primary floating actions to `.glassProminent` on iOS 26 and bordered system styles on older iOS. The deployment target remains iOS 17.
- Custom glass is limited to floating Play-Along and Tuner transport controls, primary Start/Record actions, and score-viewer top controls. `TabView` and `NavigationStack` retain system chrome so iOS 26 can apply its automatic treatment.
- The live tuner readout, tuning meter, continuously changing pitch content, score pages, progress metrics, cards, and Settings forms never receive custom glass.

## Current Validation Boundary

The current local candidate has coverage for the five-tab information architecture, onboarding, fixture isolation, audible metronome defaults, the `27`-exercise grouped Play-Along catalog, the shared scorer contract, eight practice features, 12 production locales, class capability/API/race handling, destructive alerts, persistence, and audio behavior.

Current local evidence is BrassTuneCore `3/3`, native app units `99/99`, UI smoke `8/8`, and passing Debug and Release iPhone/iPad simulator builds plus launch-frame checks. Localization validation covered `556` source keys, `562` String Catalog entries, `159` sentinels, and `1,511` locale assertions with zero violations. Preserve the exact revision with this evidence after the final commit before treating it as a release candidate.

When an unrestricted macOS/Xcode environment is available, run:

- `python3 swift/BrassTuneApp/scripts/verify_design_tokens.py`
- `xcrun simctl list devices available`
- `cd swift/BrassTuneCore && swift test`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Debug -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -configuration Release -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneApp -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppTests`
- `xcodebuild test -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke -destination "id=<dynamic-simulator-id>" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:BrassTuneAppUITests`

Always discover an available simulator dynamically instead of hard-coding a device name.

## Explicit Non-Claims

- Native evidence is local and unsigned; it does not validate the final pushed/deployed SHA.
- Static localization coverage does not validate translation quality, typography, truncation, or RTL behavior; in-context human review remains required.
- No physical-device microphone, brass-room acoustic, interruption/route, haptic, metronome timing, speaker/headphone bleed, Files, or Photos validation is claimed.
- No signed archive, Apple Developer signing, App Store Connect upload, TestFlight run, App Review, or App Store readiness is claimed.
- Camera score capture remains absent; no camera capability or validation is implied.
- Native account/provider lifecycle behavior remains external and unverified until production configuration and authorized disposable accounts are available.
