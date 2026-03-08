# Runtime Profiles

This document defines runtime-specific wiring for the portable GG Agentic Harness.

## Profiles

| Profile | Primary Runtime | MCP Source of Truth |
|---|---|---|
| `codex` | Codex CLI sessions | `.agent/registry/mcp-runtime.json` |
| `claude` | Claude Code sessions | `.agent/registry/mcp-runtime.json` + Claude plugins |
| `kimi` | Kimi with the same harness contract | `.agent/registry/mcp-runtime.json` |

## Memory Path by Profile

Codex, Claude, and Kimi must execute the same memory strategy in this order:

1. `claude-mem` query path: `search -> timeline -> get_observations`
2. `memory` MCP fallback: `search_nodes -> open_nodes`
3. Worker HTTP fallback: `/api/search -> /api/timeline -> /api/observations/batch`
4. If all are unavailable, continue and log the skip reason in the run artifact

| Profile | Primary Path | Secondary | Tertiary |
|---|---|---|---|
| `claude` | claude-mem query path | memory MCP | worker HTTP fallback |
| `codex` | claude-mem query path | memory MCP | worker HTTP fallback |
| `kimi` | claude-mem query path | memory MCP | worker HTTP fallback |

## Tool-Dependent Rules

1. Run `npm run harness:runtime-parity` before high-value sessions or after MCP/prompt wiring changes.
2. Never assume optional worker-run transport tools exist. Check the runtime profile first.
3. If an MCP server or tool is unavailable for the active profile, use the documented fallback and continue.
4. Keep workflow docs profile-aware: do not hard-code single-runtime commands as universal.
5. Remote task tracking is CLI-first: use `node scripts/gws-task.mjs` plus `.agent/rules/remote-task-tracking.md` for `TASK|TASK_LITE|DECISION`.

## Codex Project Activation

`gg-skills` and `filesystem` are repo-scoped for Codex. Installing the harness into a new repo is not enough by itself; Codex must be activated against that repo so `~/.codex/config.toml` and `~/.codex/mcp.json` point at the current project.

Commands:

```bash
npm run harness:codex:activate
npm run harness:codex:status
```

Portable target from the source harness:

```bash
node packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo codex activate /absolute/path/to/target-repo
```

Behavior:

1. `activate` backs up the existing Codex config files.
2. `activate` rewrites project trust plus `gg-skills` and `filesystem` MCP entries for the selected repo.
3. Restart Codex after activation so the active session loads the new repo-scoped MCP paths.
4. `npm run harness:runtime-parity` should treat missing activation as a warning, not a repo wiring failure.

## Validation

Run `node scripts/harness-lint.mjs` to verify:

- prompt mirrors are aligned,
- persona registry and compound registry files exist,
- runtime docs reference the same MCP registry and artifact contracts shipped by the harness.

Run `npm run harness:codex:status` to confirm the current machine is activated for the repo you are working in.
