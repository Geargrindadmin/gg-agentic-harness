---
description: Full board deliberation with discussion rounds - directors debate and reach consensus
---

# /board-meeting — Board of Directors Deliberation

Activate the Board of Directors persona from `AGENTS/agent.board.md`.

## When to Use

- Architecture decisions (new services, database changes, API design)
- Feature design requiring trade-offs
- Security-sensitive changes (auth, payments, PII)
- Cross-cutting concerns (performance vs. features, scope decisions)
- Sub-agent questions that require strategic direction
- Any change >50 LOC touching auth, payments, or security

## Protocol

### Step 1: Frame the Decision

State the decision clearly:
```
Topic: [What needs to be decided]
Context: [Why this decision is needed now]
Constraints: [Timeline, budget, technical limitations]
Stakeholder: [Who requested this — main agent or sub-agent]
```

### Step 2: Directors Research (MANDATORY, TWO PHASES)

Each director independently investigates before opining.

Phase A — Codebase Evidence:

| Director | Research Focus | Tools |
|----------|---------------|-------|
| **CA** (Architect) | Architecture docs, service files, dependency graph | `grep_search`, `view_file`, `view_file_outline` |
| **CPO** (Product) | PRD.md, user stories, existing feature behavior | `view_file` PRD.md, Task.md |
| **CSO** (Security) | Auth flows, data handling, OWASP checklist | `grep_search` for auth patterns |
| **COO** (Operations) | Deployment config, CI/CD, ops runbooks | `view_file` cloudbuild.yaml, Dockerfile |
| **CXO** (Experience) | Design system, UI patterns, accessibility | `view_file` cyber-component-dev-guide.md |

Phase B — Internet Evidence:

- Each director must collect current external evidence relevant to their domain (standards, advisories, vendor docs, benchmarks, or compliance updates).
- Every internet citation must include source and date.
- If no high-signal external evidence exists, explicitly record "no relevant external delta found" with searched domains/queries.

> 🔴 **Directors MUST cite both codebase files/patterns and internet sources from their research.** No opinions without evidence.

### Step 3: Brainstorm Options

Each director proposes 1-3 approaches. The board must surface **at least 3 distinct options**:

```markdown
### Option A: [Name] (proposed by [Director])
- Approach: [How it works]
- Trade-offs: [Pros vs Cons]
- Effort: [S/M/L]
- Risk: [Low/Med/High]
- Evidence: [File/pattern that supports this approach]
```

### Step 4: Deliberation Rounds

Directors debate the options (2-3 rounds):

**Round 1 — Initial Positions**: Each director states their preferred option and why.
**Round 2 — Challenges**: Directors challenge each other's positions with evidence.
**Round 3 — Convergence**: Directors identify common ground and final positions.

> Gate: Deliberation cannot start until all 5 directors have submitted both codebase and internet evidence.

### Step 5: Vote

| Director | Vote | Option | Rationale |
|----------|------|--------|-----------|
| CA | APPROVE/CONCERNS/REJECT | [A/B/C] | [1-2 sentences] |
| CPO | ... | ... | ... |
| CSO | ... | ... | ... |
| COO | ... | ... | ... |
| CXO | ... | ... | ... |

**Decision rules:**
- 5-0 or 4-1 = **APPROVED** (proceed immediately)
- 3-2 = **APPROVED WITH CONDITIONS** (address minority concerns)
- 2-3 or worse = **REJECTED** (propose new options or escalate to user)

### Step 6: Directives Output

The meeting MUST produce:

1. **Chosen approach** with rationale
2. **Action items** with owners (which agent/specialist handles what)
3. **PRD updates** — What to add/change in PRD.md
4. **Task.md updates** — Sub-tasks to scaffold
5. **Constraints** — Guardrails the implementation must follow
6. **Risks** — What to monitor during implementation

## Quick Board Review (for sub-agent questions)

When a sub-agent surfaces a question during execution, use a streamlined version:

```markdown
## Quick Board Review: [Question]

**Context**: [Sub-agent name] asks: [question]

| Director | Recommendation |
|----------|---------------|
| CA | [1 sentence] |
| CPO | [1 sentence] |
| CSO | [1 sentence] |
| COO | [1 sentence] |
| CXO | [1 sentence] |

**Consensus**: [Decision]
**Action**: [What to tell the sub-agent]
```

## Logging

All board decisions MUST be logged:
- In `walkthrough.md` under a "Board Decisions" section
- In `docs/governance/board-decisions/` for architectural decisions
- In the relevant bead via `bd update <id> --description "Board decision: ..."`
