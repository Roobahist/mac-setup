#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH="${1:-$(uname -m)}"
VERSION="${2:-0.5.0}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
if [[ ! "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]]; then echo "Invalid version" >&2; exit 1; fi

bash scripts/build.sh -c release --arch "$ARCH"
BIN_DIR="$(bash scripts/build.sh -c release --arch "$ARCH" --show-bin-path)"
PACKAGE="mac-setup-$VERSION-macos-$ARCH"
DEST="dist/$PACKAGE"
mkdir -p "$DEST"
cp "$BIN_DIR/mac-setup" "$DEST/mac-setup"
cp "$BIN_DIR/mac-setup-display" "$DEST/mac-setup-display"
cp -R "$BIN_DIR/MacSetup_MacSetupCore.bundle" "$DEST/"
bash scripts/app-bundle.sh "$BIN_DIR" "$DEST/Mac Setup.app"
cp scripts/install.sh README.md LICENSE NOTICE.md "$DEST/"
chmod +x "$DEST/mac-setup" "$DEST/install.sh"
# Ad-hoc signing meets Apple silicon's local executable requirement. It is
# not Developer ID signing or Apple notarization.
codesign --force --sign - "$DEST/mac-setup"
codesign --force --sign - "$DEST/mac-setup-display"
COPYFILE_DISABLE=1 tar -czf "dist/$PACKAGE.tar.gz" -C dist "$PACKAGE"
(cd dist && shasum -a 256 "$PACKAGE.tar.gz" > "$PACKAGE.tar.gz.sha256")
echo "Packaged dist/$PACKAGE.tar.gz"
