---
name: prompt-improver
description: "Runtime-agnostic intake workflow that normalizes vague objectives into actionable harness packets."
arguments:
  - name: objective
    description: "Raw user objective that needs intake normalization."
    required: true
user_invocable: true
---

# /prompt-improver

Normalize a raw objective before routing it into `/go`, `paperclip-extracted`, or any autonomous execution path.

## Usage

```bash
/prompt-improver <objective>
```

## Output Contract

Return a deterministic intake packet with:

1. normalized objective
2. constraints
3. acceptance criteria
4. risk flags
5. codebase findings
6. clarifying questions when the objective is still ambiguous

## Research Order

1. Conversation and local docs first
2. Codebase findings second
3. Optional graph-context pilot (`CodeGraphContext`) when enabled
4. No runtime-specific prompt hooks in the output contract

## Guardrails

1. Do not execute implementation work here.
2. Do not fabricate file targets or validation claims.
3. If the objective is still ambiguous, emit grounded clarifying questions instead of pretending it is ready.
4. Keep the packet portable across `codex`, `claude`, and `kimi`.
