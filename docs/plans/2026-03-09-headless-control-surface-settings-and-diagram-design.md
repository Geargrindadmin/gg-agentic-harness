# Headless Control-Surface Settings and Dynamic Diagram Design

Date: 2026-03-09
Scope: Keep `gg-agentic-harness` fully headless, add canonical harness settings that can be edited by the optional macOS app, add a dynamic end-user architecture diagram tab, and harden installer/runtime parity so a fresh install works without the app.

## 1. Goals

1. Preserve the current contract that the headless harness is the system of record.
2. Make selected harness defaults adjustable without requiring the macOS app.
3. Let the macOS app edit and visualize those same settings when installed.
4. Replace the current static architecture-only diagram experience with a richer end-user explainer that overlays live control-plane state.
5. Finish with a portable installer path that passes deterministic verification.

## 2. Non-Negotiable Boundaries

1. The macOS app must remain an optional client only.
2. No authoritative harness setting may live only in Swift `UserDefaults`.
3. Headless CLI and control-plane usage must remain fully functional with no GUI installed.
4. The app may cache local view preferences, but not canonical runtime behavior.
5. Installer success must include runtime parity and portable verification, not only app build success.

## 3. Canonical Settings Model

Add a harness-owned persisted settings document under the repo, served by the control plane and editable by CLI/app.

Recommended location:

- `.agent/control-plane/server/harness-settings.json`

