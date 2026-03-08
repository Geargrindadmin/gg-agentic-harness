---
trigger: before_any_subagent_dispatch
priority: T2
---

# Persona Dispatch Governance

`.agent/registry/persona-registry.json` and `.agent/registry/persona-compounds.json` are the canonical sources of truth for persona routing across `codex`, `claude`, and `kimi`.

## Required Flow

Before any multi-agent or specialist dispatch:

1. Run `node scripts/persona-registry-audit.mjs`
2. Resolve the task: `node scripts/persona-registry-resolve.mjs --prompt "<task>" --classification <SIMPLE|TASK|TASK_LITE|DECISION|CRITICAL> --json`
3. Use the resolved primary persona and collaborator set as the only approved starting dispatch.
4. If resolver returns `compoundPersona`, treat its primary/collaborator set as the effective dispatch contract and record it in the run artifact.
5. If resolver returns `boardRequired=true`, run `/board-meeting` before implementation fanout.
6. If resolver returns `createPersonaSuggested=true`, do not improvise a new persona inline. Register it first.
7. If resolver returns a runtime compound with `promoteCompoundSuggested=true`, register a follow-up to add it to `.agent/registry/persona-compounds.json` if the pattern recurs.

## Missing Persona Procedure

When there is no strong persona match:

1. Research the gap with `orchestrator`, `project-planner`, and `explorer-agent`.
2. Create the new persona file under `.agent/agents/<slug>.md`.
3. Add a matching entry to `.agent/registry/persona-registry.json`.
4. Run `node scripts/persona-registry-sync.mjs`.
5. Run `node scripts/persona-registry-audit.mjs`.
6. If a supporting workflow or skill is added, reload the catalog and run `node scripts/skills-audit.mjs`.

## Compound Persona Procedure

When a routing pattern repeats across multiple specialists:

1. Capture the runtime evidence from the resolver output or run artifact `personaRouting`.
2. Add the new compound definition to `.agent/registry/persona-compounds.json`.
3. Re-run `node scripts/persona-registry-audit.mjs`.
4. Update prompt/workflow docs if the compound changes the expected dispatch contract.

## Enforcement

- Persona files must include `## Agent Constraints` and `## Persona Dispatch Signals`.
- Role declarations in persona files must match the registry exactly.
- Memory query drift is a failure, not a warning.
- High-risk domains (`auth`, `payments`, `kyc`, `secrets`, `production`) require coordinator ownership plus board review.
- Runtime compounds are allowed, but they are not authoritative until promoted into `.agent/registry/persona-compounds.json`.
