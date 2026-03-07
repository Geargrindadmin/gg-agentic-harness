---
trigger: always_on
priority: T2
---

# Agent Traceability Protocol

> **Board Decision**: 4-1 APPROVED (2026-03-02) — JSONL + commit prefix
> **Principle**: Every agent action must be traceable.

## Commit Message Format

All agent commits MUST use this prefix format:

```
[agent:{role}-{task-slug}] {conventional commit message}
```

**Examples:**
```
[agent:builder-auth-refactor] feat: add rate limiting to login endpoint
[agent:scout-audit] chore: document missing error handlers
[agent:reviewer-pr-42] fix: address code review comments
```

## Trace Log (Optional — for multi-agent workflows)

When running swarm/multi-agent workflows, create JSONL trace files:

**Location**: `.agent/logs/{agent-id}-{date}.jsonl`  
**Retention**: 7 days (auto-rotate)  
**Git**: `.gitignore`'d — logs are ephemeral  

### Entry Format

```json
{
  "agentId": "builder-auth-refactor",
  "role": "builder",
  "action": "write",
  "target": "src/services/AuthService.ts",
  "timestamp": "2026-03-02T23:45:00Z",
  "worktree": "worktrees/auth-refactor",
  "beadId": "bd-42",
  "result": "success",
  "summary": "Added rate limiting middleware to login endpoint"
}
```

## Rules

1. **Every commit** must have the `[agent:...]` prefix
2. **Multi-agent workflows** should use JSONL logs for detailed tracing
3. **Never edit** past log entries — append-only
4. **Trace files** are NOT committed to git
