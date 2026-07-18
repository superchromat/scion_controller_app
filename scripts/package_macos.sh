#!/usr/bin/env bash
#
# Build → Developer ID sign → notarize → staple the macOS app for beta testers.
# Output: build/scion-macos.zip (double-click-clean on any Mac).
#
# ---------------------------------------------------------------------------
# ONE-TIME SETUP
#
#   1. Developer ID Application cert + private key in the login keychain.
#      (Verify: `security find-identity -v -p codesigning` shows it.)
#      If the cert is present but "0 valid identities", the G2 intermediate is
#      missing — install it:
#        curl -fsSLO https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
#        security add-certificates DeveloperIDG2CA.cer
#
#   2. Store notary credentials as a keychain profile (needs an app-specific
#      password from appleid.apple.com → Sign-In & Security → App-Specific Passwords):
#        xcrun notarytool store-credentials scion-notary \
#          --apple-id "YOU@example.com" --team-id DJ7F26GRG8 --password "xxxx-xxxx-xxxx-xxxx"
#
#   3. (Optional, avoids a codesign GUI prompt per run) authorize the key for
#      command-line tools — enter your macOS login password when asked:
#        security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
#          -k "$(read -rsp 'login password: ' p; echo "$p")" ~/Library/Keychains/login.keychain-db
# ---------------------------------------------------------------------------
set -euo pipefail

APP_NAME="scion"
IDENTITY="Developer ID Application: Superchromat Pty. Ltd. (DJ7F26GRG8)"
NOTARY_PROFILE="scion-notary"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENT="macos/Runner/Release.entitlements"
APP="build/macos/Build/Products/Release/${APP_NAME}.app"
ZIP="build/${APP_NAME}-macos.zip"

echo "==> Building release"
flutter build macos --release

# Sign inside-out: nested dylibs and frameworks first, then the app bundle.
# Hardened runtime (--options runtime) and a secure timestamp are required for
# notarization.
echo "==> Signing nested code"
while IFS= read -r -d '' f; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f"
done < <(find "$APP/Contents/Frameworks" -type f -name "*.dylib" -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$f"
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 2>/dev/null)

echo "==> Signing app bundle"
codesign --force --options runtime --timestamp \
  --entitlements "$ENT" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Zipping for notarization"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Notarizing (a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the ticket to the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Repackaging the stapled app"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper assessment"
spctl -a -vvv --type execute "$APP" || true

echo "==> Done: $ZIP"
