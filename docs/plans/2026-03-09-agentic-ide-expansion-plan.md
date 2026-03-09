# Agentic IDE Expansion Plan

Date: 2026-03-09
Repo: `gg-agentic-harness`
Scope: macOS control surface evolution into an Agentic IDE

## Goal

Turn the current macOS control surface into a real local Agentic IDE:

- left side: harness navigation and operating surfaces
- center: multi-tab file editor and diff-aware document viewer
- bottom center: integrated CLI terminal sessions, similar to VS Code
- right side: tabbed IDE rail for explorer, context, extensions, and future agent tools

The harness must remain the control plane. The IDE is an operator and developer surface over the same run graph, worker orchestration, worktrees, and telemetry.

## Current State

Already implemented:

- planner-first app shell
- swarm telemetry and worktree awareness
- right-side IDE rail
- workspace/run explorer
- center multi-tab file viewer
- markdown rendering using `swift-markdown-ui`
- basic file-to-file diff mode when a workspace/run counterpart exists

Still missing:

- editable buffers
- save/reload/dirty-state handling
- bottom integrated terminal sessions under the editor
- agent-aware edit/patch flows
- source control and change review surfaces
- diagnostics and problem list
- richer telemetry and file-aware worker actions

## User Workflow Target

The core workflow should become:

1. User plans work in `Planner`
2. User launches a coordinator and worker team
3. User watches swarm activity in `Swarm`
4. User opens worktree or workspace files in the editor
5. User opens one or more terminal sessions below the editor
6. User compares worker output against workspace files
7. User steers workers directly from the IDE context
8. User reviews diffs, patches, and telemetry without leaving the app

## Architecture Direction

### 1. Three-Zone IDE Shell

- Left sidebar:
  - planner
  - swarm
  - analytics
  - run/history/log/config tabs
- Center workspace:
  - multi-tab editor/viewer
  - diff mode
  - bottom terminal dock
- Right rail:
  - explorer
  - context
  - extensions
  - future SCM / problems / search / agent actions

### 2. Editor Model

Add a true editor state model, not just preview state.

Required state:

- open tabs
- active tab
- file source
  - workspace
  - selected run worktree
  - explicit worker worktree
- dirty state
- read-only vs editable state
- related counterpart path
- active diff mode

### 3. Bottom Terminal Dock

Add a bottom split panel below the file viewer.

Required behaviors:

- multiple terminal tabs
- new CLI session button
- per-tab runtime label
- persistent PTY-backed sessions
- resizable height
- show/hide toggle
- attach session to:
  - workspace root
  - selected run root
  - selected worker worktree

### 4. Agent-Aware Terminal Semantics

Terminals must understand harness context.

Session types:

- `workspace shell`
- `run shell`
- `worker shell`
- `provider CLI shell`
  - `codex`
  - `claude`
  - `kimi`
  - later `qwen`, `glm`, `deepseek`, `gemini`

Desired defaults:

- if launched from selected worker: cwd = worker worktree
- if launched from selected run: cwd = run worktree root
- if launched from workspace: cwd = project root

Future enhancement:

- prebuild a command launcher for authenticated CLI sessions so the user can open a runtime-specific shell without re-entering setup

## Implementation Phases

### Phase 1: Bottom Terminal Dock

Objective:
- move terminal functionality into the editor workspace

Tasks:

- create `IDEBottomPanelState`
- embed a vertical split in `IDEWorkspaceView`
- reuse `SwiftTerm`-backed terminal tabs below the editor
- add:
  - new terminal tab
  - new shell tab
  - close terminal tab
  - hide/show dock
  - resize dock
- route sessions by context:
  - workspace
  - selected run
  - selected worker

Acceptance:

- user can open files in center and terminals below without leaving the IDE shell
- switching editor tabs does not destroy terminal sessions

### Phase 2: Real Editor State

Objective:
- move from preview to editable documents

Tasks:

- add editable text buffers
- detect dirty state
- add save / revert / reload
- lock read-only mode for non-text files
- support markdown edit/render toggle
- preserve open tabs across navigation

Acceptance:

- user can edit workspace files locally inside the app
- diff mode remains available for workspace/run comparisons

### Phase 3: Patch and Diff Workflows

Objective:
- make worker output reviewable and actionable

Tasks:

- diff workspace file vs worker counterpart
- diff current buffer vs saved file
- add patch summary headers
- add:
  - copy patch
  - reveal counterpart
  - accept local changes
  - discard local edits

Future:

- partial hunk apply/reject

### Phase 4: Agent-Aware File Actions

Objective:
- tie the editor to the swarm and planner

Tasks:

- open all files changed by selected worker
- open all files related to selected run
- open counterpart file automatically from swarm node
- expose worker context in file header
- add quick actions:
  - message worker about this file
  - retask worker on this file
  - open worker terminal in this worktree

Acceptance:

- file viewer is no longer isolated from swarm operations

### Phase 5: Diagnostics and Problems

Objective:
- add developer feedback loops

Tasks:

- add `Problems` panel
- parse:
  - TypeScript diagnostics
  - lint output
  - test failures
  - run/blocker events
- make diagnostics clickable to open file tabs

### Phase 6: SCM and Change Review

Objective:
- expose repo change state inside the IDE

Tasks:

- add SCM tab in the right rail
- show modified/untracked files
- group changes by workspace vs worker worktree
- open staged/unified diff in center pane
- later add commit and review helpers

### Phase 7: Search and Command Surfaces

Objective:
- make the IDE navigable at scale

Tasks:

- add workspace file search
- add content grep search
- add command palette
- add recent files / recent runs / recent workers

### Phase 8: Extension and Tool Surfaces

Objective:
- make the right rail extensible

Tasks:

- evolve `Extensions` tab from placeholder to managed surface
- add plugin cards
- expose installed skills/tools/workflows
- allow opening skill docs and workflow docs in editor tabs

## Bottom Terminal Dock Design

Recommended UI:

- bottom dock spans only the center workspace area
- top of dock:
  - terminal tabs
  - `+` new session
  - session scope picker
  - hide button
- body:
  - active PTY terminal
- optional future split:
  - terminal
  - output / problems

Recommended session scopes:

- `Workspace`
- `Selected Run`
- `Selected Worker`
- `Provider CLI`

Recommended terminal presets:

- `Shell`
- `jcode`
- `Codex CLI`
- `Claude CLI`
- `Kimi CLI`

## Additional Features Worth Adding

High value:

- file breadcrumbs in editor header
- pinned tabs
- recent files
- problem markers in file tree
- unsaved indicator on tabs
- open file from swarm node double-click
- worker ownership badge in file header
- file-lock awareness in editor

Medium value:

- minimap for source viewer
- markdown side-by-side preview
- structured trace viewer in editor tab
- package README preview in center pane
- inline telemetry badge for selected run

Longer term:

- firewire/network split-model workstation manager
- multi-machine worktree browsing
- collaborative run review mode
- command palette-driven agent task creation
- editor-integrated patch apply from worker proposals

## Risks

- terminal dock can complicate focus and keyboard routing
- editable buffers require careful save semantics to avoid stomping worker outputs
- workspace vs run worktree comparisons need explicit labels so users do not confuse sources
- too many side panels can overwhelm the operator workflow if not kept progressive

## Recommendation

Build next in this order:

1. bottom terminal dock
2. editable buffer state
3. diff/patch actions
4. agent-aware file actions
5. problems/SCM/search

That sequence turns the current viewer into a real local IDE without destabilizing the existing planner/swarm workflow.
