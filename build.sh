#!/bin/zsh
# Builds "Lark Screenshot.app"; --install copies it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="build/Lark Screenshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LarkScreenshot "$APP/Contents/MacOS/LarkScreenshot"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/LarkScreenshot.icns "$APP/Contents/Resources/LarkScreenshot.icns"
# A stable signing identity keeps the Screen Recording grant across rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
if [[ "${1:-}" == "--install" ]]; then
  pkill -x LarkScreenshot 2>/dev/null || true
  rm -rf "/Applications/Lark Screenshot.app"
  cp -R "$APP" "/Applications/Lark Screenshot.app"
  open "/Applications/Lark Screenshot.app"
fi
