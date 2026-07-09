# TestFlight upload — one-command archive + export

The app is archive-ready. Verified locally: Release build archives cleanly for
`generic/platform=iOS` (unsigned), the Sign in with Apple entitlement is in the
target, the app icon and privacy manifest are present, and the mic/photo usage
strings are set. Signing + upload need your Apple Developer account.

## One-time setup (owner)

1. Join the **Apple Developer Program** ($99/yr) if you haven't.
2. In **Xcode → Settings → Accounts**, add your Apple ID (so automatic signing can
   create certificates/profiles), or create an **App Store Connect API key**
   (App Store Connect → Users and Access → Integrations → Keys) for CLI signing/upload.
3. In **App Store Connect**, create the app record (New App) using a bundle id you
   own, e.g. `com.brasstune.BrassTuneApp` (default) — or pick your own and pass it
   via `BRASSTUNE_BUNDLE_ID`.
4. Note your **Team ID** (Apple Developer → Membership).

## Build + export the .ipa

```bash
APPLE_TEAM_ID=YOURTEAMID scripts/ios/build-testflight.sh
# or a custom bundle id:
APPLE_TEAM_ID=YOURTEAMID BRASSTUNE_BUNDLE_ID=com.yourorg.BrassTune scripts/ios/build-testflight.sh
```

This archives Release with automatic signing (`-allowProvisioningUpdates` registers
the App ID + Sign in with Apple capability + a distribution profile on first run),
then exports `build/ios/export/BrassTuneApp.ipa`.

## Upload to TestFlight (pick one)

- **Transporter.app** (free, Mac App Store): open it, drag in `BrassTuneApp.ipa`, Deliver.
- **CLI** with an App Store Connect API key:
  ```bash
  xcrun altool --upload-app --type ios \
    -f build/ios/export/BrassTuneApp.ipa \
    --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
  ```

Then in App Store Connect → your app → **TestFlight**, add internal testers. Processing
takes a few minutes; the first external build needs a short Beta App Review.

## Current app metadata (change as desired)
- Marketing version: `0.1.0`, build: `1` (bump `CURRENT_PROJECT_VERSION` per upload,
  or the export sets `manageAppVersionAndBuildNumber`).
- Display name: **BrassTune**. Deployment target: iOS 17. Devices: iPhone + iPad.
- App icon: brass tuning-fork placeholder — replace `AppIcon-1024.png` with final art.
- See `APP_STORE_CHECKLIST.md` for the full store-metadata checklist.
