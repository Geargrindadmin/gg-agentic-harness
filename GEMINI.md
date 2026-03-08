# CLAUDE.md

Canonical prompt contract for GG Agentic Harness.

- Use `gg-skills` MCP for skill/workflow discovery when available.
- Use `gg` CLI for deterministic operations (`doctor`, `skills`, `workflow`, `run`, `context`, `validate`, `obsidian`, `portable`).
- Verify runtime parity first: `npm run harness:runtime-parity`.
- Prime memory using `docs/memory.md` and `docs/runtime-profiles.md`.
- Before any specialist dispatch, run `npm run harness:persona:audit` and `node scripts/persona-registry-resolve.mjs --prompt "<task>" --classification <SIMPLE|TASK|TASK_LITE|DECISION|CRITICAL> --json`.
- For `TASK|TASK_LITE|DECISION`, mirror run status through `.agent/rules/remote-task-tracking.md` and `node scripts/gws-task.mjs`.
- Treat `.agent/registry/persona-registry.json` and `.agent/registry/persona-compounds.json` as the canonical routing contract. If the resolver returns `compoundPersona`, use it as the effective dispatch plan.
- If routing is low-confidence or a new persona is needed, follow `.agent/rules/persona-dispatch-governance.md`.
- Record persona routing evidence with `node scripts/agent-run-artifact.mjs persona --id <run-id> --resolution-file .agent/runs/<run-id>.persona-routing.json`.
- Keep runs traceable with `.agent/runs` artifacts and apply `.agent/rules/feedback-loop-governance.md` plus `node scripts/feedback-loop-report.mjs --window-days 7`.
- Keep changes minimal and verify with typecheck/lint/tests before completion claims.
