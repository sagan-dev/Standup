#!/bin/bash
#
# Builds, signs (Developer ID), notarizes and publishes a Standup release.
#
# One-time setup:
#   1. Install a "Developer ID Application" certificate (with its private key) in your login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. Store notarization credentials once:
#        xcrun notarytool store-credentials "Standup-notary" \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Usage:
#   TEAM_ID=ABCDE12345 scripts/release.sh          # build, notarize, create the GitHub release
#   TEAM_ID=ABCDE12345 scripts/release.sh --no-publish   # stop after producing the notarized zip
#
set -euo pipefail

cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to the Apple Developer team that owns your Developer ID certificate}"
NOTARY_PROFILE="${NOTARY_PROFILE:-Standup-notary}"
PUBLISH=1
[ "${1:-}" = "--no-publish" ] && PUBLISH=0

PROJECT="Standup.xcodeproj"
SCHEME="Standup"
APP_NAME="Standup.app"
VERSION=$(grep -m1 "MARKETING_VERSION" "$PROJECT/project.pbxproj" | sed -E 's/.*= ([0-9.]+);/\1/')
TAG="v$VERSION"
BUILD_DIR="build/release"
ZIP="$BUILD_DIR/Standup-$VERSION.zip"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application.*($TEAM_ID)"; then
  echo "No 'Developer ID Application' identity for team $TEAM_ID found in the keychain." >&2
  exit 1
fi

if [ "$PUBLISH" = 1 ] && [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is not clean; commit or stash first." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving $VERSION"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$BUILD_DIR/Standup.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -quiet

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

echo "==> Exporting with Developer ID signature"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/Standup.xcarchive" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" \
  -quiet

APP="$BUILD_DIR/export/$APP_NAME"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/notarize.zip"
xcrun notarytool submit "$BUILD_DIR/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "==> Ready: $ZIP"

if [ "$PUBLISH" = 1 ]; then
  NOTES=$(awk -v v="$VERSION" '
    $0 ~ "^## \\[" { if (found) exit } 
    $0 ~ "^## \\[(Unreleased|" v ")" { found=1; next }
    found { print }' CHANGELOG.md)
  echo "==> Publishing $TAG"
  gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
    --title "Standup $VERSION" \
    --notes "$NOTES"
fi
