#!/usr/bin/env bash

PLUGIN_DIR="$CONFIG_DIR/plugins"
source "$PLUGIN_DIR/colors.sh"

WORKSPACES=("$@")
CACHE_FILE="$HOME/.cache/sketchybar/focused-workspace"

focused_workspace() {
  local focused=""

  if [ -r "$CACHE_FILE" ]; then
    IFS= read -r focused < "$CACHE_FILE"
  fi

  if [ -z "$focused" ]; then
    focused="${FOCUSED:-${FOCUSED_WORKSPACE:-}}"
  fi

  if [ -z "$focused" ]; then
    focused="$(aerospace list-workspaces --focused 2>/dev/null)" || return 1
  fi

  printf '%s\n' "$focused"
}

# One subscribed observer updates every workspace in a single SketchyBar call.
# This avoids queuing thirteen scripts and AeroSpace queries for every event.
while :; do
  CURRENT_WORKSPACE="$(focused_workspace)" || exit 0

  if ACTIVE_WORKSPACES="$(aerospace list-windows --all --format '%{workspace}' 2>/dev/null)"; then
    HAVE_WINDOW_LIST=true
  else
    ACTIVE_WORKSPACES=""
    HAVE_WINDOW_LIST=false
  fi

  # The window query can overlap a newer workspace event. Re-read the shared
  # focus value before painting so this handler always applies the latest state.
  LATEST_WORKSPACE="$(focused_workspace)" || exit 0
  CURRENT_WORKSPACE="$LATEST_WORKSPACE"

  UPDATE=(sketchybar)

  for WORKSPACE in "${WORKSPACES[@]}"; do
    if [ "$WORKSPACE" = "$CURRENT_WORKSPACE" ]; then
      COLOR="$HIGHLIGHT_COLOR"
    elif ! $HAVE_WINDOW_LIST; then
      # Clear any stale highlight even if AeroSpace is briefly unavailable.
      COLOR="$BASE_WHITE"
    elif printf '%s\n' "$ACTIVE_WORKSPACES" | grep -Fxq "$WORKSPACE"; then
      COLOR="$BASE_WHITE"
    else
      COLOR="$BASE_GRAY"
    fi

    UPDATE+=(--set "space.$WORKSPACE" label.color="$COLOR")
  done

  "${UPDATE[@]}"

  # If focus changed while the batch was being applied, immediately recompute.
  AFTER_UPDATE_WORKSPACE="$(focused_workspace)" || exit 0
  [ "$AFTER_UPDATE_WORKSPACE" = "$CURRENT_WORKSPACE" ] && exit 0
done
