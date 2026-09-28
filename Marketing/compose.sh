#!/bin/zsh
# Frames the raw overlay renders as 2880×1800 App Store screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -O -framework AppKit -o /tmp/snip-compose Marketing/compose.swift
/tmp/snip-compose "${1:-Marketing/raw}" "${2:-Marketing/appstore}"
