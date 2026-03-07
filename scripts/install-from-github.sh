#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
MODE="${2:-symlink}"
HARNESS_HOME="${HARNESS_HOME:-$HOME/.gg-agentic-harness}"
REPO_URL="${REPO_URL:-https://github.com/Geargrindadmin/gg-agentic-harness.git}"

if [[ "$MODE" != "symlink" && "$MODE" != "copy" ]]; then
  echo "Invalid mode: $MODE (expected: symlink|copy)" >&2
  exit 2
fi

if [[ -d "$HARNESS_HOME/.git" ]]; then
  git -C "$HARNESS_HOME" fetch --all --prune
  git -C "$HARNESS_HOME" pull --ff-only
else
  git clone "$REPO_URL" "$HARNESS_HOME"
fi

npm --prefix "$HARNESS_HOME" install
npm --prefix "$HARNESS_HOME" run build

node "$HARNESS_HOME/packages/gg-cli/dist/index.js" \
  --project-root "$HARNESS_HOME" \
  portable init "$TARGET_DIR" --mode "$MODE"

echo "Harness installed into: $TARGET_DIR"
echo "Source harness: $HARNESS_HOME"
echo "Verify target: node \"$HARNESS_HOME/packages/gg-cli/dist/index.js\" --project-root \"$TARGET_DIR\" --json doctor"
