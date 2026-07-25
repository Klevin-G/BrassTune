#!/usr/bin/env bash
# Archive BrassTune for TestFlight / App Store and export a signed .ipa.
#
# Prereqs (one-time, owner):
#   - Paid Apple Developer Program membership.
#   - Signed into the Apple ID in Xcode (Settings → Accounts) OR an App Store
#     Connect API key for non-interactive signing.
#   - APPLE_TEAM_ID set to your 10-char Team ID (Apple Developer → Membership).
#   - BRASSTUNE_BUNDLE_ID registered in App Store Connect.
#   - BRASSTUNE_SUPABASE_URL and BRASSTUNE_SUPABASE_PUBLISHABLE_KEY set to the
#     public production values. The script rejects missing, placeholder, or
#     secret values before invoking Xcode.
#
# Usage:
#   APPLE_TEAM_ID=ABCDE12345 BRASSTUNE_BUNDLE_ID=com.yourorg.BrassTune \
#     BRASSTUNE_SUPABASE_URL=https://<20-character-project-ref>.supabase.co \
#     BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=<complete-public-publishable-key> \
#     scripts/ios/build-testflight.sh
#
set -euo pipefail

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer Team ID}"
: "${BRASSTUNE_BUNDLE_ID:?Set BRASSTUNE_BUNDLE_ID to the registered App Store bundle ID}"
: "${BRASSTUNE_SUPABASE_URL:?Set BRASSTUNE_SUPABASE_URL to the public production URL}"
: "${BRASSTUNE_SUPABASE_PUBLISHABLE_KEY:?Set BRASSTUNE_SUPABASE_PUBLISHABLE_KEY to the public production key}"
BUNDLE_ID="$BRASSTUNE_BUNDLE_ID"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$REPO_ROOT/swift/BrassTuneApp/BrassTuneApp.xcodeproj"
SCHEME="BrassTuneApp"
OUT="$REPO_ROOT/build/ios"
ARCHIVE="$OUT/BrassTuneApp.xcarchive"
mkdir -p "$OUT"

case "$APPLE_TEAM_ID" in
  ??????????) ;;
  *) echo "APPLE_TEAM_ID must be exactly 10 alphanumeric characters." >&2; exit 1 ;;
esac
case "$APPLE_TEAM_ID" in
  *[!A-Za-z0-9]*) echo "APPLE_TEAM_ID must contain only letters and numbers." >&2; exit 1 ;;
esac
case "$BUNDLE_ID" in
  *.*) ;;
  *) echo "BRASSTUNE_BUNDLE_ID must be a reverse-DNS bundle identifier." >&2; exit 1 ;;
esac

CONFIGURATION=Release ACTION=install BRASSTUNE_REQUIRE_ONLINE_AUTH=YES \
  BRASSTUNE_ENV=production BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
  BRASSTUNE_SUPABASE_URL="$BRASSTUNE_SUPABASE_URL" \
  BRASSTUNE_SUPABASE_PUBLISHABLE_KEY="$BRASSTUNE_SUPABASE_PUBLISHABLE_KEY" \
  /bin/sh "$REPO_ROOT/swift/BrassTuneApp/scripts/verify_release_auth_config.sh"

echo "==> Archiving $SCHEME (Release) for team $APPLE_TEAM_ID, bundle $BUNDLE_ID"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  BRASSTUNE_ENV=production \
  BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
  BRASSTUNE_SUPABASE_URL="$BRASSTUNE_SUPABASE_URL" \
  BRASSTUNE_SUPABASE_PUBLISHABLE_KEY="$BRASSTUNE_SUPABASE_PUBLISHABLE_KEY" \
  BRASSTUNE_REQUIRE_ONLINE_AUTH=YES \
  CODE_SIGNING_ALLOWED=YES \
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
