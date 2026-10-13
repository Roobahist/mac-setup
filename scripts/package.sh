#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.2.0}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
if [[ ! "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]]; then echo "Invalid version" >&2; exit 1; fi

BUILD_DIR="${MAC_SETUP_BUILD_DIR:-.build}"
SWIFT_OPTIONS=(--disable-sandbox --scratch-path "$BUILD_DIR" --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security")
swift build -c release --arch "$ARCH" "${SWIFT_OPTIONS[@]}"
BIN_DIR="$(swift build -c release --arch "$ARCH" "${SWIFT_OPTIONS[@]}" --show-bin-path)"
PACKAGE="mac-setup-$VERSION-macos-$ARCH"
DEST="dist/$PACKAGE"
mkdir -p "$DEST"
cp "$BIN_DIR/mac-setup" "$DEST/mac-setup"
cp -R "$BIN_DIR/MacSetup_MacSetupCore.bundle" "$DEST/"
cp scripts/install.sh README.md LICENSE NOTICE.md "$DEST/"
chmod +x "$DEST/mac-setup" "$DEST/install.sh"
# Ad-hoc signing meets Apple silicon's local executable requirement. It is
# not Developer ID signing or Apple notarization.
codesign --force --sign - "$DEST/mac-setup"
COPYFILE_DISABLE=1 tar -czf "dist/$PACKAGE.tar.gz" -C dist "$PACKAGE"
(cd dist && shasum -a 256 "$PACKAGE.tar.gz" > "$PACKAGE.tar.gz.sha256")
echo "Packaged dist/$PACKAGE.tar.gz"
