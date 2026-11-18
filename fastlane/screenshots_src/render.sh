#!/usr/bin/env bash
# Renders the App Store screenshots from index.html with headless Google Chrome:
#   iPhone 6.9" (1320x2868) → fastlane/screenshots/<locale>/iPhone_6.9_<n>.png
#   iPhone 6.5" (1284x2778) → fastlane/screenshots/<locale>/iPhone_6.5_<n>.png
#   iPad 13"    (2064x2752) → fastlane/screenshots/<locale>/iPad_13_<n>.png
#
# Usage: fastlane/screenshots_src/render.sh [variant] [devices]
#        variant: A | B | C (default B)
#        devices: "iphone iphone65 ipad" (default), or any subset
set -euo pipefail

VARIANT="${1:-B}"
DEVICES="${2:-iphone iphone65 ipad}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/fastlane/screenshots"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8799

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1

for device in $DEVICES; do
  case "$device" in
    iphone) size="1320,2868"; prefix="iPhone_6.9" ;;
    iphone65) size="1284,2778"; prefix="iPhone_6.5" ;;
    ipad)   size="2064,2752"; prefix="iPad_13" ;;
    *) echo "unknown device: $device" >&2; exit 1 ;;
  esac
  for pair in "en:en-US" "pt:pt-BR"; do
    lang="${pair%%:*}"; locale="${pair##*:}"
    mkdir -p "$OUT/$locale"
    for n in 1 2 3 4 5 6 7 8; do
      "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
        --window-size="$size" --virtual-time-budget=3000 \
        --screenshot="$OUT/$locale/${prefix}_$n.png" \
        "http://127.0.0.1:$PORT/fastlane/screenshots_src/index.html?render=1&variant=$VARIANT&frame=$n&lang=$lang&device=$device" \
        >/dev/null 2>&1
      echo "$locale/${prefix}_$n.png"
    done
  done
done
