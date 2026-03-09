# PRD — Multi-Model Control Plane for GG Agentic Harness

**Document ID:** PRD-MULTI-MODEL-CONTROL-PLANE  
**Version:** 0.1  
**Date:** 2026-03-09  
**Status:** Draft  
**Owners:** Agentic Systems, Platform Engineering

## 1. Problem

The harness currently understands runtime profiles for `codex`, `claude`, and `kimi`, but it does not yet provide a first-class orchestration layer for one model-runtime to request, supervise, and validate work performed by another model-runtime. Runtime parity exists as metadata and activation policy, not as an execution control plane.

This creates four gaps:

1. Delegation decisions are not expressed as a deterministic harness policy.
2. Worker lifecycle control (`spawn`, `message`, `ack`, `terminate`) is not part of the harness core.
3. Model-to-model communication risks collapsing into ad hoc peer chat instead of a governed mailbox contract.
4. Run artifacts do not yet capture why one model-runtime was chosen over another for a delegated task.

## 2. Objective

Add a harness-native multi-model control plane so the active coordinator runtime can request work from another runtime under explicit policy, with deterministic traceability, bounded authority, and shared validation semantics.

## 3. Fit Within the Existing Harness

### 3.1 Harness Slot

This capability fits between the current harness execution layer and workflow engine:

- Node `3A` / `3B`: coordinator runtime remains the decision owner.
- Node `3.5`: evolves from "optional swarm bridge" into a **Multi-Model Control Plane**.
- Node `4`: 5-Cycle Engine remains the execution and validation contract.

### 3.2 Architectural Position

The control plane sits inside harness core, not as an external sidecar:

1. `gg-cli` remains the operator surface.
2. A new control plane package manages runs, workers, routing, and delegation policy.
3. Runtime adapters provide transport for `codex`, `claude`, and `kimi`.
4. A message bus provides mailbox-style worker communication.
5. Validation, governance, and run artifacts remain owned by the harness.

### 3.3 Proposed Package Additions

1. `packages/gg-orchestrator`
2. `packages/gg-runtime-adapters`
3. `packages/gg-message-bus`

## 4. Scope

### In Scope

1. Control-plane run registry (`runId`, `workerId`, parent-child graph).
2. Runtime adapter interface for `codex`, `claude`, and `kimi`.
3. Mailbox-style bus with directed messages, acknowledgements, and worker inbox polling.
4. Delegation policy that decides when Codex should use Kimi or Claude, and vice versa.
5. Worker status, timeout handling, escalation, and termination.
6. Run artifact evidence for delegation and runtime-routing decisions.
7. CLI commands for multi-model orchestration.
8. Hybrid PTY transport for live local CLI workers, with the harness preserving control of routing and state.

### Out of Scope

1. Unbounded peer-to-peer model conversation.
2. Direct worker authority to spawn arbitrary children without harness approval.
3. Replacing the existing workflow system, run artifacts, or validation gates.
4. Reintroducing legacy bridge/A2A assumptions as the core orchestration path.

## 5. Functional Requirements

### A. Control Plane

The harness must expose first-class orchestration primitives:

1. `createRun`
2. `spawnWorker`
3. `delegateTask`
4. `postMessage`
5. `fetchInbox`
6. `ackMessage`
7. `getWorkerStatus`
8. `terminateWorker`
9. `watchRun`

### B. Runtime Adapters

Each runtime adapter must implement a shared contract:

```ts
interface RuntimeAdapter {
  id: 'codex' | 'claude' | 'kimi';
  spawnWorker(input: SpawnWorkerInput): Promise<SpawnedWorker>;
  sendMessage(input: SendMessageInput): Promise<void>;
  fetchInbox(input: FetchInboxInput): Promise<BusMessage[]>;
  acknowledgeMessage(input: AckMessageInput): Promise<void>;
  getWorkerStatus(input: WorkerStatusInput): Promise<WorkerStatus>;
  terminateWorker(input: TerminateWorkerInput): Promise<void>;
  listCapabilities(): RuntimeCapabilities;
}
```

