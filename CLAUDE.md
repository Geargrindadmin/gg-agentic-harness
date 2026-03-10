# CLAUDE.md

Canonical prompt contract for GG Agentic Harness.

## Core Operations

- Use `gg-skills` MCP for skill/workflow discovery when available.
- Use `gg` CLI for deterministic operations (`doctor`, `skills`, `workflow`, `run`, `context`, `validate`, `obsidian`, `portable`).
- Verify runtime parity first: `npm run harness:runtime-parity`.
- Prime memory using `docs/memory.md` and `docs/runtime-profiles.md`.

## Multi-Model Control Plane

- The harness now exposes a headless control-plane server at `packages/gg-control-plane-server`.
- Coordinator selection: `Auto` (default) or pinned via `GG_COORDINATOR_RUNTIME=codex|claude|kimi`.
- Sub-agents get dedicated worktrees under `.agent/control-plane/worktrees/<runId>/<agentId>`.
- Kimi remains harness-controlled: it can request delegation, but the harness owns spawn/terminate policy.

## Persona Dispatch

- Before any specialist dispatch, run `npm run harness:persona:audit` and `node scripts/persona-registry-resolve.mjs --prompt "<task>" --classification <SIMPLE|TASK|TASK_LITE|DECISION|CRITICAL> --json`.
- Treat `.agent/registry/persona-registry.json` and `.agent/registry/persona-compounds.json` as the canonical routing contract.
- If the resolver returns `compoundPersona`, use it as the effective dispatch plan.
- If routing is low-confidence or a new persona is needed, follow `.agent/rules/persona-dispatch-governance.md`.
- Record persona routing evidence with `node scripts/agent-run-artifact.mjs persona --id <run-id> --resolution-file .agent/runs/<run-id>.persona-routing.json`.

## Task Tracking and Governance

- For `TASK|TASK_LITE|DECISION`, mirror run status through `.agent/rules/remote-task-tracking.md` and `node scripts/gws-task.mjs`.
- Keep runs traceable with `.agent/runs` artifacts and apply `.agent/rules/feedback-loop-governance.md` plus `node scripts/feedback-loop-report.mjs --window-days 7`.
- Keep changes minimal and verify with typecheck/lint/tests before completion claims.

## Control Plane Commands

```bash
# Start control plane
npm run control-plane:start

# Runtime status
npm run harness:runtime:status

# Persona audit
npm run harness:persona:audit
```
