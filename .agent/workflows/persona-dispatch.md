---
description: Resolve the correct persona set for a task using the canonical registry before any sub-agent fanout.
---

# /persona-dispatch

Use this workflow before any specialist or parallel agent dispatch.

## Steps

1. Audit registry integrity:
   ```bash
   node scripts/persona-registry-audit.mjs
   ```
2. Resolve personas for the task:
   ```bash
   node scripts/persona-registry-resolve.mjs --prompt "<task>" --classification <SIMPLE|TASK|TASK_LITE|DECISION|CRITICAL> --json
   ```
3. Apply the result:
   - `primaryPersona` owns the first dispatch.
   - `collaboratorPersonas` are the only approved initial fanout set.
   - If `compoundPersona` is present, it becomes the effective dispatch contract.
   - If `boardRequired=true`, run `/board-meeting` before builders start.
4. If `createPersonaSuggested=true`, stop ad hoc dispatch and follow `.agent/rules/persona-dispatch-governance.md`.
5. If a runtime compound returns `promoteCompoundSuggested=true`, create a follow-up to add it to `.agent/registry/persona-compounds.json`.

## Output Contract

Return:

- chosen primary persona
- collaborator personas
- compound persona (if present)
- dispatch plan
- board requirement (`yes`/`no`)
- whether persona creation is required
- whether runtime compound promotion is suggested
