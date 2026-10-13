#!/usr/bin/env bash

set -euo pipefail

PROFILE_NUMBER="${1:-}"

# Explicit mapping avoids reading Chrome's private profile metadata.
case "$PROFILE_NUMBER" in
    1) PROFILE_DIR="Default" ;;
    2) PROFILE_DIR="Profile 1" ;;
    3) PROFILE_DIR="Profile 2" ;;
    4) PROFILE_DIR="Profile 3" ;;
    5) PROFILE_DIR="Profile 4" ;;
    6) PROFILE_DIR="Profile 5" ;;
    7) PROFILE_DIR="Profile 6" ;;
    8) PROFILE_DIR="Profile 7" ;;
    9) PROFILE_DIR="Profile 8" ;;
    *) exit 2 ;;
esac

CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ ! -x "$CHROME_BIN" ]; then
    exit 1
fi

nohup "$CHROME_BIN" \
    --profile-directory="$PROFILE_DIR" \
    --new-window \
    >/dev/null 2>&1 </dev/null &
