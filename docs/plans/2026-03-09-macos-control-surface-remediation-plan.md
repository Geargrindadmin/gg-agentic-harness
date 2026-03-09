# macOS Control Surface Remediation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the macOS control surface function correctly against the `gg-agentic-harness` headless control plane, with no dependence on the retired GGAS repo layout.

**Architecture:** Treat the headless control plane as the single source of truth for runs, workers, worktrees, quality jobs, and integration settings. The macOS app becomes a configurable client over that API, while repo-local features such as LM Studio, Forge, and Terminal remain optional local surfaces. Legacy GGAS-specific setup/install assumptions are removed or isolated behind project-root driven helpers.

**Tech Stack:** SwiftUI, Foundation, SwiftTerm, TypeScript, Node.js HTTP server, npm workspace scripts.

---

### Task 1: Standardize Control-Plane Connection Settings

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/ProjectSettings.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/WorktreePanel.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ConfigView.swift`

**Intent:**
- Add a single configurable control-plane base URL derived from project settings.
- Make all app API traffic use that setting.
- Surface the configured endpoint in Config instead of hardcoding `:7891`.

### Task 2: Unify Startup on the Harness Control Plane

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/LaunchManager.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ControlPanelView.swift`

**Intent:**
- Remove the dead `start.sh` launcher path.
- Start the harness-native control plane with `npm run control-plane:start`.
- Keep the app functional whether the control plane is launched from the app or externally.

### Task 3: Repair Broken Tab Contracts

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/IntegrationControlSurfaceView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/CoordinatorManager.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/HardwareTopologyService.swift`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Intent:**
- Align quality-runner status handling with the server.
- Make the quality tools surface match actual executable tools.
- Fix live-log selection for harness-native runs.
- Make the hardware gate capable of blocking local over-spawn attempts.

### Task 4: Remove Legacy GGAS Setup Assumptions

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/SetupWizard.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ConfigView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/ProjectSettings.swift`

**Intent:**
- Replace hardcoded `GearGrind-Agentic-System` roots and `gg-a2a-server` references with harness-root aware logic.
- Keep setup flows portable across project roots.

### Task 5: Repair Package Persona Installation Paths

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/PackageManager.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/ProjectSettings.swift`

**Intent:**
- Install personas into `.agent/agents`.
- Preserve existing skill/workflow package behavior.

### Task 6: Re-verify the App and Headless Control Plane

**Files:**
- No code changes expected

**Commands:**
- `npm run macos:control-surface:build`
- `npm run build`
- `HARNESS_DRY_RUN=1 HARNESS_CONTROL_PLANE_PORT=7891 PROJECT_ROOT=/Users/shawn/Documents/gg-agentic-harness npm run control-plane:start`
- `curl -sf http://127.0.0.1:7891/health`
- `curl -sf http://127.0.0.1:7891/api/status`
- `curl -sf -X POST http://127.0.0.1:7891/api/task -H 'Content-Type: application/json' -d '{"task":"smoke task","mode":"auto","coordinator":"claude"}'`
- `curl -sf -X POST http://127.0.0.1:7891/api/integrations/quality/run -H 'Content-Type: application/json' -d '{"tools":["lint"],"profile":"quick"}'`

**Expected Outcome:**
- App builds cleanly.
- Headless control plane starts and responds.
- Quality runner and live-log contracts match the UI.
- Setup/config/package flows no longer target the old GGAS repo.

## Integration Opportunities

- Add a control-plane URL editor and health diagnostics panel so the app can target local, remote, or alternate-port harness instances.
- Expose governor telemetry directly in the Swarm and Control tabs so operators can see why workers are queued or paused.
- Add worker heartbeat timestamps and inbox counts to the Agents tab using `BusRunStatus` instead of the reduced `AgentSwarmModel` projection.
- Extend the quality runner into a true tool registry with per-tool availability checks, dry-run support, and result parsing for `semgrep`, `gitleaks`, `trivy`, and `promptfoo`.
- Add a live server log stream endpoint for global logs, so the Live Log tab stops inferring “current” runs from task history.
