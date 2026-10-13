#!/bin/sh

# SketchyBar invokes this once a second so the display changes immediately at
# a minute boundary.  Avoid making an IPC call during the other 59 seconds.
current_minute="$(date '+%Y-%m-%d %H:%M')"
state_file="${TMPDIR:-/tmp}/sketchybar-clock-minute"

if [ -r "$state_file" ] && [ "$(<"$state_file")" = "$current_minute" ]; then
  exit 0
fi

printf '%s\n' "$current_minute" > "$state_file"
sketchybar --set "$NAME" label="$(date +'%a %b %d %H:%M')"
