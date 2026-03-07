# Spec Template — Full (>50 LOC or auth/payments/security)

> **Board Decision**: 5-0 APPROVED (2026-03-02) — Tiered templates

## Instructions

Use this template for any task that:
- Changes >50 lines of code
- Touches auth, payments, or security code
- Creates new services, models, or API endpoints
- Involves multi-file refactoring

---

# Spec: [Feature/Task Name]

## Objective

One-sentence summary of what this agent must accomplish.

## Context

Brief description of why this change is needed. Reference PRD section if applicable.

## Exact Files to Modify

| File | Action | Lines | What Changes |
|------|--------|-------|-------------|
| `src/services/FooService.ts` | MODIFY | L45-L82 | Add validation logic for X |
| `src/models/Bar.ts` | NEW | — | Create Bar interface + model |
| `src/routes/baz.routes.ts` | MODIFY | L12-L20 | Add POST /baz endpoint |

## Code Context

Paste relevant code snippets the agent needs to understand:

```typescript
// Current implementation in FooService.ts (L45-L60)
// <paste actual code here>
```

## Acceptance Criteria

- [ ] Criterion 1 — specific and testable
- [ ] Criterion 2 — specific and testable
- [ ] Criterion 3 — specific and testable
- [ ] All existing tests still pass
- [ ] New tests written for new/changed code

## Out of Scope

- Do NOT modify [specific files/systems]
- Do NOT refactor [specific code areas]
- If you find bugs in [area], create a bead: `bd create "Found: {issue}" --deps discovered-from:{this-bead}`

## Quality Gate

Before marking this spec complete:

```bash
npx tsc --noEmit       # must exit 0
npm run lint            # must exit 0
npm test               # must exit 0 (100% pass)
```

## Dependencies

- Depends on: [other specs/beads if any]
- Blocks: [what this unblocks]
