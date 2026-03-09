# External Intelligence Integrations Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate `claude-replay`, `llmfit`, and `free-coding-models` into `gg-agentic-harness` as harness-backed services and macOS app surfaces, while clarifying Planner UX around coordinator, agent team, and work intent.

**Architecture:** The headless control plane remains the source of truth. External repos are vendored under `third-party/` and accessed through harness-owned adapters/endpoints. The macOS app consumes those endpoints and presents them as logical operator surfaces: `Planner`, `Swarm`, `Agent Analytics`, `Replays`, `Model Fit`, and `Free Models`. `Work Intent` remains separate from `Agent Team`, and the coordinator selection remains explicit and harness-owned.

**Tech Stack:** Node/TypeScript control plane, SwiftUI/AppKit macOS app, vendored ESM modules from `claude-replay`, local CLI integration for `llmfit`, local Node integration for `free-coding-models`.

**Current Status:** Initial implementation is live in `gg-agentic-harness`.
- `claude-replay` is wrapped by control-plane replay endpoints and surfaced in the macOS `Replays` tab.
- `llmfit` is wrapped by control-plane fit endpoints and surfaced in the `Model Fit` tab with LM Studio handoff.
- `free-coding-models` is wrapped by control-plane catalog endpoints and surfaced in the `Free Models` tab.
- Planner now separates `Coordinator`, `Agent Team`, and `Work Intent`, with explicit suggested-team application.

---

## Integration Targets

### `claude-replay`

**What to reuse**
- `src/parser.mjs`
- `src/renderer.mjs`
- `src/extract.mjs`

**Harness use**
- List transcript files from known sources
- Parse transcript metadata and preview turn counts
- Render self-contained replay HTML on demand
- Support rereading and sharing conversations from the mac app

**Do not reuse**
- Their CLI as the primary integration surface

### `llmfit`

**What to reuse**
- Local `llmfit` binary if installed
- REST/CLI contract for recommendations and system fit
- Model metadata and “top runnable models” semantics

**Harness use**
- Query local system fit recommendations
- Feed “fits this machine” results into model selection and LM Studio download suggestions
- Provide a dedicated `Model Fit` view

**Do not reuse**
- Their TUI or desktop shell

### `free-coding-models`

**What to reuse**
- Provider/model catalog in `sources.js`
- Provider metadata in `src/provider-metadata.js`
- Discovery/analysis helpers where directly usable

**Harness use**
- Show free-model provider availability, tier, context, scores, and provider metadata
- Create a dedicated `Free Models` page for users
- Use its catalog to enrich language model selection

**Do not reuse**
- Their terminal UI or proxy launch behavior as-is

---

## UX Reorganization

### Planner

Rename and clarify the major sections:

1. `Coordinator`
- Explicit card selector for the lead model/runtime
- This selection owns the run and launches all workers

2. `Agent Team`
- Sub-agent model
- Single vs team
- Role boxes
- Advanced worker options

3. `Work Intent`
- `Code Review`, `Write Tests`, `Debug`, `Refactor`, `Docs`, `Security`
- These change the objective/prompt, not the team automatically
- Each card should show:
  - `Changes prompt only`
  - optional `Suggested team`
  - optional `Apply Suggested Team`

4. `Kanban`
- Task cards launch with the current `Coordinator + Agent Team + Work Intent`
- Task run status continues to drive board movement

### New Tabs / Surfaces

1. `Replays`
- Browse recent transcript sessions
- Inspect metadata
- Open rendered replay HTML in-app

2. `Model Fit`
- Show llmfit recommendations for this machine
- Highlight “downloadable in LM Studio”
- Drive better coordinator/sub-agent suggestions

3. `Free Models`
- Show current free model catalog by provider
- Expose tier, score, context, free-tier/provider notes
- Provide filters by provider, tier, coding score, and context

### Existing Tabs

1. Keep `Planner` and `Swarm` at the top of the navigation
2. Keep diagnostics lower in the stack
3. Ensure styling matches Planner’s card language across new tabs

---

## Control Plane Additions

### Replay Endpoints

Add:
- `GET /api/replays/sources`
- `GET /api/replays/sessions`
- `POST /api/replays/render`
- `GET /api/replays/file?path=...`

