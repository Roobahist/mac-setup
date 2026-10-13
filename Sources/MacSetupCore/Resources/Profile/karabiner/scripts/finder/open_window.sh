#!/usr/bin/env bash

set -euo pipefail

# Finder may reuse an existing window when a folder is opened directly.
# Create an empty Finder window first, then point that new window at Home.
/usr/bin/osascript <<'APPLESCRIPT'
set homeFolder to path to home folder

tell application "Finder"
    activate
    set newWindow to make new Finder window
    set target of newWindow to homeFolder
end tell
APPLESCRIPT
