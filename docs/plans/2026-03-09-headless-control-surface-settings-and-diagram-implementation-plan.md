# Headless Control-Surface Settings and Dynamic Diagram Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add headless-canonical harness settings, an optional macOS editor and dynamic diagram tab, and finish with an installer/runtime-parity path that works without the app.

**Architecture:** Store canonical settings in the headless control plane, expose them through HTTP and `gg` CLI, and let the macOS app read/write the same contract. Render the diagram as a richer local HTML explainer with live overlay payloads from the control plane. Treat installer verification as a first-class output, including the current Kimi runtime-parity failure.

**Tech Stack:** SwiftUI, WebKit, TypeScript, Node.js HTTP server, workspace `gg` CLI, JSON schema validation, npm test/lint/build flows.

---

### Task 1: Define the canonical harness settings contract

**Files:**
- Create: `.agent/schemas/harness-settings.schema.json`
- Modify: `packages/gg-control-plane-server/src/store.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`
- Test: `packages/gg-control-plane-server/test/*`

**Step 1: Write the failing tests**

Add tests that assert:
- default settings file is created when missing
- invalid stored settings fall back to safe defaults
- persisted settings round-trip cleanly

**Step 2: Run tests to verify they fail**

Run: `npm test -- --runInBand`
Expected: FAIL because harness settings helpers and endpoints do not exist yet.

**Step 3: Write minimal implementation**

Implement:
- typed defaults
- read/validate/write helpers in the control-plane store
- settings schema file

**Step 4: Add control-plane API endpoints**

Implement:
- `GET /api/harness/settings`
- `PUT /api/harness/settings`
- `POST /api/harness/settings/reset`

**Step 5: Run tests to verify they pass**

Run: `npm test -- --runInBand`
Expected: PASS for the new settings tests.

**Step 6: Commit**

```bash
git add .agent/schemas/harness-settings.schema.json packages/gg-control-plane-server/src/store.ts packages/gg-control-plane-server/src/index.ts packages/gg-control-plane-server/test
git commit -m "feat: add headless harness settings contract"
```

### Task 2: Wire canonical settings into runtime behavior

**Files:**
- Modify: `packages/gg-control-plane-server/src/index.ts`
- Modify: `packages/gg-control-plane-server/src/governor.ts`
- Modify: `packages/gg-cli/src/index.ts`
- Test: `packages/gg-control-plane-server/test/*`

**Step 1: Write the failing tests**

Add coverage for:
- dispatch defaults pulling from stored settings
- governor snapshot using stored overrides where allowed
- CLI reading and mutating the settings file

**Step 2: Run tests to verify they fail**

Run: `npm test -- --runInBand`
Expected: FAIL because dispatch/governor/CLI still use hard-coded defaults only.

**Step 3: Write minimal implementation**

Implement:
- settings precedence model
- `gg harness settings get|set|reset`
- stored default application for loop/retry/validate/doc-sync/context/hydra/dispatch defaults

**Step 4: Keep machine safety deterministic**

Ensure:
- environment variables can still override governor-sensitive knobs
- invalid operator values are clamped and rejected clearly

**Step 5: Run verification**

Run:
- `npm run build`
- `npm test -- --runInBand`

Expected: PASS with updated CLI and control-plane behavior.

**Step 6: Commit**

```bash
git add packages/gg-control-plane-server/src/index.ts packages/gg-control-plane-server/src/governor.ts packages/gg-cli/src/index.ts packages/gg-control-plane-server/test
git commit -m "feat: wire headless settings into dispatch and governor"
```

### Task 3: Add a headless diagram payload and richer end-user HTML

**Files:**
- Modify: `packages/gg-control-plane-server/src/index.ts`
- Modify: `docs/architecture/agentic-harness-complete-system-diagram.html`
- Create: `docs/architecture/agentic-harness-dynamic-user-diagram.html`
- Test: `packages/gg-control-plane-server/test/*`

**Step 1: Write the failing tests**

Add tests that assert `/api/harness/diagram` returns:
- static architecture metadata
- current settings summary
- governor snapshot
- active run/worker graph
- degraded-state notes when parity or server state is not healthy

**Step 2: Run tests to verify they fail**

Run: `npm test -- --runInBand`
Expected: FAIL because no diagram payload endpoint exists.

**Step 3: Write minimal implementation**

Implement:
- `GET /api/harness/diagram`
- server-side payload builder
- richer HTML artifact designed for end users, not only engineers

**Step 4: Keep offline behavior safe**

Add:
- clear static rendering when live data is unavailable
- operator-readable fallback banner

**Step 5: Run verification**

Run:
- `npm run build`
- `npm test -- --runInBand`

Expected: PASS with diagram payload coverage.

**Step 6: Commit**

```bash
git add packages/gg-control-plane-server/src/index.ts docs/architecture/agentic-harness-complete-system-diagram.html docs/architecture/agentic-harness-dynamic-user-diagram.html packages/gg-control-plane-server/test
git commit -m "feat: add dynamic harness diagram payload"
```

