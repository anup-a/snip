#!/bin/zsh
# Renders the four overlay states used under the App Store captions.
# Scenes are 1440×900 points at 2× (2880×1800 PNG). Window rects are top-left points.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=".build/release/Snip"
[[ -x "$BIN" ]] || { echo "run ./build.sh first" >&2; exit 1; }
OUT="${1:-Marketing/raw}"
mkdir -p "$OUT"

render() {
  SNIP_DEMO_IMAGE="$1" SNIP_DEMO_WINDOWS="$2" "$BIN" --render-demo "$3" "$OUT/$4"
}

render Marketing/scenes/dash.png "110,70,1080,720" hover "dash-hover.png"
render Marketing/scenes/dash.png "110,70,1080,720" annotate "dash-annotate.png"
render Marketing/scenes/dash.png "110,70,1080,720" pin "dash-pin.png"
render Marketing/scenes/chat.png "150,80,1000,690" mosaic "chat-mosaic.png"
echo "wrote $OUT"
