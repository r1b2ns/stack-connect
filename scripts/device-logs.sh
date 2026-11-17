#!/usr/bin/env bash
#
# Streams StackConnect's unified log from an iPhone connected to this Mac
# (USB or the same network as a paired device), filtered to the app.
#
# By default it shows only the Rust core's diagnostic lines (categories
# `core.*`: HTTP requests, Google's errors, edits, users…). See docs/LOGGING.md.
#
# Usage:
#   scripts/device-logs.sh                 # core.* lines of StackConnect
#   scripts/device-logs.sh --all           # every StackConnect category (UI + core.*)
#   scripts/device-logs.sh --category 'core.googleplay*'
#   scripts/device-logs.sh --match developers --save /tmp/stack.log
#   scripts/device-logs.sh --device Anton  # pick a device by name when several are connected
#   scripts/device-logs.sh --udid <UDID>   # …or by UDID
#   scripts/device-logs.sh --no-debug      # hide debug lines (one per HTTP request)
#
# Requires pymobiledevice3:  brew install pipx && pipx install pymobiledevice3

set -euo pipefail

SUBSYSTEM="zeroSixteen.stackconnect"
PROCESS="StackConnect"

categories=()
all=false
udid=""
device=""
save=""
matches=()
extra=()

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)       all=true; shift ;;
        --category)  categories+=("$2"); shift 2 ;;
        --device)    device="$2"; shift 2 ;;
        --udid)      udid="$2"; shift 2 ;;
        --save)      save="$2"; shift 2 ;;
        --match)     matches+=("$2"); shift 2 ;;
        --no-debug)  extra+=("--no-debug"); shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if ! command -v pymobiledevice3 >/dev/null 2>&1; then
    cat >&2 <<'EOF'
pymobiledevice3 is not installed. Install it with:

    brew install pipx
    pipx install pymobiledevice3

Then connect the iPhone, unlock it and tap "Trust This Computer" if asked.
EOF
    exit 1
fi

if $all; then
    categories=()
elif [[ ${#categories[@]} -eq 0 ]]; then
    categories=("core.*")
fi

# --device <name>: resolve the device's name (as shown in Finder / Settings ›
# General › About) to its UDID through usbmux.
if [[ -n "$device" && -z "$udid" ]]; then
    udid="$(pymobiledevice3 usbmux list 2>/dev/null | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1].casefold()
for entry in json.load(sys.stdin):
    if str(entry.get("DeviceName", "")).casefold() == name:
        print(entry.get("Identifier") or entry.get("UniqueDeviceID") or "")
        break
' "$device")"
    if [[ -z "$udid" ]]; then
        echo "No connected device named \"$device\". Connected devices:" >&2
        pymobiledevice3 usbmux list >&2 || true
        exit 1
    fi
fi

args=(syslog live --process-name "$PROCESS" --subsystem "$SUBSYSTEM" --label)
for category in "${categories[@]+"${categories[@]}"}"; do
    args+=(--category "$category")
done
for text in "${matches[@]+"${matches[@]}"}"; do
    args+=(--match "$text")
done
[[ -n "$save" ]] && args+=(--out "$save")
[[ -n "$udid" ]] && args+=(--udid "$udid")
args+=("${extra[@]+"${extra[@]}"}")

if [[ ${#categories[@]} -eq 0 ]]; then
    scope="all categories"
else
    scope="categories ${categories[*]}"
fi
echo "Streaming $SUBSYSTEM ($scope) from the connected iPhone. Ctrl+C to stop." >&2
exec pymobiledevice3 "${args[@]}"
