---
name: symphony-lite
description: "Single isolated autonomous run flow inspired by Symphony: one task, one worktree, one validation gate"
arguments:
  - name: task
    description: "Specific implementation task"
    required: true
user_invocable: true
---

# /symphony-lite

A small Symphony-style flow for GGV3: isolate one task, execute autonomously, validate, and hand off.

## Usage

```bash
/symphony-lite <task>
```

## Contract

- One task per run.
- One isolated worktree per run (if repo state is noisy).
- One clear terminal outcome: `HANDOFF_READY` or `BLOCKED`.

## Flow

1. Normalize task:
- convert input to explicit acceptance criteria
- reject ambiguous tasks until clarified

2. Isolate execution:
- create bead and claim ownership
- optionally create worktree `worktrees/symphony-{bead-id}`

3. Execute implementation:
- minimal diff
- stay in scope
- capture discovered out-of-scope issues as separate tasks

4. Validate:
- `npx tsc --noEmit`
- `npm run lint`
- targeted tests for changed surfaces

5. Return handoff:
- `HANDOFF_READY`: include changed files, verification evidence, known risks
- `BLOCKED`: include blocker, attempted actions, required decision/input

## Guardrails

- No direct push from worker-style execution.
- No hidden retries beyond documented retry policy.
- No silent scope expansion.
