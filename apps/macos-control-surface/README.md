# GG Agentic Harness Control Surface — macOS App

> Native SwiftUI macOS application imported into `gg-agentic-harness`.
> Serves as a local control surface and viewer for harness runs, logs, skills, traces, and runtime state.

## What it is

A unified dashboard that combines:
- harness operator tabs for run history, logs, skill analytics, dispatch, trace, config, and model/runtime control
- local viewer surfaces for worktree/task state plus optional GG Forge data from `~/.ggas/forge/forge.db`

This app was imported from the legacy `GearGrind-Agentic-System` repo. Some setup/bridge actions still assume services that have not been fully migrated into `gg-agentic-harness` yet. The viewer/operator surfaces and the hardware topology gate are present now; deeper backend rewiring remains follow-up integration work.

## Requirements

- macOS 14.0 (Sonoma) or later  
- Swift 5.9+ (`xcode-select --install`)
- harness-compatible API services running on `:7891` for the ops tabs that query the A2A/control-plane APIs
- GG Forge app launched at least once to create `~/.ggas/forge/forge.db`

## Build & Run

```bash
npm run macos:control-surface:bundle
open apps/macos-control-surface/.dist/GGHarnessControlSurface.app
```

To replace an already installed app copy in `~/Applications` or `/Applications`:

```bash
npm run macos:control-surface:install
```

To replace the installed copy and launch it immediately:

```bash
npm run macos:control-surface:run-installed
```

Or open in Xcode:
```bash
open Package.swift
```

The app is designed around a planner-first workflow:
- `Planner` is the primary launch surface and is organized as `Coordinator`, `Agent Team`, and `Work Intent`.
- `Work Intent` changes the objective only; it does not silently rewrite the deployed team unless the user explicitly applies a suggested team.
- `Swarm`, `Console`, and `Live Log` follow the currently selected planner task/run.
- `Agent Analytics` reports coordinator usage, worker runtime mix, and persona invocation counts from the harness run graph.
- `Swarm` exposes selected-run telemetry, selected-worker runtime/persona details, and direct worktree inspection.
- `Replays` renders local Claude Code and Cursor transcript sessions into readable replay pages.
- `Model Fit` uses local `llmfit` analysis to recommend which coding models fit the current machine and can hand off into the LM Studio browser.
- `Free Models` exposes the vendored free-provider catalog and can hand off model searches into LM Studio.
- `Harness` shows a live control-plane badge, the dynamic architecture diagram, and headless-backed settings that save to `.agent/control-plane/server/harness-settings.json`.
- the headless harness remains the source of truth; the mac app is an operator surface, not a separate control plane.

## Package as .dmg (distribute to teammates)

```bash
swift build -c release

# Option A: simple drag-to-Applications .dmg
mkdir -p /tmp/dmg-stage
cp -R .build/release/GGHarnessControlSurface.app /tmp/dmg-stage/
hdiutil create -volname "GG Agentic Harness Control Surface" \
  -srcfolder /tmp/dmg-stage \
  -ov -format UDZO \
  GGHarnessControlSurface.dmg

echo "✅ GGHarnessControlSurface.dmg ready"
```

No Apple Developer account needed for internal distribution.

## Architecture

```
GGASConsoleApp.swift          @main entry point
├── ContentView.swift         NavigationSplitView + sidebar
│
├── Services/
│   ├── A2AClient.swift       REST client → harness control-plane :7891
│   └── ForgeStore.swift      GRDB reader → ~/.ggas/forge/forge.db
│
├── Models/
│   └── Models.swift          AgentRun, LogLine, SkillStats, ForgeTask, ForgeNote
│
└── Views/
    ├── Components/
    │   └── SharedComponents.swift   StatusDot, StatBadge
    └── Tabs/
        ├── RunHistoryView.swift     GET /api/runs  (polls 5s)
        ├── LiveLogView.swift        GET /api/logs  (polls 2s)
        ├── SkillAnalyticsView.swift GET /api/skill-stats
        ├── AgentAnalyticsView.swift GET /api/agent-analytics
        ├── DispatchView.swift       POST /api/dispatch
        ├── TraceView.swift          GET /api/runs/:id/trace
        ├── TasksView.swift          GRDB → tasks table
        ├── NotesView.swift          GRDB → notes table
        └── ConfigView.swift         Health ping + env info
```

## vs. Web Console

| | Web Console (`apps/agent-console`) | macOS App (`apps/macos-control-surface`) |
|---|---|---|
| Access | `localhost:7070` in any browser | Native macOS `.app` in Dock |
| Deployment | Docker / GCP Cloud Run | Local only |
| GG Forge tasks | ❌ | ✅ (GRDB read) |
| GG Forge notes | ❌ | ✅ (GRDB read) |
| DMG distributable | ❌ | ✅ |

Both connect to the same harness control-plane backend — they're complementary, not replacements.

## References

- SwiftUI libraries reference for future control-surface enhancements:
  `https://github.com/Toni77777/awesome-swiftui-libraries`
