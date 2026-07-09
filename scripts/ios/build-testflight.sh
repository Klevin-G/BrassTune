#!/usr/bin/env bash
# Archive BrassTune for TestFlight / App Store and export a signed .ipa.
#
# Prereqs (one-time, owner):
#   - Paid Apple Developer Program membership.
#   - Signed into the Apple ID in Xcode (Settings → Accounts) OR an App Store
#     Connect API key for non-interactive signing.
#   - APPLE_TEAM_ID set to your 10-char Team ID (Apple Developer → Membership).
#   - The App ID / bundle id registered in App Store Connect with the
#     "Sign in with Apple" capability enabled (automatic signing + the flag below
#     will register/update it for you on first run).
#
# Usage:
#   APPLE_TEAM_ID=ABCDE12345 scripts/ios/build-testflight.sh
#   APPLE_TEAM_ID=ABCDE12345 BRASSTUNE_BUNDLE_ID=com.yourorg.BrassTune scripts/ios/build-testflight.sh
#
set -euo pipefail

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer Team ID}"
BUNDLE_ID="${BRASSTUNE_BUNDLE_ID:-com.brasstune.BrassTuneApp}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$REPO_ROOT/swift/BrassTuneApp/BrassTuneApp.xcodeproj"
SCHEME="BrassTuneApp"
OUT="$REPO_ROOT/build/ios"
ARCHIVE="$OUT/BrassTuneApp.xcarchive"
mkdir -p "$OUT"

echo "==> Archiving $SCHEME (Release) for team $APPLE_TEAM_ID, bundle $BUNDLE_ID"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

echo "==> Writing ExportOptions.plist"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${APPLE_TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict>
</plist>
EOF

echo "==> Exporting .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates

echo ""
echo "Done. IPA: $OUT/export/BrassTuneApp.ipa"
echo ""
echo "Upload to TestFlight (pick one):"
echo "  A) Transporter.app (Mac App Store) — drag in the .ipa, Deliver."
echo "  B) CLI with an App Store Connect API key:"
echo "     xcrun altool --upload-app --type ios -f \"$OUT/export/BrassTuneApp.ipa\" \\"
echo "       --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
