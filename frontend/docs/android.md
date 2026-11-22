# Android packaging

BrassTune's Android app is a Capacitor 8 wrapper around the locally built Vite
bundle. It never points at a remote `server.url`, so guest tools, local scores,
and the static app shell remain available offline after installation.

## Local commands

Use Node 24, OpenJDK 21, and an Android SDK installation. The generated Gradle
8.14.3 wrapper is validated here with OpenJDK 21; do not point it at the newer
Android Studio JBR until Android Gradle Plugin/wrapper compatibility has been
verified.

```sh
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
cd frontend
npm run android:build:debug
```

`android:sync` builds the Vite assets first and then copies `dist/` into the
native project. Do not edit `android/app/src/main/assets/public/` directly.

## Native boundaries

- `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, and `CAMERA` are declared in the
  Android manifest. Android still presents microphone and camera runtime
  prompts when tuner/recording or Score Practice camera capture calls
  `getUserMedia`; the existing UI keeps Photos/Files available after denial or
  cancellation.
- Android backgrounding dispatches the existing practice-audio pause event, so
  browser audio for tuner, metronome, and drone is stopped promptly.
- Service-worker registration is disabled only in the native WebView. Capacitor
  packages the static bundle, avoiding a second native cache/update authority.
- Google OAuth remains hidden in Android builds unless
  `VITE_ANDROID_ACCOUNT_API_ENABLED=true` and
  `VITE_ANDROID_OAUTH_ENABLED=true` are intentionally supplied at bundle build
  time *and* Supabase has the exact callback
  `com.brasstune.android://auth/callback` in its redirect allow-list. Apple
  OAuth is not offered on Android. No wildcard redirect is permitted.
- The deep-link bridge validates only callback scheme/host/path before it
  forwards the response to Supabase's PKCE handler. It does not claim an
  additional app-owned callback-state contract, so OAuth must remain gated
  until the complete external-browser return flow is tested on Android.
- Password reset links use the existing HTTPS web reset page while Android App
  Links are unverified; they never point email clients to Capacitor's internal
  `https://localhost` origin. People return to the app and sign in after reset.
- Account, cloud-session, analytics, and class views remain unavailable by
  default in Android. Enable them only after the packaged build has explicit
  `VITE_API_BASE_URL=https://…` and `VITE_WS_BASE_URL=wss://…` values and the
  deployed backend CORS **and** WebSocket policies allow the exact native
  origin `https://localhost`. The backend currently rejects deployed localhost
  origins, so this requires a separately reviewed backend policy design; do
  not add a wildcard or relax origin checks as an Android shortcut.

## Release gates

Before a production Android release, validate on physical hardware: microphone
permission, live pitch latency, worker fallback, metronome scheduling, drone
audio focus/route interruption, `MediaRecorder` MIME behavior, offline
relaunch/local storage, Google PKCE return when enabled, and account/class
lifecycles. The generated project contains no signing key, keystore, or Play
publishing credential; signing and Play Console submission are owner actions.
