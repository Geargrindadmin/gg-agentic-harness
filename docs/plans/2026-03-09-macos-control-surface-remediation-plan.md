# macOS Control Surface Remediation Plan

**Goal:** Make the macOS control surface production-ready against the `gg-agentic-harness` headless control plane, with no silent local side effects, no retired GGAS assumptions, and no dead operator surfaces.

**Architecture:** Treat the headless control plane as the single source of truth for runs, workers, worktrees, quality jobs, planner data, and integration settings. The macOS app is an optional control/viewer client over that API, while local features such as LM Studio and Terminal remain explicit operator tools rather than hidden startup dependencies.

**Tech Stack:** SwiftUI, Foundation, SwiftTerm, TypeScript, Node.js HTTP server, npm workspace scripts.

## 20-Pass Program

### Pass 1 — Remove Surprising Startup Side Effects
- Stop LM Studio from auto-launching during coordinator health checks.
- Keep health probes read-only by default.
- Add explicit launch semantics for LM Studio-only actions.

### Pass 2 — Standardize Control-Plane Connection Settings
- Use one configurable control-plane base URL derived from project settings.
- Route all app API traffic through that setting.
- Surface the active endpoint clearly in Config.

### Pass 3 — Unify Startup on the Harness Control Plane
- Remove the dead `start.sh` launcher path.
- Start the harness-native control plane with `npm run control-plane:start`.
- Keep the app usable whether the control plane is launched externally or from the app.

### Pass 4 — Coordinator and Runtime UX Cleanup
- Make coordinator selection explicit: `Auto | Codex | Claude | Kimi`.
- Clarify worker backend/runtime terminology in the app.
- Remove unclear or legacy labels where the harness is already the control plane.

### Pass 5 — Fix Live Log and Message Surfaces
- Stop inferring “current” runs from historical task state only.
- Stream harness-native logs and worker outputs from the control plane.
- Make text/message panes show real run and worker traffic.

### Pass 6 — Repair Planner CRUD Reliability
- Ensure planner tasks refresh consistently after create/update/delete.
- Preserve local editing state correctly.
- Make task state transitions predictable.

### Pass 7 — Repair Notes CRUD Reliability
- Ensure notes refresh consistently after create/update/delete.
- Avoid brittle raw-id workflows.
- Make task-linked notes a first-class path.

### Pass 8 — Improve Planner/Notes Integration
- Add quick note creation from planner tasks.
- Add explicit task linking in the Notes editor.
- Improve cross-navigation between tasks and notes.

### Pass 9 — Repair Broken Tab Contracts
- Align quality-runner status handling with the server.
- Make the quality tools surface match actual executable tools.
- Fix harness-native run selection for log and trace surfaces.

### Pass 10 — Remove Legacy GGAS Setup Assumptions
- Replace hardcoded `GearGrind-Agentic-System` roots and `gg-a2a-server` references.
- Keep setup flows portable across project roots.

### Pass 11 — Repair Package Persona Installation Paths
- Install personas into `.agent/agents`.
- Preserve existing skill/workflow package behavior.

### Pass 12 — Make Swarm and Agents Surfaces Operational
- Show real run graph data, heartbeats, and worker state.
- Add reliable steering controls for retask, retry, terminate, and guidance.
- Remove fake or stale placeholders.

### Pass 13 — Harden Worktree Handling
- Ensure every worker gets its own worktree.
- Make worktree paths inspectable from the app.
- Fail clearly on collisions or missing git state.

### Pass 14 — Make Governor and Hardware Controls Visible
- Surface headless governor decisions in the app.
- Show why workers are queued or blocked.
- Make local over-spawn attempts fail clearly.

### Pass 15 — LM Studio Integration Cleanup
- Separate LM Studio management from harness coordination.
- Keep LM Studio as an optional local model surface.
- Remove hidden assumptions that it is the default coordinator path.

### Pass 16 — Terminal Surface Reliability
- Keep terminal sessions durable across tab switches.
- Clarify background PTY vs visible terminal behavior.
- Make terminal launches traceable from the harness.

### Pass 17 — Usage and Observability Hardening
- Improve usage history/degraded states.
- Tie observability settings to real server capability.
- Remove misleading empty surfaces.

### Pass 18 — Version and Compatibility Handshake
- Add explicit app/server protocol compatibility checks.
- Detect stale control-plane processes before the UI binds to them.
- Fail with operator-readable remediation guidance.

### Pass 19 — End-to-End Production Validation
- Run app build, control-plane build, lint, and smoke tests.
- Validate planner, notes, dispatch, swarm, logs, and worktrees together.
- Re-test the app against a cold local start.

### Pass 20 — Packaging and Release Readiness
- Confirm launch behavior, persisted settings, and safe defaults.
- Prepare a stable internal release baseline.
- Document known constraints and next extensions.

## Immediate Active Passes

### Active Pass A — Startup and Side-Effect Control

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/LMStudioEngine.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/CoordinatorManager.swift`

**Intent:**
- Stop LM Studio from being launched by background health polling.
- Keep local side effects explicit and operator-driven.

### Active Pass B — Planner and Notes Hardening

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/TasksView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/NotesView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/ForgeStore.swift`

**Intent:**
- Make planner and notes usable without raw internal IDs.
- Add stronger task-linked note workflows.
- Improve refresh and editing reliability.

### Active Pass C — Re-verify the App and Headless Control Plane

**Commands:**
- `npm run macos:control-surface:build`
- `npm run build`
- `npm run lint`
- `npm test`

**Expected Outcome:**
- App builds cleanly.
- Headless control plane starts and responds.
- Planner and notes behave like harness-native features.
- LM Studio no longer launches during passive health checks.

### Active Pass D — Live Log and Messaging Repair

**Files:**
- Modify: `packages/gg-control-plane-server/src/index.ts`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/LiveLogView.swift`

**Intent:**
- Add a harness-native global task-log SSE stream.
- Stop the Live Log tab from inferring the “current” run by polling snapshots.
- Surface mixed swarm output with real run IDs so operator messaging windows become readable.

### Active Pass E — Deterministic macOS App Automation

**Files:**
- Modify: `apps/macos-control-surface/Package.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Add: `apps/macos-control-surface/Tests/GGHarnessControlSurfaceTests/*`
- Modify: `docs/plans/2026-03-09-macos-ui-automation-plan.md`

**Intent:**
- Establish a real Swift test target for the mac app.
- Cover planner/swarm shared workflow state with fixture-backed tests.
- Move the app toward deterministic verification instead of manual-only checking.

**Delivered so far:**
- `A2AClient` fixture transport override
- `WorkflowContextStore` shared-selection tests
- `AgentSwarmModel` run-graph / comm-link tests
- `WorktreeViewModel` success + missing-worktree tests
- `AgentMonitorService` visible-run filtering + comm-link dedupe tests
- `PlannerStore` reload/create-task tests
- AppKit-backed planner deployment inputs for model, agent-count, roles, worktree, timeout, and extra context

## Integration Opportunities

- Add a control-plane URL editor and health diagnostics panel so the app can target local, remote, or alternate-port harness instances.
- Expose governor telemetry directly in the Swarm and Control tabs so operators can see why workers are queued or paused.
- Add worker heartbeat timestamps and inbox counts to the Agents tab using `BusRunStatus` instead of the reduced `AgentSwarmModel` projection.
- Extend the quality runner into a true tool registry with per-tool availability checks, dry-run support, and result parsing for `semgrep`, `gitleaks`, `trivy`, and `promptfoo`.
- Extend the new global log stream to support richer worker/event filtering and message-pane reuse in Swarm and Trace.
