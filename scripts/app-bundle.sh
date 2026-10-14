#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="$1"
APP_DIR="$2"
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