Each adapter must also expose a launch profile for live local sessions when the CLI is installed and authenticated:

1. `kimi`
   - preferred live transport: authenticated CLI session
   - autonomous flag: `--yolo`
2. `claude`
   - preferred live transport: background terminal session
   - autonomous flag: `--dangerously-skip-permissions`
3. `codex`
   - preferred live transport: background terminal session
   - autonomous flag: `--dangerously-bypass-approvals-and-sandbox`

### C. Message Bus

The bus must be mailbox-oriented, not chat-oriented.

Required message schema:

```json
{
  "runId": "run_123",
  "messageId": "msg_456",
  "fromAgentId": "planner-1",
  "toAgentId": "builder-1",
  "type": "TASK_SPEC",
  "payload": {},
  "requiresAck": true,
  "timestamp": "2026-03-09T00:00:00Z"
}
```

Required behavior:

1. Directed delivery by `toAgentId`.
2. Optional broadcast for coordinator-only system events.
3. Cursor-based inbox polling.
4. Explicit acknowledgement of messages when `requiresAck=true`.
5. Timeout detection for stale workers and unacked messages.

### C.1 Hybrid PTY Transport

The mailbox is the source of truth, but live-capable workers run inside background PTY sessions.

Required behavior:

1. The harness launches the worker terminal in the background, not in a separate app window.
2. The macOS app is an optional viewer/control surface for those sessions.
3. Guidance from the coordinator or operator is written into the target PTY only after it is recorded on the mailbox.
4. PTY output is parsed in near real time for structured markers and routed back into the mailbox.
5. Raw PTY output remains available for live logs and terminal inspectors.

Required structured markers:

```text
@@GG_MSG {"type":"PROGRESS","body":"Completed API scaffold"}
@@GG_MSG {"type":"BLOCKED","body":"Missing schema decision","requiresAck":true}
@@GG_STATE {"status":"handoff_ready","summary":"Ready for review"}
@@GG_STATE {"status":"blocked","reason":"Need credential from coordinator"}
```

### D. Delegation Policy

A worker runtime may request delegation, but only the harness may approve and spawn.

Required delegation flow:

1. Active runtime submits `DELEGATE_REQUEST`.
2. Harness evaluates task type, risk tier, tool availability, and runtime scorecard.
3. Harness either:
   - approves and spawns a child worker, or
   - rejects and returns a reason.
4. Decision is recorded in the run artifact.

### E. Runtime Routing Rules

Initial policy target:

1. `codex`
   - best default for coordinator, repo edits, deterministic local verification.
2. `claude`
   - preferred for planning, architecture synthesis, high-context review, and acceptance framing.
3. `kimi`
   - preferred for builder-style implementation tasks that are parallelizable, medium/low risk, and well scoped.

The runtime routing policy must prefer inherited local CLI sessions over remote API execution when:

1. the CLI is installed locally,
2. the CLI is already authenticated for the current user,
3. the runtime supports background or CLI-session transport, and
4. the hardware governor allows another live worker.

### F. Governance Rules

Delegation must fail closed under these conditions:

1. Task touches auth, payments, secrets, or irreversible side effects and lacks board approval.
2. Target runtime lacks required tools for the task.
3. Run policy marks target runtime degraded based on recent failure evidence.
4. Message-bus health or worker heartbeat is degraded.

## 6. Benefits

1. Coordinator and builder responsibilities are separated cleanly.
2. The harness can deploy multiple workers without losing deterministic ownership.
3. Multi-model runs become observable and auditable.
4. Codex can remain focused on orchestration and validation while Kimi handles parallel builder tasks.
5. Claude can be used selectively for planning and review without becoming a transport dependency.
6. Runtime choice becomes explainable instead of ad hoc.

