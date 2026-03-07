---
trigger: always_on
priority: T1
---

# Push Policy — Hybrid Mode

> **Board Decision**: 5-0 APPROVED (2026-03-02)
> **Principle**: Feature branches are for speed. Protected branches are for safety.

## Policy

| Branch Pattern | Agent Push Allowed | Human Gate |
|---------------|:------------------:|:----------:|
| `feature/*`, `fix/*`, `chore/*` | ✅ Auto-push after quality gates | ❌ |
| `main` | ❌ | ✅ Create PR |
| `release/*` | ❌ | ✅ Create PR |
| `hotfix/*` | ❌ | ✅ Create PR + emergency review |

## Enforcement

A pre-push hook in `.husky/pre-push` blocks direct pushes to protected branches.

## For Agents

- **Builders**: Work in feature branches. Push freely after quality gates pass.
- **Coordinators**: Create PRs to merge feature branches into main.
- **All agents**: NEVER force-push (`git push --force` is always blocked).

## Quality Gates Before Push

Before any push (including feature branches), the pre-push hook runs:
1. Full test suite (`npm test`)
2. TypeScript compilation (`npx tsc --noEmit`)
