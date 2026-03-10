# Multi-Model Control Plane Implementation Notes

> **Run ID:** run-mmj536fg-bbv1ng  
> **Date:** 2026-03-09  
> **Scope:** Multi-model harness control plane with runtime adapters, persona registry, and macOS control surface integration

---

## Overview

This implementation adds a multi-model control plane to the GG Agentic Harness, enabling coordinated execution across Codex, Claude, and Kimi runtimes. The control plane maintains the harness as the system of record while supporting live worker execution through runtime-specific adapters.

---

## Key Components Implemented

### 1. Runtime Adapters (`packages/gg-runtime-adapters`)

**Purpose:** Abstract runtime-specific activation and execution patterns behind a unified interface.

**Files:**
- `src/index.ts` — Core adapter interface and factory
- `test/runtime-adapters.test.mjs` — Adapter contract validation

**Adapter Implementations:**

| Adapter | Status | Host Mutation | Transport |
|---------|--------|---------------|-----------|
| `codex` | Active | Yes (config.toml, mcp.json) | background-terminal |
| `claude` | Active | No (contract-only) | background-terminal |
| `kimi` | Active | No (contract-only) | cli-session / api-session |

**Key Design Decisions:**
1. Codex requires host-level config mutation for repo-scoped MCPs (`gg-skills`, `filesystem`)
2. Claude and Kimi use contract-only adapters with dynamic transport selection
3. All adapters implement the same interface: `activate()`, `status()`, `validate()`

### 2. Control Plane Server (`packages/gg-control-plane-server`)

**Purpose:** Headless HTTP API for harness coordination, independent of the macOS app.

**Files:**
- `src/index.ts` — Express server setup and middleware
- `src/sessions.ts` — Worker session lifecycle management
- `src/planner.ts` — Run graph and task planning
- `src/governor.ts` — Hardware-governed spawn limits
- `src/store.ts` — Run state persistence
- `src/usage.ts` — Usage tracking and quotas

**API Surface:**
```typescript
POST /api/v1/runs              // Create new run
GET  /api/v1/runs/:id          // Get run status
POST /api/v1/runs/:id/spawn    // Spawn worker agent
POST /api/v1/runs/:id/terminate // Terminate worker
GET  /api/v1/worktrees         // List active worktrees
GET  /api/v1/mailbox/:runId    // Get messages for run
```

### 3. Persona Registry System

**Files:**
- `.agent/registry/persona-registry.json` — 21 specialist personas with domains, triggers, and constraints
- `.agent/registry/persona-compounds.json` — 4 compound personas for complex tasks
- `scripts/persona-registry-resolve.mjs` — Runtime persona resolution
- `scripts/persona-registry-audit.mjs` — Registry validation
- `scripts/persona-registry-benchmark.mjs` — Routing accuracy testing

**Persona Structure:**
```typescript
interface Persona {
  id: string;
  role: 'scout' | 'planner' | 'builder' | 'reviewer' | 'coordinator';
  dispatchMode: 'single' | 'parallel-safe' | 'discovery' | 'review-only' | 'coordinator';
  riskTier: 'low' | 'medium' | 'high';
  domains: string[];
  selectionTriggers: string[];
  requiresBoardFor: string[];
  allowed: string[];
  blocked: string[];
}
```

**Compound Personas:**
- `compound:auth-hardening:v1` — Auth changes with security review
- `compound:payment-reliability:v1` — Payment path coordination
- `compound:incident-hardening:v1` — Incident response team
- `compound:docs-governance:v1` — Documentation and PRD updates

### 4. Runtime Profiles (`docs/runtime-profiles.md`)

**Profiles Defined:**
- `codex` — Codex CLI with host activation
- `claude` — Claude Code with dynamic transport
- `kimi` — Kimi with Moonshot API fallback

**Coordinator Selection Policy:**
1. `GG_COORDINATOR_RUNTIME` env var for explicit pinning
2. `GG_COORDINATOR_PREFERENCE` (default: `codex,claude,kimi`)
3. Prefer authenticated local CLI sessions
4. Fall back to provider credentials
5. Fail clearly at preflight if credentials missing

