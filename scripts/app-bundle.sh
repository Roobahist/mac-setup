#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="$1"
DEST_APP="$2"
BUILD_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/mac-setup-app.XXXXXX")"
trap 'rm -rf "$BUILD_PARENT"' EXIT
APP_DIR="$BUILD_PARENT/Mac Setup.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp -X "$BIN_DIR/mac-setup" "$APP_DIR/Contents/MacOS/mac-setup"
PROFILE_DIR="$BIN_DIR/MacSetup_MacSetupCore.bundle/Contents/Resources/Profile"
if [[ ! -d "$PROFILE_DIR" ]]; then PROFILE_DIR="$BIN_DIR/MacSetup_MacSetupCore.bundle/Profile"; fi
cp -RX "$PROFILE_DIR" "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.roobahist.mac-setup</string>
<key>CFBundleName</key><string>Mac Setup</string>
<key>CFBundleDisplayName</key><string>Mac Setup</string>
<key>CFBundleExecutable</key><string>mac-setup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR/Contents/MacOS/mac-setup"
codesign --force --sign - "$APP_DIR"

if [[ -e "$DEST_APP" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$EXISTING_ID" != "com.roobahist.mac-setup" || -L "$DEST_APP" ]]; then
    echo "Refusing to replace an unrelated app or symlink: $DEST_APP" >&2
    exit 1
  fi
  rm -rf "$DEST_APP"
fi
mkdir -p "$(dirname "$DEST_APP")"
mv "$APP_DIR" "$DEST_APP"