Recommended shape:

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-03-09T00:00:00.000Z",
  "source": "default",
  "diagram": {
    "defaultView": "system",
    "showLiveOverlays": true,
    "showLegend": true
  },
  "execution": {
    "loopBudget": 50,
    "retryLimit": 3,
    "retryBackoffSeconds": [1, 2, 4],
    "defaultValidateMode": "all",
    "defaultDocSyncMode": "auto",
    "promptImproverMode": "auto",
    "contextSource": "prefer",
    "hydraMode": "off"
  },
  "dispatch": {
    "defaultCoordinator": "auto",
    "defaultWorkerRuntime": "kimi",
    "defaultTopology": "team",
    "defaultBridgeAgents": 4,
    "defaultBridgeStrategy": "parallel",
    "defaultTimeoutSeconds": 1800
  },
  "governor": {
    "cpuHighPct": 85,
    "cpuLowPct": 70,
    "reservedRamGb": null,
    "modelVramGb": 0,
    "perAgentOverheadGb": 0.5
  },
  "artifacts": {
    "promptVersion": "",
    "workflowVersion": "",
    "blueprintVersion": "",
    "riskTier": "medium",
    "toolBundle": []
  }
}
```

## 4. Settings Precedence

Canonical precedence should be deterministic:

1. Explicit per-run request payload
2. Stored harness settings
3. Environment overrides for machine-sensitive governor values
4. Built-in harness defaults

Rules:

1. Headless CLI and server both read the same stored settings.
2. App edits write through the control plane into the same stored settings.
3. Environment variables still override machine safety knobs where appropriate.
4. Stored settings must validate and fail closed to safe defaults.

## 5. Headless Interfaces

### 5.1 Control-plane API

Add:

1. `GET /api/harness/settings`
2. `PUT /api/harness/settings`
3. `POST /api/harness/settings/reset`
4. `GET /api/harness/diagram`

`/api/harness/diagram` should return a merged payload with:

1. static architecture nodes and edges
2. current governor snapshot
3. current active run summary
4. worker graph
5. runtime scorecards
6. current settings snapshot
7. compatibility or degraded-state notes

### 5.2 CLI

Extend `gg` with deterministic headless commands:

1. `gg harness settings get`
2. `gg harness settings set --key value`
3. `gg harness settings reset`
4. `gg harness diagram --format json|html`

These commands let a machine with no app installed inspect and change the same settings.

## 6. Dynamic Diagram Experience

The new app tab should not be just a file viewer. It should be a live explainer built from two layers:

1. A richer static HTML architecture document for end users
2. Live overlay data from `/api/harness/diagram`

Recommended presentation:

1. System layer
- Entry points
- Control plane
- worker graph
- message bus
- worktree manager
- validation/doc gates

2. Live layer
- active coordinator runtime
- active worker count vs governor capacity
- queued workers
- active run ID and status
- selected topology and team plan
- warnings such as parity failure, missing credentials, or stale control plane

3. Explainability layer
- plain-language descriptions for each node
- "what this means" callouts for end users
- live state chips instead of raw JSON

4. Offline fallback
- if the server is unreachable, render the static diagram with a visible "live data unavailable" banner

## 7. macOS App Changes

### 7.1 New Tab

Add `Harness Diagram` to the sidebar and load a dedicated view.

That view should:

1. load the local HTML artifact from `docs/architecture/`
2. poll or subscribe to control-plane diagram/state data
3. inject or render live overlay panels
4. provide a quick switch between:
- `System`
- `Live Control Plane`
- `Installer Readiness`

### 7.2 Harness Settings Editor

Add a headless-backed settings panel, likely under `Config` or a new `Harness Settings` section.

Expose:

1. loop budget
2. retry limit
3. retry backoff
4. validate mode
5. doc-sync mode
6. prompt-improver mode
7. context-source mode
8. hydra mode
9. default coordinator/runtime/topology/team size
10. governor overrides
11. artifact version fields and default risk tier/tool bundle

Do not expose raw prompt mirror file editing in v1.
Instead, expose structured knobs that already map to harness behavior.

### 7.3 Existing Local-Only Settings

LM Studio and per-model prompt/inference settings remain local operator tooling.
They should be clearly labeled as model/runtime-local rather than canonical harness policy.

## 8. Installer and Runtime-Parity Hardening

The installer deliverable is incomplete until deterministic verification passes on a fresh install path.

Required work:

1. Fix the current `harness:runtime-parity` failure for the missing Kimi provider-api execution contract.
2. Ensure portable init includes the new harness settings schema and defaults.
3. Ensure portable verify checks:
- prompt mirrors
- runtime registry completeness
- harness settings schema/default creation
- control-plane boot
- CLI settings commands
- diagram payload generation
4. Keep the macOS app optional and out of installer critical path.
5. Document the no-app workflow clearly in setup docs.

## 9. Recommended File-Level Change Areas

Headless core:

- `packages/gg-control-plane-server/src/index.ts`
- `packages/gg-control-plane-server/src/store.ts`
- `packages/gg-control-plane-server/src/governor.ts`
- `packages/gg-cli/src/index.ts`
- `docs/setup/portable-agentic-harness-setup.md`
- `docs/runtime-profiles.md`
- `.agent/registry/mcp-runtime.json`

App:

- `apps/macos-control-surface/Sources/GGASConsole/Views/ContentView.swift`
- `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- new diagram/settings views under `Views/Tabs/`
- `apps/macos-control-surface/Sources/GGASConsole/Models/Models.swift`

Docs/artifacts:

- `docs/architecture/agentic-harness-complete-system-diagram.html`
- new richer end-user diagram artifact if needed

Tests:

- control-plane server tests for settings persistence and diagram payload
- CLI tests for `gg harness settings` commands
- macOS fixture tests for settings fetch/save and diagram hydration
- installer/portable verification tests

## 10. Risks and Mitigations

1. Risk: app-only state silently diverges from headless behavior
- Mitigation: all canonical settings served and stored by the control plane

2. Risk: diagram becomes a fragile web app inside SwiftUI
- Mitigation: keep the HTML base artifact mostly static and inject a small, typed live payload

3. Risk: installer passes structural checks but still fails at runtime
- Mitigation: add cold-start verification that exercises CLI, server, parity, and portable verify together

4. Risk: exposing too many knobs creates unsafe operator behavior
- Mitigation: validate ranges, provide reset-to-safe-defaults, and keep high-risk settings explicit

## 11. Recommendation

Implement the feature as a headless-first settings contract with app editing and visualization layered on top.

This keeps the harness portable, deterministic, and usable in three modes:

1. CLI only
2. control-plane HTTP only
3. control-plane plus macOS app

The app then becomes a better operator and explainer surface, not a hidden dependency.
