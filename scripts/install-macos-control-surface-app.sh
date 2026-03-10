#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-debug}"
DESTINATION="${2:-auto}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$("$ROOT/scripts/build-macos-control-surface-app.sh" "$MODE")"
APP_NAME="$(basename "$APP_BUNDLE")"

resolve_install_dir() {
  case "$DESTINATION" in
    auto)
      if [[ -d "/Applications/$APP_NAME" && -w "/Applications" ]]; then
        printf '%s\n' "/Applications"
        return
      fi
      if [[ -d "$HOME/Applications/$APP_NAME" ]]; then
        mkdir -p "$HOME/Applications"
        printf '%s\n' "$HOME/Applications"
        return
      fi
      if [[ -d "/Applications/$APP_NAME" && ! -w "/Applications" ]]; then
        mkdir -p "$HOME/Applications"
        printf '%s\n' "$HOME/Applications"
        return
      fi
      if [[ -w "/Applications" ]]; then
        printf '%s\n' "/Applications"
        return
      fi
      mkdir -p "$HOME/Applications"
      printf '%s\n' "$HOME/Applications"
      ;;
    user)
      mkdir -p "$HOME/Applications"
      printf '%s\n' "$HOME/Applications"
      ;;
    system)
      printf '%s\n' "/Applications"
      ;;
    *)
      mkdir -p "$DESTINATION"
      printf '%s\n' "$DESTINATION"
      ;;
  esac
}

INSTALL_DIR="$(resolve_install_dir)"
TARGET_APP="$INSTALL_DIR/$APP_NAME"

osascript -e 'tell application "GGHarnessControlSurface" to quit' >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
ditto "$APP_BUNDLE" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true

printf '%s\n' "$TARGET_APP"
