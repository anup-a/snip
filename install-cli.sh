#!/bin/zsh
# Builds the `snip` command-line tool and installs it to ~/.local/bin (or $1).
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-$HOME/.local/bin}"
swift build -c release --product SnipCLI
mkdir -p "$DEST"
cp .build/release/SnipCLI "$DEST/snip"
codesign --force --sign - "$DEST/snip" 2>/dev/null || true
echo "Installed $DEST/snip"
case ":$PATH:" in *":$DEST:"*) ;; *) echo "Add $DEST to your PATH to run snip." ;; esac
