#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Respect the user's selected compiler. SwiftUI views explicitly use the
# original State property wrapper, which does not need the SwiftUIMacros
# plugin that can be missing from standalone Command Line Tools.
BUILD_DIR="${MAC_SETUP_BUILD_DIR:-.build/native}"
mkdir -p "$BUILD_DIR"
# Keep the native build engine and caches isolated in this checkout.
case "$BUILD_DIR" in /*) BUILD_ABSOLUTE="$BUILD_DIR" ;; *) BUILD_ABSOLUTE="$PWD/$BUILD_DIR" ;; esac
export CLANG_MODULE_CACHE_PATH="$BUILD_ABSOLUTE/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ABSOLUTE/module-cache"
exec swift build --build-system native --disable-sandbox --scratch-path "$BUILD_DIR" \
  --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" \
  --security-path "$BUILD_DIR/security" "$@"
