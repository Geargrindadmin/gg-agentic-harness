# ADR 0006: Codex Project-Scoped Activation

- Date: 2026-03-08
- Status: Accepted

## Context

The portable harness ships repo-local `.mcp.json` and runtime registries, but Codex also reads global host config from `~/.codex/config.toml` and `~/.codex/mcp.json`. Before this change, `gg-skills` and `filesystem` were effectively pinned to whichever repo last edited the global config. That made portable installs incomplete and caused false parity failures when switching between `GGV3` and `gg-agentic-harness`.

## Decision

Introduce an explicit activation layer for repo-scoped Codex MCPs:

1. Ship `scripts/codex-project-sync.mjs` in the harness.
2. Expose it through:
   - `npm run harness:codex:activate`
   - `npm run harness:codex:status`
   - `gg codex activate|status`
3. `activate` rewrites project trust plus `gg-skills` and `filesystem` MCP entries in `~/.codex/config.toml` and `~/.codex/mcp.json`, with backups.
4. `portable verify` warns when the current machine has not activated the target repo, instead of treating that host-state gap as a structural repo failure.
5. The one-command installer activates Codex by default, with an opt-out via `ACTIVATE_CODEX=0`.

## Consequences

Positive:

- Portable installs are now operational on a clean machine without manual Codex path editing.
- Repo-local harness correctness is separated from host activation drift.
- Switching between projects becomes deterministic and auditable.

Trade-offs:

- Codex sessions must be restarted after activation to pick up new MCP paths.
- Host-level activation is now an explicit part of local operator workflow.
- Portable verification must distinguish host warnings from repo install failures.
