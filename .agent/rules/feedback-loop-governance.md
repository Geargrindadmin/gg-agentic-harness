# Feedback Loop Governance (Internal + External)

## Purpose

Eliminate repeated failures by enforcing two connected loops:

1. Internal Loop: within a single run (fast correction)
2. External Loop: across runs (system-level hardening)

This rule applies to `TASK`, `TASK_LITE`, and `DECISION`.

---

## Internal Loop (In-Run)

Use this loop after every failed deterministic gate (`tsc`, lint, tests, security, deploy preflight):

1. Detect failure signature (error code/message + file path + command).
2. Attempt bounded repair with retry budget (max 3 attempts, backoff 1s -> 2s -> 4s).
3. If the same signature appears 2+ times in the same run:
   - Record as recurring in run artifact (`gate` event with reason `recurring-failure`).
   - Create a `discovered-from` bead for root-cause hardening.
4. If attempts exceed budget:
   - Stop current fix loop.
   - Roll back per rollback plan.
   - Escalate with blocker summary.

Never suppress failures. Convert them into evidence.

---

## External Loop (Cross-Run)

At run completion, inspect recent run artifacts and normalize recurring patterns.

Trigger thresholds (any one):

1. Same TypeScript error code appears in >=3 runs within 7 days.
2. Same lint rule appears in >=3 runs within 7 days.
3. Same flaky test fails in >=2 runs within 7 days.

When triggered, create one hardening action:

1. Skill candidate (if workflow/tooling gap)
2. Rule candidate (if governance/policy gap)
3. Workflow candidate (if orchestration gap)

Required outputs:

1. Bead linked to source runs.
2. Proposal doc in `docs/governance/feedback-loop-proposals/`.
3. If approved, integrate into:
   - `.agent/rules/*.md`
   - `.agent/workflows/*.md`
   - `CLAUDE.md` + `AGENTS.md` if prompt-level behavior changes.

---

## Cross-Runtime Parity Contract

Codex, Claude, and Kimi must apply identical loop semantics:

1. Same gate order.
2. Same retry budget.
3. Same escalation thresholds.
4. Same artifact evidence requirements.

Runtime-specific tools may differ, but control logic must not.

