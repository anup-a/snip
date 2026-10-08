#!/bin/zsh
# Re-renders the README illustrations and the motion demo into Marketing/readme/assets.
#   Marketing/readme/render.sh          illustrations (hero, scroll, record, agent)
#   Marketing/readme/render.sh motion   also the demo video (demo.mp4) and its README GIF (needs ffmpeg)
#   Marketing/readme/render.sh raw      first re-render the overlay states in raw/ (needs .build/release/Snip)
# Playwright is installed into a temp dir (not the repo) and drives the local Google Chrome.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export SNIP_PW_DIR="${SNIP_PW_DIR:-${TMPDIR:-/tmp}/snip-pw}"
if [[ ! -d "$SNIP_PW_DIR/node_modules/playwright" ]]; then
  mkdir -p "$SNIP_PW_DIR"
  (cd "$SNIP_PW_DIR" && npm init -y >/dev/null && npm i playwright >/dev/null)
fi
if [[ "${1:-}" == "raw" ]]; then
  BIN="$HERE/../../.build/release/Snip"
  [[ -x "$BIN" ]] || { echo "run swift build -c release --product Snip first" >&2; exit 1; }
  mkdir -p "$HERE/raw"
  for s in hover select annotate; do
    SNIP_DEMO_IMAGE="$HERE/../html/scenes/dash.png" SNIP_DEMO_WINDOWS="110,70,1080,720" "$BIN" --render-demo $s "$HERE/raw/dash-$s.png"
  done
fi
node "$HERE/render.mjs"
if [[ "${1:-}" == "motion" ]]; then
  node "$HERE/motion.mjs"
fi
