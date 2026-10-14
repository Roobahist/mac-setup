#!/usr/bin/env bash
set -euo pipefail
PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
AEROSPACE_CONFIG=auto
if [[ "$AEROSPACE_CONFIG" == auto ]]; then
  AEROSPACE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml"
fi
[[ -x "$PLUGIN_DIR/mac-setup-display" && -r "$AEROSPACE_CONFIG" ]] || exit 0
exec "$PLUGIN_DIR/mac-setup-display" refresh "$AEROSPACE_CONFIG"
