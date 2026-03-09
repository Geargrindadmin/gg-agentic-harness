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
cd apps/macos-control-surface
swift build -c release
./.build/release/GGHarnessControlSurface
```

Or open in Xcode:
```bash
open Package.swift
```

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
│   ├── A2AClient.swift       REST client → gg-a2a-server :7891
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

Both connect to the same `gg-a2a-server` backend — they're complementary, not replacements.
