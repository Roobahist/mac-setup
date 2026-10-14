#!/usr/bin/env bash
# export shared colors; your aerospace.sh and sketchybarrc will source this

export BAR_COLOR=0x35000000
export BASE_GRAY=0xff9ca3af
export BASE_WHITE=0xffffffff
export HIGHLIGHT_COLOR=0xff7873B6

# Manual extraction uses a cache. The existing watcher writes this file; only
# use a cache newer than this file so it cannot mask a subsequent watcher update.
ACCENT_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/highlight-color"
if [[ -r "$ACCENT_FILE" && "$ACCENT_FILE" -nt "${BASH_SOURCE[0]}" ]]; then
  IFS= read -r local_accent < "$ACCENT_FILE" || true
  if [[ "$local_accent" =~ ^0xff[0-9A-Fa-f]{6}$ ]]; then
    export HIGHLIGHT_COLOR="$local_accent"
  fi
fi
