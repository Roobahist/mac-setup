#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -x "$SOURCE_DIR/mac-setup" || ! -d "$SOURCE_DIR/MacSetup_MacSetupCore.bundle" ]]; then
  echo "Run this installer from an extracted release archive, beside mac-setup and its resource bundle." >&2
  exit 1
fi
if [[ "$(id -u)" == 0 ]]; then echo "Run as your normal user, without sudo." >&2; exit 1; fi

INSTALL_BASE="${MAC_SETUP_PREFIX:-$HOME/.local}"
INSTALL_ROOT="$INSTALL_BASE/lib/mac-setup"
BIN_ROOT="$INSTALL_BASE/bin"
if [[ -e "$BIN_ROOT/mac-setup" && ! -L "$BIN_ROOT/mac-setup" ]]; then
  echo "$BIN_ROOT/mac-setup is an existing file. Move it aside before installing." >&2
  exit 1
fi
if [[ -L "$BIN_ROOT/mac-setup" && "$(readlink "$BIN_ROOT/mac-setup")" != "$INSTALL_ROOT/current/mac-setup" ]]; then
  echo "$BIN_ROOT/mac-setup points to another installation. Move it aside first." >&2
  exit 1
fi
mkdir -p "$INSTALL_ROOT/versions" "$BIN_ROOT"
INSTALL_DIR="$INSTALL_ROOT/versions/$(date +%Y%m%d-%H%M%S)-$$"
mkdir "$INSTALL_DIR"
cp "$SOURCE_DIR/mac-setup" "$INSTALL_DIR/"
cp -R "$SOURCE_DIR/MacSetup_MacSetupCore.bundle" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/mac-setup"
if [[ -e "$INSTALL_ROOT/current" && ! -L "$INSTALL_ROOT/current" ]]; then
  echo "$INSTALL_ROOT/current is not a managed symlink. Move it aside first." >&2; exit 1
fi
ln -s "$INSTALL_DIR" "$INSTALL_ROOT/current.new-$$"
mv -fh "$INSTALL_ROOT/current.new-$$" "$INSTALL_ROOT/current"
ln -sfn "$INSTALL_ROOT/current/mac-setup" "$BIN_ROOT/mac-setup"
echo "Installed. Previous versions remain under $INSTALL_ROOT/versions."
echo "Run: $BIN_ROOT/mac-setup"
echo 'If ~/.local/bin is not on PATH, add it in your shell configuration.'
