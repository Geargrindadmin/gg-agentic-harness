#!/usr/bin/env bash
set -euo pipefail

if [[ -L AGENTS.md ]]; then
  target="$(readlink AGENTS.md)"
  if [[ "$target" != "CLAUDE.md" ]]; then
    rm -f AGENTS.md
    ln -s CLAUDE.md AGENTS.md
  fi
else
  cp CLAUDE.md AGENTS.md
fi

echo "Synced AGENTS.md to canonical CLAUDE.md"
