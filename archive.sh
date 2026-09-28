#!/bin/zsh
# Builds a sandboxed, hardened Snip.app signed for the Mac App Store.
# Does not replace /Applications/Snip.app. Pass --install to do that.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/Snip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Snip "$APP/Contents/MacOS/Snip"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/Snip.icns "$APP/Contents/Resources/Snip.icns"
cp Resources/Snip_Mac_App_Store.provisionprofile "$APP/Contents/embedded.provisionprofile"
IDENTITY="Apple Distribution: Anup Aglawe (384UFAG6NB)"
codesign --force --options runtime --timestamp --entitlements Snip.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Snip 2>/dev/null || true
  rm -rf "/Applications/Snip.app"
  cp -R "$APP" "/Applications/Snip.app"
  open "/Applications/Snip.app"
fi
