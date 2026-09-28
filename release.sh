#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Snip for GitHub releases.
# Signs with Developer ID, notarizes, and staples when a Developer ID identity is installed.
# Writes build/release/Snip-<version>.dmg and .zip.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
OUT="build/release"; APP="$OUT/Snip.app"
swift build -c release --arch arm64 --arch x86_64
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Snip
cp "$BIN" "$APP/Contents/MacOS/Snip"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Snip.icns "$APP/Contents/Resources/Snip.icns"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --entitlements Release.entitlements --sign "$IDENTITY" "$APP"
else
  echo "warning: no Developer ID Application identity, ad-hoc signing (Gatekeeper will warn)" >&2
  codesign --force --options runtime --entitlements Release.entitlements --sign - "$APP"
fi
codesign --verify --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Snip"

DMG="$OUT/Snip-$VERSION.dmg"; ZIP="$OUT/Snip-$VERSION.zip"
STAGE="$OUT/dmg"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Snip" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  KEY_ID=${ASC_KEY_ID:-3U5Y5B8R9V}; ISSUER=${ASC_ISSUER_ID:-18b76006-72f8-4068-b993-124ac62ce778}
  xcrun notarytool submit "$DMG" --key ~/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8 --key-id "$KEY_ID" --issuer "$ISSUER" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$DMG" "$ZIP"
