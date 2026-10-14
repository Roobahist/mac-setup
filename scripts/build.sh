#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Recent SwiftUI SDKs implement @State through SwiftUIMacros. The standalone
# Command Line Tools may expose that SDK without shipping the macro plugin.
# Prefer full Xcode when installed, without modifying xcode-select globally.
if [[ "$(uname -s)" == "Darwin" ]]; then
  ACTIVE_DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [[ -z "${DEVELOPER_DIR:-}" &&
        "$ACTIVE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" &&
        -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    ACTIVE_DEVELOPER_DIR="$DEVELOPER_DIR"
    echo "Using Xcode for SwiftUI macro support: $DEVELOPER_DIR" >&2
  fi

  # Older Command Line Tools can still build this project. Probe the actual
  # compiler instead of rejecting every CLT installation based on its path.
  if [[ "$ACTIVE_DEVELOPER_DIR" == */CommandLineTools ]]; then
    PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-setup-swiftui.XXXXXX")"
    trap 'rm -rf "$PROBE_DIR"' EXIT
    cat > "$PROBE_DIR/StateProbe.swift" <<'SWIFT'
import SwiftUI
struct MacSetupStateProbe: View {
    @State private var counter = 0
    var body: some View { Text(String(counter)) }
}
SWIFT
    if ! swiftc -typecheck "$PROBE_DIR/StateProbe.swift" >"$PROBE_DIR/error.log" 2>&1; then
      if /usr/bin/grep -Eq 'SwiftUIMacros.StateMacro|plugin for module .SwiftUIMacros. not found' "$PROBE_DIR/error.log"; then
        cat >&2 <<'MESSAGE'
Cannot compile SwiftUI @State with the current Command Line Tools: SwiftUIMacros is missing.

Full Xcode is needed for the SwiftUI SDK selected on this Mac.
Install Xcode, then retry with:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash install.sh

Check the active developer directory using:
  xcode-select -p

Mac Setup does not change your system-wide Xcode selection.
Alternatively, install a prebuilt Mac Setup release if one is available.
MESSAGE
        exit 1
      fi
    fi
    rm -rf "$PROBE_DIR"
    trap - EXIT
  fi
fi

BUILD_DIR="${MAC_SETUP_BUILD_DIR:-.build/native}"
mkdir -p "$BUILD_DIR"
# Keep SwiftPM's native build engine and its caches isolated per checkout.
case "$BUILD_DIR" in /*) BUILD_ABSOLUTE="$BUILD_DIR" ;; *) BUILD_ABSOLUTE="$PWD/$BUILD_DIR" ;; esac
export CLANG_MODULE_CACHE_PATH="$BUILD_ABSOLUTE/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ABSOLUTE/module-cache"
exec swift build --build-system native --disable-sandbox --scratch-path "$BUILD_DIR" \
  --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" \
  --security-path "$BUILD_DIR/security" "$@"
