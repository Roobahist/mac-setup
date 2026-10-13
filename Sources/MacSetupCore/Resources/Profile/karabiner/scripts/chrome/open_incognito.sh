#!/usr/bin/env bash

set -euo pipefail

CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ ! -x "$CHROME_BIN" ]; then
    exit 1
fi

nohup "$CHROME_BIN" \
    --incognito \
    --new-window \
    >/dev/null 2>&1 </dev/null &