### 5. macOS Control Surface Integration

**Files:**
- `apps/macos-control-surface/` — SwiftUI macOS app
- `Sources/GGASConsole/Services/LaunchManager.swift` — Worker launch coordination
- `Sources/GGASConsole/Models/AgentSwarmModel.swift` — Swarm state management

**Integration Points:**
1. macOS app connects to headless control plane via HTTP
2. Same worktree allocation: `.agent/control-plane/worktrees/<runId>/<agentId>`
3. Shared hardware governor formula for spawn limits
4. Coordinator selection exposed in dispatch UI

---

## Worktree Structure

```
.agent/control-plane/
├── worktrees/
│   └── {runId}/
│       ├── coordinator/          # Coordinator worktree
│       ├── builder-1/            # Builder agent worktree
│       ├── builder-2/            # Another builder
│       └── reviewer-1/           # Reviewer agent worktree
├── runs/
│   └── {runId}.json              # Run artifact
└── mailbox/
    └── {runId}/                  # Message bus for run
```

---

## Run Artifact Contract

Every run emits a machine-readable artifact at `.agent/runs/{run-id}.json`:

```json
{
  "runId": "run-mmj536fg-bbv1ng",
  "runtime": "codex|claude|kimi",
  "classification": "SIMPLE|TASK|DECISION|CRITICAL",
  "personaRouting": {
    "primary": "orchestrator",
    "collaborators": ["backend-specialist", "test-engineer"],
    "compoundPersona": "compound:auth-hardening:v1"
  },
  "validationGates": [
    {"gate": "tsc", "exitCode": 0, "attempts": 1}
  ],
  "status": "success|failed",
  "worktrees": ["coordinator", "builder-1", "builder-2"]
}
```

---

## Structured Worker Markers

Workers emit structured markers for harness parsing:

```
@@GG_MSG {"type":"PROGRESS","body":"Completed API implementation"}
@@GG_MSG {"type":"BLOCKED","body":"Waiting for database schema review","requiresAck":true}
@@GG_STATE {"status":"handoff_ready","summary":"Backend implementation complete, ready for review"}
@@GG_STATE {"status":"blocked","reason":"Security audit required for auth changes"}
```

---

## Validation Commands

```bash
# Runtime adapter status
npm run harness:runtime:status

# Full runtime parity check
npm run harness:runtime-parity

# Persona registry validation
npm run harness:persona:audit

# Persona routing benchmark
npm run harness:persona:benchmark

# Resolve personas for a task
node scripts/persona-registry-resolve.mjs \
  --prompt "ship auth hardening" \
  --classification TASK \
  --json

# Control plane health
curl http://localhost:3000/api/v1/health
```

---

## Known Limitations

1. **Codex Host Mutation:** Requires session restart after activation for MCP changes to take effect
2. **Kimi Transport:** Falls back to API session when local CLI unavailable (higher latency)
3. **Worktree Cleanup:** Orphaned worktrees require manual `bd prime` or periodic cleanup
4. **Memory Fallback:** If `claude-mem` unavailable, falls through to MCP then HTTP with degraded context

---

## Future Work

- [ ] Auto-cleanup of orphaned worktrees based on TTL
- [ ] Worker checkpoint/restore for long-running tasks
- [ ] Cross-runtime migration (handoff from Kimi to Claude)
- [ ] Distributed control plane (multi-machine swarm)

---

## References

- ADR 0004: Persona Registry Dispatch — `docs/decisions/0004-persona-registry-dispatch.md`
- ADR 0005: Compound Persona Runtime — `docs/decisions/0005-compound-persona-runtime.md`
- ADR 0006: Codex Project Activation — `docs/decisions/0006-codex-project-activation.md`
- ADR 0007: Runtime Activation Adapters — `docs/decisions/0007-runtime-activation-adapters.md`
- Runtime Profiles — `docs/runtime-profiles.md`
- Agentic Harness — `docs/agentic-harness.md`
