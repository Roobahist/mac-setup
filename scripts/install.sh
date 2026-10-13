#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${MAC_SETUP_SOURCE_DIR:-$(cd "$(dirname "$0")" && pwd)}"
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
# Make the installed command available in new zsh sessions.
SHELL_RC="${ZDOTDIR:-$HOME}/.zshrc"
if [[ -L "$SHELL_RC" ]]; then
  echo "Shell configuration is linked; add $BIN_ROOT to PATH yourself."
else
  mkdir -p "$(dirname "$SHELL_RC")"
  printf -v BIN_QUOTED '%q' "$BIN_ROOT"
  PATH_LINE="export PATH=$BIN_QUOTED:\$PATH"
  if ! /usr/bin/grep -Fqx "$PATH_LINE" "$SHELL_RC" 2>/dev/null; then
    if [[ -e "$SHELL_RC" ]]; then cp -p "$SHELL_RC" "$SHELL_RC.mac-setup-backup-$(date +%Y%m%d-%H%M%S)-$$"; fi
    printf '\n# mac-setup command\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
  fi
  echo "Open a new terminal and run: mac-setup"
fi
