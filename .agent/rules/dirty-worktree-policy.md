# Dirty Worktree Policy

Use `scripts/dirty-worktree-guard.sh` for deterministic dirty-state enforcement.

## Policy

1. Capture baseline once per run: `bash scripts/dirty-worktree-guard.sh init`
2. Before commit/push gates: `bash scripts/dirty-worktree-guard.sh check`
3. Behavior:
- New files matching denylist patterns fail immediately.
- New files not in allowlist fail as unexpected drift.
- Existing baseline dirt is tolerated (to support long-running/dirty repos).

## Policy Files

- Allowlist: `.agent/policies/dirty-worktree-allowlist.txt`
- Denylist: `.agent/policies/dirty-worktree-denylist.txt`

Keep both files short and explicit. Prefer adding targeted patterns over broad globs.
