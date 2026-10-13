#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${MAC_SETUP_BUILD_DIR:-.build/native}"
mkdir -p "$BUILD_DIR"
# The native engine supports Command Line Tools without Xcode-only linker paths.
case "$BUILD_DIR" in /*) BUILD_ABSOLUTE="$BUILD_DIR" ;; *) BUILD_ABSOLUTE="$PWD/$BUILD_DIR" ;; esac
export CLANG_MODULE_CACHE_PATH="$BUILD_ABSOLUTE/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ABSOLUTE/module-cache"
exec swift build --build-system native --disable-sandbox --scratch-path "$BUILD_DIR" \
  --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" \
  --security-path "$BUILD_DIR/security" "$@"
