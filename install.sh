#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(id -u)" == 0 ]]; then echo "Run as your normal user, without sudo." >&2; exit 1; fi
bash scripts/build.sh -c release
BIN_DIR="$(bash scripts/build.sh -c release --show-bin-path)"
MAC_SETUP_SOURCE_DIR="$BIN_DIR" bash scripts/install.sh
