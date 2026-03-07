---
trigger: always_on
priority: T1
---

# Agent Role Permissions Matrix

> **Board Decision**: 4-1 APPROVED (2026-03-02) — Phased rollout
> **Principle**: Principle of least privilege. An agent should only have the tools it needs.

## Role Definitions

| Role | Read Files | Write Files | Execute Commands | Git Commit | Git Push |
|------|:----------:|:-----------:|:----------------:|:----------:|:--------:|
| **Scout** | ✅ | ❌ | ❌ (read-only cmds) | ❌ | ❌ |
| **Planner** | ✅ | ✅ (docs/plans only) | ❌ | ❌ | ❌ |
| **Builder** | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Reviewer** | ✅ | ✅ (comments only) | ✅ (tests only) | ❌ | ❌ |
| **Coordinator** | ✅ | ✅ | ✅ | ✅ | ✅ (feature branches only) |

## Role Assignment

Every agent persona file in `AGENTS/` must declare its role:

```markdown
## Agent Constraints
- Role: [scout|planner|builder|reviewer|coordinator]
- Allowed: [explicit list of allowed actions]
- Blocked: [explicit list of blocked actions]
```

## Enforcement (Phased)

### Phase 1 (Current): Document role expectations
- Role matrix defined (this file)
- Agent personas updated with role declarations

### Phase 2: Critical hard blocks
- Block `git push` for non-coordinator roles
- Block destructive commands (`rm -rf`, `DROP TABLE`, etc.)

### Phase 3: Full tool-level enforcement
- Hook-based tool restriction per role
- Automatic detection of role violations

## Violations

If an agent exceeds its role permissions:
1. Log the violation
2. Warn the coordinator
3. On repeated violations: reset the agent