### E.1 Coordinator Selection

The coordinator runtime must support both harness-driven and operator-pinned selection:

1. `Auto` is the default and should be exposed in the macOS app and any dispatch client.
2. Operators may pin `codex`, `claude`, or `kimi` for a given run.
3. The harness remains the control plane even when the coordinator is pinned.
4. `Auto` must prefer authenticated local CLI sessions before provider-backed API transport.
5. `Auto` must respect `GG_COORDINATOR_RUNTIME` and `GG_COORDINATOR_PREFERENCE` when those environment overrides are present.
6. The chosen coordinator runtime and the reason it was chosen must be recorded in the run log or run artifact.

## 7. Example Decision Policy

Codex should delegate to `kimi` when all of the following are true:

1. Task role = `builder`.
2. Risk tier = `low` or `medium`.
3. Work is parallelizable or implementation-heavy.
4. Target runtime has required tools and verified parity.
5. The task does not require board-only reasoning.

Codex should retain ownership when any of the following are true:

1. Task role = `coordinator` or `reviewer`.
2. Work requires local deterministic verification loops tightly coupled to the active session.
3. Risk tier = `high`.
4. Runtime parity or worker health checks fail.

## 8. CLI Requirements

The `gg` CLI must add orchestration commands:

```bash
gg run create
gg worker spawn --runtime codex --role coordinator
gg worker delegate --from planner-1 --to-runtime kimi --role builder
gg bus inbox --run-id <runId> --agent-id builder-1
gg run watch <runId>
```

## 9. Run Artifact Requirements

Run artifacts must record:

1. `activeRuntime`
2. `delegationDecisions[]`
3. `workerGraph`
4. `messageBusHealth`
5. `runtimeScorecards`
6. `delegationFailures[]`

## 10. Acceptance Criteria

1. Multi-model orchestration is documented as a harness-core capability at Node `3.5`.
2. A shared runtime adapter contract exists for `codex`, `claude`, and `kimi`.
3. The message bus supports inbox polling and acknowledgements.
4. Delegation decisions are policy-based and recorded in run artifacts.
5. CLI supports creating runs, spawning workers, delegating tasks, and inspecting inbox/state.
6. Runtime parity still passes for `codex`, `claude`, and `kimi`.
7. High-risk tasks fail closed without governance approval.
8. Live-capable workers can receive near-real-time operator guidance through harness-mediated PTY sessions.
9. The exact autonomous CLI flags are documented in the runtime profile contract and enforced by the launch adapter.

## 11. Rollout Plan

### Phase 1 — Contracts

1. Add control-plane PRD and architecture diagram.
2. Define adapter interfaces and message schema.
3. Extend run artifact schema for delegation evidence.

### Phase 2 — Core Runtime

1. Add `gg-message-bus`.
2. Add `gg-orchestrator`.
3. Add stub runtime adapters for `codex`, `claude`, and `kimi`.

### Phase 3 — CLI

1. Add `gg run`, `gg worker`, and `gg bus` command groups.
2. Add status and health inspection for runs and workers.

### Phase 4 — Policy Enforcement

1. Add routing scorecards and fail-closed governance checks.
2. Add runtime selection evidence to run artifacts.
3. Validate with controlled Codex -> Kimi and Codex -> Claude delegation scenarios.

## 12. Risks

1. Runtime recursion or uncontrolled fan-out.
   - Mitigation: only the harness may spawn children.
2. Soft chat semantics causing worker drift.
   - Mitigation: mailbox contract with explicit message types and acknowledgements.
3. Tool mismatch between runtimes.
   - Mitigation: adapter capability checks before delegation.
4. Governance bypass.
   - Mitigation: delegation policy enforced before worker creation.

## 13. Reference Diagram

- Diagram: [docs/architecture/agentic-harness-multi-model-control-plane-diagram.html](../architecture/agentic-harness-multi-model-control-plane-diagram.html)
