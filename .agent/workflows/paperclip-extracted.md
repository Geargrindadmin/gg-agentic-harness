---
name: paperclip-extracted
description: "Extracted workflow patterns (not platform adoption): intake triage, capability routing, and gated execution"
arguments:
  - name: objective
    description: "Business objective or delivery goal"
    required: true
user_invocable: true
---

# /paperclip-extracted

This workflow cherry-picks high-signal orchestration patterns from Paperclip-style operations without adopting a new orchestration platform.

## Usage

```bash
/paperclip-extracted <objective>
```

## Patterns Integrated

1. Intake triage: normalize objective into measurable outcomes.
2. Capability routing: map outcome to existing local skills/workflows.
3. Stage gates: block transitions unless acceptance criteria are explicit.
4. Exception queue: capture off-scope findings as separate tasks, no inline scope creep.
5. Execution audit: log what was decided, run, and verified.

## Execution Steps

1. Define outcome:
- objective
- owner
- success metric
- deadline

2. Route to existing capabilities:
- identify primary workflow (`go`, `minion`, `loop-*`, or targeted skill)
- identify required validators (`tsc`, lint, tests, security checks)

3. Enforce delivery gates:
- Gate A: plan approved
- Gate B: implementation complete
- Gate C: validation pass
- Gate D: handoff documented

4. Escalation handling:
- if requirements conflict, stop and request decision
- if dependency is missing, mark blocker and create task

5. Emit concise run summary:
- what was done
- what was skipped
- what remains

## Integration Boundary

- Do not install or run Paperclip runtime.
- Use local GGV3 harness primitives only.
