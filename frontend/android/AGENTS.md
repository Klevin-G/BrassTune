# BrassTune Android

Project attribution: Kelvin Guo, Arya Salem.

This is the Capacitor 8 Android shell for the React/Vite application in
`frontend/src`. It packages local assets; never configure a production
`server.url` pointing at the hosted website. Shared web behavior must remain
intact when adding native behavior.

## Ownership and commands

- Native shell: this directory; shared native bridge: `../src/platform`.
- Build and dependencies: `../package.json`, lockfile, `../capacitor.config.ts`.
- Generated bundled assets under `app/src/main/assets/public` must not be edited.
- Use Node 24, OpenJDK 21, and SDK/API 36. Gradle 8.14.3 is not compatible with
  Android Studio's Java 25 runtime; select Java 21 in the IDE and shell.
- From `frontend`: `npm test`, `npm run build`, `npm run android:sync`.
- From this directory: `./gradlew :app:assembleDebug :app:lintDebug`,
  `./gradlew :app:testDebugUnitTest`, and `./gradlew :app:connectedDebugAndroidTest`
  with a discovered running device. Keep native unit and instrumentation counts
  separate; a successful NO-SOURCE task is not test execution.
- Release artifacts: `./gradlew :app:assembleRelease :app:bundleRelease`.
  Unsigned output is not a publishable or released app.

## Product and release boundaries

- Default Android builds support local guest practice. Account/cloud features
  and Google OAuth remain gated until exact origins, public API/WS endpoints,
  external-browser PKCE return, and deployed provider configuration are verified.
- Never weaken backend CORS/WebSocket checks or add wildcard auth redirects to
  make the native app connect. Never bundle service-role keys or signing secrets.
- Explicit microphone/camera actions require Android runtime permissions. Stop
  capture and finalize active takes on native backgrounding; foreground may
  resume passive listening only according to prior intent, never saved recording.
- Validate microphone denial/retry, background finalization, offline startup,
  local saved sessions, navigation and localization on the packaged app.
- Emulator evidence cannot establish physical pitch accuracy, timing, Bluetooth,
  microphone quality, thermal behavior or audio focus/interruption reliability.
- Keep SDKs, Gradle caches, APK/AABs, captures, recordings, keys and keystores out
  of Git. Store private release receipts outside the checkout.
- Play account identity, terms, signing, testing-track eligibility, listing and
  app-content forms are separate release gates. Do not claim publication without
  a verified Play Console receipt and appropriate availability evidence.

Use one Android writer and an independent reviewer/tester, with disjoint test
file ownership. Coordinate Gradle/emulator use. Depth remains one; do not spawn
grandchildren. See `../docs/android.md` and `../docs/ANDROID_CODEX_SETUP.md`.
