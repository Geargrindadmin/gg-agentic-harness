---
description: Run the Testing Quality Gate — 11 specialized sub-agents verify test quality at the end of each 5-Cycle Engine phase. Hard-stop on failure.
---

# /test-quality-gate - Testing Quality Gate

$ARGUMENTS

---

## Purpose

Run all 11 testing sub-agents sequentially to verify code quality before proceeding to the next 5-Cycle Engine phase. **Hard-stop**: all agents must PASS at 100% for new code before cycle advancement.

---

## PRD Reference

📄 Full specification: [`docs/prd/PRD-TESTING-QUALITY-GATE.md`](../../docs/prd/PRD-TESTING-QUALITY-GATE.md)

---

## Execution Order

All 11 agents run in this order (cheapest/fastest first, most expensive last):

```
Phase Gate Execution Sequence:

  ┌─ 1. Coverage Agent ────────── Verify coverage thresholds met
  │  2. Unit Test Agent ────────── Verify all unit tests pass
  │  3. Component Test Agent ───── Verify component tests + a11y
  │  4. Integration Test Agent ─── Verify integration tests pass
  │  5. API Contract Agent ─────── Verify API schemas valid
  │  6. Mock Audit Agent ──────── Verify anti-mocking compliance
  │  7. Test Data Agent ────────── Verify data isolation
  │  8. Flaky Test Agent ──────── Check for new flaky tests
  │  9. E2E Test Agent ─────────── Verify E2E journeys pass
  │  10. Smoke Test Agent ──────── Verify smoke checks pass
  └─ 11. Performance Agent ────── Verify p95 targets met
```

---

## Behavior

### Step 1: Announce Gate

```markdown
🚦 **Testing Quality Gate — Cycle [C1-C5]**
Running 11 test agents sequentially. Hard-stop on failure.
```

### Step 2: Run Each Agent

For each agent in order:

// turbo-all

1. Read the agent persona file from `AGENTS/agent.test-{name}.md`
2. Execute the agent's commands
3. Evaluate results against pass criteria
4. Report PASS ✅ or FAIL ❌

### Step 3: Report Results

```markdown
## 🚦 Testing Quality Gate Results — Cycle [C1-C5]

| # | Agent | Verdict | Details |
|:-:|:------|:-------:|:--------|
| 1 | Coverage | ✅ PASS | 82% line, 73% branch |
| 2 | Unit Tests | ✅ PASS | 1,230/1,230 passing |
| 3 | Component Tests | ✅ PASS | 480/480 passing, 0 a11y violations |
| ... | ... | ... | ... |

**Overall**: ✅ ALL PASS — Proceed to next cycle.
```

### Step 4: Handle Failures

If ANY agent reports FAIL:

```markdown
## 🚦 Testing Quality Gate Results — Cycle [C2]

| # | Agent | Verdict | Details |
|:-:|:------|:-------:|:--------|
| 1 | Coverage | ❌ FAIL | Server: 78% (required 80%) |
| 2 | Unit Tests | ✅ PASS | 1,230/1,230 passing |

**Overall**: ❌ BLOCKED — Fix coverage in WalletService.ts (lines 45, 67, 89)
**Action**: Fix failures, then re-run `/test-quality-gate`
```

---

## Hard-Stop Rules

1. **ALL 11 agents must PASS** — No exceptions
2. **Max 3 retries** per failing agent per cycle
3. **After 3 failures**: Create bead, notify user, HALT
4. **Never proceed** to the next cycle with FAIL status
5. **New code requires 100% test pass rate** — pre-existing failures may be tagged `@known-issue`

---

## When to Run

| Trigger | Description |
|:--------|:------------|
| End of C1 (Research) | Baseline — existing tests still pass |
| End of C2 (Implementation) | New code has tests, coverage met |
| End of C3 (UI/UX) | A11y checks, E2E journeys pass |
| End of C4 (Hardening) | Performance targets met, full regression |
| End of C5 (Ship) | Final verification — all 11 PASS |

---

## Agent Persona Files

| Agent | Persona File |
|:------|:-------------|
| Coverage | `AGENTS/agent.test-coverage.md` |
| Unit Test | `AGENTS/agent.test-unit.md` |
| Component Test | `AGENTS/agent.test-component.md` |
| Integration Test | `AGENTS/agent.test-integration.md` |
| API Contract | `AGENTS/agent.test-api-contract.md` |
| Mock Audit | `AGENTS/agent.test-mocking-audit.md` |
| Test Data | `AGENTS/agent.test-data.md` |
| Flaky Test | `AGENTS/agent.test-flaky.md` |
| E2E Test | `AGENTS/agent.test-e2e.md` |
| Smoke Test | `AGENTS/agent.test-smoke.md` |
| Performance | `AGENTS/agent.test-performance.md` |

---

## Quick Reference

```bash
# Manual trigger (outside of 5-Cycle Engine)
# Invoke: /test-quality-gate

# Run individual agent check
# Read AGENTS/agent.test-unit.md, then execute its commands

# View PRD
cat docs/prd/PRD-TESTING-QUALITY-GATE.md
```