### Task 4: Add the macOS diagram tab and settings editor

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/ContentView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/Models.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ConfigView.swift`
- Create: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/HarnessDiagramView.swift`
- Create: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/HarnessSettingsView.swift`
- Test: `apps/macos-control-surface/Tests/GGHarnessControlSurfaceTests/*`

**Step 1: Write the failing tests**

Add fixture-driven tests for:
- fetching/saving harness settings
- decoding diagram payloads
- tab rendering state when the control plane is offline

**Step 2: Run tests to verify they fail**

Run: `npm test -- --runInBand`
Expected: FAIL because the new views, models, and client methods are missing.

**Step 3: Write minimal implementation**

Implement:
- `Harness Diagram` tab registration
- typed settings/diagram API models
- `A2AClient` methods for settings and diagram endpoints
- WebKit-backed HTML render wrapper with live status overlay
- settings editor that writes only to the headless control plane

**Step 4: Preserve headless contract**

Ensure:
- no canonical harness behavior is stored only in app preferences
- existing local LM Studio/per-model settings remain clearly local-only

**Step 5: Run verification**

Run:
- `npm run macos:control-surface:build`
- `npm test -- --runInBand`

Expected: PASS for app build and new fixture tests.

**Step 6: Commit**

```bash
git add apps/macos-control-surface/Sources/GGASConsole/Views/ContentView.swift apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift apps/macos-control-surface/Sources/GGASConsole/Models/Models.swift apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ConfigView.swift apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/HarnessDiagramView.swift apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/HarnessSettingsView.swift apps/macos-control-surface/Tests/GGHarnessControlSurfaceTests
git commit -m "feat: add headless-backed harness diagram and settings tabs"
```

### Task 5: Fix installer and runtime parity

**Files:**
- Modify: `.agent/registry/mcp-runtime.json`
- Modify: `scripts/runtime-parity-smoke.mjs`
- Modify: `packages/gg-cli/src/index.ts`
- Modify: `docs/setup/portable-agentic-harness-setup.md`
- Modify: `docs/runtime-profiles.md`
- Test: `npm run harness:runtime-parity`, `npm run gg -- portable verify ...`

**Step 1: Write the failing verification target**

Capture current failure:
- `npm run harness:runtime-parity`

Expected today: FAIL on missing Kimi provider-api execution contract.

**Step 2: Write minimal implementation**

Implement:
- missing runtime registry/provider-api contract entry for Kimi
- portable initialization for harness settings defaults
- portable verify checks for settings contract and diagram payload generation

**Step 3: Run deterministic verification**

Run:
- `npm run harness:runtime-parity`
- `npm run gg -- --json doctor`
- `npm run gg -- portable verify /tmp/gg-harness-portable-check --runtime structure`

Expected: PASS or clear, actionable warnings only.

**Step 4: Update setup docs**

Document:
- headless-only usage
- optional app usage
- new settings/diagram commands
- installer verification path

**Step 5: Commit**

```bash
git add .agent/registry/mcp-runtime.json scripts/runtime-parity-smoke.mjs packages/gg-cli/src/index.ts docs/setup/portable-agentic-harness-setup.md docs/runtime-profiles.md
git commit -m "fix: harden installer and runtime parity for headless settings"
```

### Task 6: Full verification and release baseline

**Files:**
- Modify: `README.md`
- Modify: `docs/plans/2026-03-09-macos-control-surface-remediation-plan.md`
- Modify: `docs/plans/2026-03-09-headless-control-surface-settings-and-diagram-design.md`

**Step 1: Run full deterministic checks**

Run:
- `npm run build`
- `npm run lint`
- `npm test`
- `npm run harness:runtime-parity`
- `npm run macos:control-surface:build`

Expected: all commands exit `0`.

**Step 2: Perform cold-start smoke**

Run:
- `npm run control-plane:start`
- verify settings endpoints
- verify diagram endpoint
- verify app can connect without mutating headless state

**Step 3: Update user-facing docs**

Document:
- new diagram tab
- headless settings commands
- optional app editor behavior
- installer readiness notes

**Step 4: Final commit**

```bash
git add README.md docs/plans/2026-03-09-macos-control-surface-remediation-plan.md docs/plans/2026-03-09-headless-control-surface-settings-and-diagram-design.md
git commit -m "docs: document headless settings and dynamic diagram flow"
```

## Rollback Plan

### Files to Revert

- `packages/gg-control-plane-server/src/index.ts`
- `packages/gg-control-plane-server/src/store.ts`
- `packages/gg-control-plane-server/src/governor.ts`
- `packages/gg-cli/src/index.ts`
- `apps/macos-control-surface/Sources/GGASConsole/Views/ContentView.swift`
- `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- new harness settings/diagram view files
- diagram HTML artifacts

### Commands

```bash
git checkout HEAD -- packages/gg-control-plane-server/src/index.ts
git checkout HEAD -- packages/gg-control-plane-server/src/store.ts
git checkout HEAD -- packages/gg-control-plane-server/src/governor.ts
git checkout HEAD -- packages/gg-cli/src/index.ts
git checkout HEAD -- apps/macos-control-surface/Sources/GGASConsole/Views/ContentView.swift
git checkout HEAD -- apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift
```

### Validation

```bash
npm run build
npm run lint
npm test
npm run harness:runtime-parity
```

### Trigger Conditions

1. New settings contract causes dispatch or control-plane boot failures.
2. App-only state leaks into canonical headless behavior.
3. Portable verify or runtime parity regresses after implementation.
4. Diagram tab introduces macOS build instability or runtime crashes.
