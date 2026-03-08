#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-check}"
BASELINE_FILE=".agent/state/dirty-worktree-baseline.txt"
ALLOWLIST_FILE=".agent/policies/dirty-worktree-allowlist.txt"
DENYLIST_FILE=".agent/policies/dirty-worktree-denylist.txt"

mkdir -p .agent/state

collect_changed_paths() {
  {
    git diff --name-only
    git diff --cached --name-only
    git ls-files --others --exclude-standard
  } | sed '/^$/d' | sort -u
}

matches_any_pattern() {
  local path="$1"
  local file="$2"
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
    if [[ "$path" == $pattern ]]; then
      return 0
    fi
  done < "$file"
  return 1
}

if [[ "$MODE" == "init" ]]; then
  collect_changed_paths > "$BASELINE_FILE"
  echo "Initialized dirty-worktree baseline at $BASELINE_FILE"
  exit 0
fi

if [[ "$MODE" != "check" ]]; then
  echo "Usage: bash scripts/dirty-worktree-guard.sh [init|check]" >&2
  exit 2
fi

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "Missing baseline: $BASELINE_FILE" >&2
  echo "Run: bash scripts/dirty-worktree-guard.sh init" >&2
  exit 2
fi

if [[ ! -f "$ALLOWLIST_FILE" || ! -f "$DENYLIST_FILE" ]]; then
  echo "Missing allowlist or denylist policy files." >&2
  exit 2
fi

unexpected=()
deny_hits=()
current_tmp="$(mktemp)"
trap 'rm -f "$current_tmp"' EXIT
collect_changed_paths > "$current_tmp"

while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -z "$path" ]] && continue

  if grep -Fxq "$path" "$BASELINE_FILE"; then
    continue
  fi

  if matches_any_pattern "$path" "$DENYLIST_FILE"; then
    deny_hits+=("$path")
    continue
  fi

  if matches_any_pattern "$path" "$ALLOWLIST_FILE"; then
    continue
  fi

  unexpected+=("$path")
done < "$current_tmp"

if [[ ${#deny_hits[@]} -gt 0 ]]; then
  echo "Dirty worktree check failed: denylist matches"
  printf '  - %s\n' "${deny_hits[@]}"
  exit 1
fi

if [[ ${#unexpected[@]} -gt 0 ]]; then
  echo "Dirty worktree check failed: unexpected newly-dirty paths"
  printf '  - %s\n' "${unexpected[@]}"
  echo "If expected, add specific patterns to $ALLOWLIST_FILE"
  exit 1
fi

echo "Dirty worktree check passed."
