---
name: runtime-parity-smoke
description: 'Verify Codex, Claude, and Kimi share the same runtime parity contract before starting a serious run.'
arguments:
  - name: format
    description: 'Optional output format: text or json'
    required: false
user_invocable: true
---

# /runtime-parity-smoke

Run this before a serious session whenever prompt, MCP, memory, or workflow wiring has changed.

## Purpose

Catch runtime drift before it turns into code continuity drift.

The smoke gate verifies:

1. Prompt mirrors are aligned (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`)
2. Project context is current
3. `claude-mem` worker is reachable
4. Claude-side plugin cache exists
5. Codex local MCP config is wired to the same `claude-mem` bridge
6. Runtime registry exposes the same parity contract for `codex`, `claude`, and `kimi`

## Usage

```bash
npm run harness:runtime-parity
```

JSON output:

```bash
npm run harness:runtime-parity:json
```

## Interpretation

- `PASS`: runtime parity is intact
- `FAIL`: startup drift exists and should be fixed before a high-value run

## Typical Fixes

| Failure | Fix |
|--------|-----|
| project context stale | `npm run harness:project-context` |
| worker unreachable | restart Claude/worker and re-run smoke gate |
| Codex MCP missing `claude-mem` | patch `~/.codex/mcp.json` and `~/.codex/config.toml` |
| prompt mirrors drifted | sync `CLAUDE.md` mirror targets |

## Boot Order

Recommended session start:

1. `npm run harness:runtime-parity`
2. `npm run harness:project-context:check || npm run harness:project-context`
3. memory prime
4. classify request
5. continue into `/go` or `/minion`