Behavior:
- Enumerate transcript roots
- Return session metadata: source, path, modified time, size, detected format, turn count
- Render replay HTML into a harness-owned cache/output directory

### Model Fit Endpoints

Add:
- `GET /api/model-fit/system`
- `GET /api/model-fit/recommendations`

Behavior:
- Prefer local `llmfit` binary
- Use JSON output or `llmfit serve`-style data shape
- Return whether a model fits this machine and whether it likely maps to LM Studio download candidates

### Free Models Endpoints

Add:
- `GET /api/free-models/providers`
- `GET /api/free-models/catalog`

Behavior:
- Read vendor catalog and provider metadata
- Normalize fields for the mac app
- Return static catalog data immediately; later add live checks if useful

### LM Studio Mapping Endpoint

Add:
- `GET /api/model-fit/lmstudio-candidates`

Behavior:
- Intersect `llmfit` “fit” results with LM Studio downloadable model candidates
- Return `availableForDownload` rows used by the LM Studio manager

---

## Task Breakdown

### Task 1: Plan and vendor structure

**Files:**
- Create: `docs/plans/2026-03-09-external-intelligence-integrations-plan.md`
- Create: `third-party/claude-replay/`
- Create: `third-party/llmfit/`
- Create: `third-party/free-coding-models/`

**Step 1: Confirm vendor locations**
- Ensure the repos live under `third-party/`

**Step 2: Document what is reused vs wrapped**
- Keep the control plane as the source of truth

**Step 3: Commit after scaffolding**

### Task 2: Clarify Planner intent vs team

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/TasksView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/CoordinatorManager.swift`

**Step 1: Rename preset section to `Work Intent`**

**Step 2: Add explanatory UI copy**
- Presets change the objective, not the team automatically

**Step 3: Add suggested team metadata**
- Cards expose suggested roles
- Add `Apply Suggested Team`

### Task 3: Build replay integration service

**Files:**
- Create: `packages/gg-control-plane-server/src/replays.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Step 1: Wrap `claude-replay` parser/renderer directly**

**Step 2: Add transcript source discovery**
- Start with Claude Code and Cursor transcript roots
- Add extension points for Codex/Kimi later

**Step 3: Add render/cache output**

### Task 4: Build llmfit integration service

**Files:**
- Create: `packages/gg-control-plane-server/src/model-fit.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Step 1: Detect `llmfit` binary**

**Step 2: Query recommendations and system info**

**Step 3: Normalize fit rows for the mac app**

**Step 4: Add LM Studio candidate mapping**

### Task 5: Build free-models catalog service

**Files:**
- Create: `packages/gg-control-plane-server/src/free-models.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Step 1: Import/normalize provider catalog**

**Step 2: Import provider metadata**

**Step 3: Expose app-friendly JSON**

### Task 6: Add macOS app tabs and models

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/ContentView.swift`
- Create: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ReplaysView.swift`
- Create: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/ModelFitView.swift`
- Create: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/FreeModelsView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Services/A2AClient.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/Models.swift`

**Step 1: Add models/endpoints to the app client**

**Step 2: Add new tabs and navigation order**

**Step 3: Match Planner visual style**

### Task 7: Hook LM Studio and selection flow

**Files:**
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Views/Tabs/LMStudioManagerView.swift`
- Modify: `apps/macos-control-surface/Sources/GGASConsole/Models/LMStudioEngine.swift`

**Step 1: Surface fit-backed “available for download” recommendations**

**Step 2: Link model-fit recommendations into model selection**

### Task 8: Verification

**Files:**
- Modify tests under `apps/macos-control-surface/Tests/GGHarnessControlSurfaceTests/`
- Add server tests where practical

**Step 1: Add deterministic endpoint/client tests**

**Step 2: Run**
- `swift test`
- `npm run macos:control-surface:build`
- `npm run build`
- `npm test`

---

## Immediate First Slice

Implement now:

1. Planner clarification:
- Rename presets to `Work Intent`
- Add suggested team metadata and explicit apply behavior

2. Server scaffolding:
- Add `replays.ts`
- Add `model-fit.ts`
- Add `free-models.ts`

3. App scaffolding:
- Add tab enums and initial views
- Add A2A client models/endpoints

Later slices:
- HTML replay preview in-app
- LM Studio “downloadable fit” mapping
- richer free-model availability state
