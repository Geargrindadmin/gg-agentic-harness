# Harness Control Surface Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a harness-native headless control plane and fully map the imported macOS control surface onto it, with swarm steering, per-agent worktrees, and hardware-governed spawn limits.

**Architecture:** Add a new `gg-control-plane-server` package that exposes the API expected by the imported macOS app, backed by `gg-orchestrator` and `gg-runtime-adapters`. Extend the orchestrator to support worker steering, worktree-aware execution, and server-friendly state queries. Keep Kimi harness-controlled and document a future brokered-autonomy hook without enabling it.

**Tech Stack:** TypeScript, Node.js, Express, SwiftUI, git worktrees, existing `gg-cli`, `gg-orchestrator`, and `gg-runtime-adapters` packages.

---

### Task 1: Extend orchestrator control-plane primitives

**Files:**
- Modify: `packages/gg-orchestrator/src/index.ts`
- Test: `packages/gg-orchestrator/package.json`

**Step 1: Add missing read/control helpers**

Implement helpers for:

```ts
listRunStates(projectRoot: string): RunState[]
terminateWorker(projectRoot: string, input: { runId: string; agentId: string; reason?: string }): { run: RunState; worker: WorkerRecord }
updateWorkerTask(projectRoot: string, input: { runId: string; agentId: string; taskSummary: string; append?: boolean }): { run: RunState; worker: WorkerRecord }
```

**Step 2: Thread execution cancellation**

Update execution signatures to accept an optional abort signal:

```ts
executeWorker(projectRoot, { runId, agentId, dryRun, signal })
```

**Step 3: Add worker status normalization**

Ensure worker state explicitly supports:

```ts
'spawn_requested' | 'queued' | 'running' | 'handoff_ready' | 'blocked' | 'failed' | 'terminated'
```

**Step 4: Run package verification**

Run: `npm run build --workspace=@geargrind/gg-orchestrator`

Expected: exit code `0`

### Task 2: Build the headless control-plane server package

**Files:**
- Create: `packages/gg-control-plane-server/package.json`
- Create: `packages/gg-control-plane-server/tsconfig.json`
- Create: `packages/gg-control-plane-server/src/index.ts`
- Create: `packages/gg-control-plane-server/src/governor.ts`
- Create: `packages/gg-control-plane-server/src/store.ts`

**Step 1: Create package scaffold**

Add the new workspace package with dependencies for HTTP serving and type-checking.

**Step 2: Implement API contract**

Expose:

```ts
GET  /health
GET  /api/status
GET  /api/runs
POST /api/runs/register
GET  /api/events
GET  /api/worktree
GET  /api/bus
GET  /api/bus/:runId/status
GET  /api/bus/:runId/stream
GET  /api/escalations
GET  /api/skill-stats
GET  /api/integrations/settings
PUT  /api/integrations/settings
GET  /api/integrations/mcp/catalog
POST /api/integrations/mcp/apply
POST /api/integrations/quality/run
GET  /api/integrations/quality/jobs
GET  /api/integrations/quality/jobs/:id
POST /api/task
GET  /api/task/:id
DELETE /api/task/:id
GET  /api/task/:id/log
GET  /api/task/:id/stream
POST /api/workers/:runId/:agentId/message
POST /api/workers/:runId/:agentId/retry
POST /api/workers/:runId/:agentId/retask
POST /api/workers/:runId/:agentId/terminate
GET  /api/governor/status
```

**Step 3: Persist lightweight sidecar state**

Store server metadata under:

```text
.agent/control-plane/server/
```

for logs, settings, jobs, and task records.

**Step 4: Run package verification**

Run: `npm run build --workspace=@geargrind/gg-control-plane-server`

Expected: exit code `0`

### Task 3: Implement worktree allocation for every worker

**Files:**
- Modify: `packages/gg-control-plane-server/src/index.ts`
- Modify: `packages/gg-cli/src/index.ts`

**Step 1: Allocate harness worktrees**

Create worktrees under:

```text
.agent/control-plane/worktrees/<runId>/<agentId>
```

