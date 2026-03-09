# Harness Control Surface Design

Date: 2026-03-08  
Scope: Headless control plane, macOS control surface integration, swarm steering, per-agent worktrees, hardware-governed spawn control.

## 1. Approved Control Boundary

The `gg-agentic-harness` remains the sole control plane.

1. The harness owns:
- run creation
- worker spawn and termination
- message routing
- per-agent worktree allocation
- hardware-aware spawn limits
- steering and retask actions
2. Runtimes such as `kimi`, `claude`, and `codex` act as execution adapters only.
3. Kimi may request additional workers, but it may not spawn them directly.
4. The macOS application is an optional client over the same headless harness APIs.

Deferred extension point:

1. A future `runtime-autonomous-spawn` policy hook may allow brokered child creation.
2. That hook stays disabled by default and must preserve harness auditability, worktree ownership, and hardware limits.

## 2. Required Control Surfaces

### 2.1 Headless Harness Control Surfaces

These become the system of record regardless of whether the macOS app is running.

1. Run registry
- create, list, inspect runs
- show worker graph and lifecycle state
2. Worker lifecycle
- spawn
- launch
- terminate
- retry
- retask
3. Swarm steering
- send guidance to worker
- escalate
- request child delegation
- inspect current task, parent, persona, runtime, and worktree
4. Message bus
- inbox
- post
- acknowledge
- event stream
5. Worktree manager
- allocate one git worktree per worker
- expose worktree file listing and metadata
6. Resource governor
- compute safe concurrency from hardware capacity
- queue or block spawns when limits are reached
- expose governor status and decisions
7. Integration settings
- MCP catalog
- integration settings persistence
- quality jobs

### 2.2 macOS Application Control Surfaces

These are the current visual/operator surfaces already present in the imported app.

1. `Run History`
- run list and summary
2. `Live Log`
- event stream and logs
3. `Swarm`
- worker topology, parent-child map, steering actions, worktree view
4. `Agents`
- worker table and summaries
5. `Skill Analytics`
- skill/runtime activity summary
6. `Control`
- server process management and health
7. `Dispatch`
- task launch and run registration
8. `Trace`
- runtime execution trace visibility
9. `Tasks`
- create and inspect tasks
10. `Notes`
- operator note surface
11. `Terminal`
- server/runtime terminal access
12. `Packages`
- package/integration state
13. `Config`
- integration settings and MCP catalog application

## 3. Mapping: App Surface → Harness Surface

| macOS tab | Harness source of truth | Integration requirement |
|---|---|---|
| Run History | run registry | `GET /api/runs`, `GET /api/task/:id` |
| Live Log | event stream + run log store | `GET /api/events`, `GET /api/task/:id/log` |
| Swarm | worker graph + message bus + worktree manager | `GET /api/bus`, `GET /api/bus/:runId/status`, `GET /api/worktree`, steering endpoints |
| Agents | worker registry | list workers, status, runtime, persona, current task |
| Skill Analytics | run + skill telemetry | `GET /api/skill-stats` |
| Control | headless control-plane server | health, server process controls |
| Dispatch | run/task entrypoint | `POST /api/task`, `POST /api/runs/register` |
| Trace | run artifact + execution trace | per-worker execution metadata |
| Tasks | run/task store | create, fetch, delete |
| Notes | app-local or run note store | optional, non-blocking |
| Terminal | local process launcher | existing app process wrapper, optional |
| Packages | integration catalog/settings | persisted settings + catalog |
| Config | integration settings | `GET/PUT /api/integrations/settings`, MCP catalog/apply |

## 4. Server Architecture

Add a harness-native HTTP control-plane package in `packages/gg-control-plane-server`.

Responsibilities:

1. Expose the API contract expected by the imported macOS app.
2. Use `@geargrind/gg-orchestrator` as the source for run, worker, and bus state.
3. Use `@geargrind/gg-runtime-adapters` to execute workers.
4. Maintain lightweight sidecar state under `.agent/control-plane/server/` for:
- event logs
- task metadata
- integration settings
- quality jobs
- spawn queue state
5. Support running standalone:
- headless server only
- headless server plus macOS app

Non-goals for this phase:

1. No direct runtime-to-runtime spawning.
2. No dependency on the legacy GGAS backend.
3. No requirement that the macOS app be present for normal harness operation.

## 5. Worktree Model

Every sub-agent gets its own worktree.

1. Base path:
- `.agent/control-plane/worktrees/<runId>/<agentId>/`
2. Allocation:
- use `git worktree add --detach`
- branchless detached worktree is acceptable for ephemeral worker sessions
3. Ownership:
- one worktree per worker record
- parent and child never share the same worktree
4. Exposure:
- worktree path becomes part of worker state and app status payloads
5. Fallback:
- if real git worktree creation fails, mark the worker `blocked` and surface the failure
- do not silently fall back to the repo root for sub-agents

## 6. Hardware and Spawn Governance

The harness adopts the macOS app hardware-capacity model and adds a headless fallback governor.

### 6.1 Capacity Formula

Use the imported control-surface logic as the primary calculation:

1. `reserved = max(2.0, totalRAMGB * 0.20)`
2. `afterModel = max(0, availableRAMGB - modelVRAMGB)`
3. `usable = max(0, afterModel - reserved)`
4. `raw = usable / perAgentOverheadGB`
5. `clamped = max(1, min(64, floor(raw)))`

### 6.2 Harness Fallback Governor

The server adds:

1. CPU high/low hysteresis
2. queued spawn requests
3. active worker count enforcement
4. deterministic rejection/queue reasons recorded in run artifacts

### 6.3 Policy

1. Requested spawn count greater than capacity does not crash the run.
2. Excess workers remain queued until capacity is available.
3. High-risk tasks may still be denied regardless of capacity.
4. Governor decisions are visible in both the server status and the app.

## 7. Swarm Steering Contract

The Swarm tab becomes an operator view over harness-owned controls.

Supported operator actions:

1. send worker guidance
2. retry worker
3. retask worker
4. terminate worker
5. open worker worktree
6. inspect worker persona, runtime, current task, parent, and status

Harness rules:

1. steering actions mutate harness state first
2. runtimes consume those state changes through adapter execution or bus delivery
3. Kimi cannot bypass these controls

## 8. API Contract Additions

Keep existing app-compatible endpoints and add steering endpoints.

Required additions:

1. `POST /api/workers/:runId/:agentId/message`
2. `POST /api/workers/:runId/:agentId/retry`
3. `POST /api/workers/:runId/:agentId/retask`
4. `POST /api/workers/:runId/:agentId/terminate`
5. `GET /api/governor/status`

## 9. Headless/GUI Dual Mode

The harness must function in both modes without feature drift.

### 9.1 Headless mode

1. CLI and server run without the macOS app.
2. All run/worker/governor behavior remains available via CLI and HTTP.

### 9.2 GUI-assisted mode

1. macOS app consumes the same HTTP control plane.
2. UI adds visibility and steering, but it does not own any authoritative state.

## 10. Future Hook: Runtime-Autonomous Spawn

This phase intentionally does not enable Kimi-controlled child creation.

If enabled later, the minimum safe contract is:

1. Kimi submits a child plan and requested persona/runtime bundle.
2. Harness evaluates policy, hardware budget, and worktree availability.
3. Harness creates the worker and returns the approved child identity.
4. All audit, worktree, and governor logic remains harness-owned.

This hook must remain disabled unless explicitly turned on by policy.
