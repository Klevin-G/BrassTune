# TestFlight upload — signed archive + export handoff

This script prepares a signed archive only when owner-owned Apple signing and the
required public production configuration are supplied. It does not create a
signed archive or upload a build by itself in this repository state. The Apple
entitlement and native third-party OAuth controls are intentionally deferred.

## One-time setup (owner)

1. Join the **Apple Developer Program** ($99/yr) if you haven't.
2. In **Xcode → Settings → Accounts**, add your Apple ID (so automatic signing can
   create certificates/profiles), or create an **App Store Connect API key**
   (App Store Connect → Users and Access → Integrations → Keys) for CLI signing/upload.
3. In **App Store Connect**, create the app record (New App) using a bundle id you
   own, then pass that registered identifier via `BRASSTUNE_BUNDLE_ID`.
4. Note your **Team ID** (Apple Developer → Membership).

## Build + export the .ipa

```bash
APPLE_TEAM_ID=YOURTEAMID \
BRASSTUNE_BUNDLE_ID=com.yourorg.BrassTune \
BRASSTUNE_SUPABASE_URL=https://<20-character-project-ref>.supabase.co \
BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=<complete-public-publishable-key> \
scripts/ios/build-testflight.sh
```

This validates the public runtime configuration, archives Release with automatic
signing and `CODE_SIGNING_ALLOWED=YES`, then exports
`build/ios/export/BrassTuneApp.ipa`. It does not enable Sign in with Apple.

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
- See `APP_STORE_CHECKLIST.md` for the full store-metadata checklist.
