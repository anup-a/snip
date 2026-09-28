#!/bin/zsh
# Re-renders the v2 App Store screenshots into Marketing/appstore-v2 (2880x1800 each + contact-sheet.png).
#   Marketing/html/render.sh          screenshots + contact sheet
#   Marketing/html/render.sh raw      also re-render the v2 demo scenes and the raw overlay states
#                                     (needs .build/release/Snip, from ./build.sh)
# Playwright is installed into a temp dir (not the repo) and drives the local Google Chrome.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export SNIP_PW_DIR="${SNIP_PW_DIR:-${TMPDIR:-/tmp}/snip-pw}"
if [[ ! -d "$SNIP_PW_DIR/node_modules/playwright" ]]; then
  mkdir -p "$SNIP_PW_DIR"
  (cd "$SNIP_PW_DIR" && npm init -y >/dev/null && npm i playwright >/dev/null)
fi

if [[ "${1:-}" == "raw" ]]; then
  node "$HERE/render.mjs" scenes
  BIN="$ROOT/.build/release/Snip"
  [[ -x "$BIN" ]] || { echo "run ./build.sh first" >&2; exit 1; }
  r() { SNIP_DEMO_IMAGE="$HERE/scenes/$1.png" SNIP_DEMO_WINDOWS="$2" "$BIN" --render-demo "$3" "$HERE/raw/$4"; }
  mkdir -p "$HERE/raw"
  r dash "110,70,1080,720" hover dash-hover.png
  r dash "110,70,1080,720" annotate dash-annotate.png
  r dash "110,70,1080,720" pin dash-pin.png
  r chat "150,80,1000,690" mosaic chat-mosaic.png
fi

node "$HERE/render.mjs" shots
for f in "$ROOT"/Marketing/appstore-v2/[0-9]-*.png; do
  sips -g pixelWidth -g pixelHeight "$f" | awk 'NR>1{printf "%s ", $2} END{print ""}' | sed "s|^|$(basename "$f"): |"
done
