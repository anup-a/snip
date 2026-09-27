#!/bin/zsh
# Builds Snip.app and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/Snip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Snip "$APP/Contents/MacOS/Snip"
cp Info.plist "$APP/Contents/Info.plist"
# A stable signing identity keeps the Screen Recording grant across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Snip 2>/dev/null || true
  rm -rf /Applications/Snip.app
  cp -R "$APP" /Applications/Snip.app
  open /Applications/Snip.app
fi