using:

```bash
git -C <projectRoot> worktree add --force --detach <path> HEAD
```

**Step 2: Fail closed on worktree allocation errors**

If worktree creation fails:

1. mark worker `blocked`
2. append the failure to run metadata
3. do not launch the worker

**Step 3: Ensure CLI does not default sub-agents to repo root**

When worker actions omit `--worktree`, allocate or require a harness worktree instead of `projectRoot`.

**Step 4: Verify with a smoke run**

Run:

```bash
npm run gg -- run create --project-root /Users/shawn/Documents/gg-agentic-harness
```

Then spawn a worker and verify a real worktree path exists.

### Task 4: Adopt hardware-aware spawn governance

**Files:**
- Create: `packages/gg-control-plane-server/src/governor.ts`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/HardwareTopologyService.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/Models.swift`

**Step 1: Port the capacity formula into the server**

Match the macOS control-surface formula exactly.

**Step 2: Add CPU hysteresis and queueing**

Implement:

```ts
canSpawnNow()
queueSpawn()
drainQueue()
snapshot()
```

**Step 3: Surface governor state**

Make the server expose current capacity, active workers, queued workers, and gating reasons.

**Step 4: Verify behavior**

Run the server locally and confirm:

1. requested spawn count above limit is queued
2. queued workers drain when capacity is available

### Task 5: Wire the macOS app to the harness-native server

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/AgentMonitorService.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/AgentSwarmModel.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/Models.swift`

**Step 1: Add steering client methods**

Implement client calls for message, retry, retask, terminate, and governor status.

**Step 2: Normalize worker states**

Ensure the app correctly displays `queued`, `terminated`, and `handoff_ready`.

**Step 3: Preserve worktree visibility**

Use the actual harness worktree path instead of inferred `/tmp` fallback paths whenever available.

**Step 4: Verify compilation**

Run: `npm run macos:control-surface:build`

Expected: exit code `0`

### Task 6: Add Swarm steering controls

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/SwarmView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/WorktreePanel.swift`

**Step 1: Add worker inspector actions**

Expose controls for:

1. send guidance
2. retry
3. retask
4. terminate
5. open files

**Step 2: Bind actions to harness endpoints**

The UI must operate on harness worker IDs, not local inferred state only.

**Step 3: Keep the tab functional without the app running**

No state should exist only in the app. The app must remain a client.

**Step 4: Verify Swarm UI build**

Run: `npm run macos:control-surface:build`

Expected: exit code `0`

### Task 7: Wire root scripts and docs

**Files:**
- Modify: `package.json`
- Modify: `README.md`
- Modify: `docs/agentic-harness.md`
- Modify: `docs/runtime-profiles.md`
- Modify: `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`

**Step 1: Add server build/run scripts**

Include:

```json
"control-plane:build": "...",
"control-plane:start": "...",
"control-plane:dev": "..."
```

**Step 2: Document dual-mode usage**

Document:

1. headless only
2. headless plus macOS app
3. harness-controlled Kimi delegation

**Step 3: Record deferred autonomy hook**

Document the disabled future `runtime-autonomous-spawn` path.

### Task 8: End-to-end verification

**Files:**
- Verify only

**Step 1: Build all relevant packages**

Run:

```bash
npm run build
```

Expected: exit code `0`

**Step 2: Build the macOS app**

Run:

```bash
npm run macos:control-surface:build
```

Expected: exit code `0`

**Step 3: Run a control-plane smoke test**

Run:

```bash
npm run control-plane:start
curl -sf http://127.0.0.1:7891/health
curl -sf http://127.0.0.1:7891/api/status
curl -sf http://127.0.0.1:7891/api/runs
```

**Step 4: Verify worker lifecycle**

Create a run, spawn a worker, confirm:

1. worktree path created
2. worker visible in `/api/bus`
3. governor status reflects active worker
4. steering endpoint updates worker state

**Step 5: Final repo verification**

Run:

```bash
npm run lint
npm test
```

Expected: exit code `0`
