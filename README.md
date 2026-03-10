# GG Agentic Harness

Portable agentic harness extracted from GGV3.

## Includes

- `packages/gg-core` catalog/core resolution utilities
- `packages/gg-cli` operator + automation CLI (`gg`)
- `mcp-servers/gg-skills` MCP server for skills/workflows
- `apps/macos-control-surface` native macOS control surface and viewer imported from the legacy GGAS repo
- `.agent` skills/workflows/rules/templates plus persona files and registries
- Harness scripts for run artifacts, persona routing, runtime parity, feedback loops, context generation, and Obsidian logging

## Multi-Model Control Plane

The harness now runs a headless control-plane server with multi-model coordinator support.

### Headless Control Plane

```bash
npm run control-plane:build
npm run control-plane:start
```

### macOS Control Surface (Optional)

The harness includes a native SwiftUI macOS app at `apps/macos-control-surface`:

```bash
npm run macos:control-surface:build
npm run macos:control-surface:run
```

### Control Plane Features

- **Run Registry**: Create, list, and inspect runs with full worker graph visibility
- **Worker Lifecycle**: Spawn, launch, terminate, retry, and retask workers
- **Swarm Steering**: Send guidance, escalate, and request child delegation
- **Message Bus**: Inbox, post, acknowledge, and event streaming
- **Worktree Manager**: Per-agent worktrees at `.agent/control-plane/worktrees/<runId>/<agentId>/`
- **Resource Governor**: Hardware-aware spawn limits with safe capacity calculation
- **Integration Settings**: MCP catalog and quality jobs

### Coordinator Selection

| Mode | Behavior |
|------|----------|
| `Auto` (default) | Selects from authenticated runtimes in preference order |
| `Pinned` | Explicit `codex`, `claude`, or `kimi` selection |

Environment variables:
- `GG_COORDINATOR_RUNTIME=codex|claude|kimi` — hard-pin the coordinator
- `GG_COORDINATOR_PREFERENCE=codex,claude,kimi` — preference order (default)

Auth discovery:
- **Codex**: `~/.codex/auth.json` → `OPENAI_API_KEY`
- **Claude**: `~/.claude/.credentials.json` → `~/.local/share/opencode/auth.json` → `ANTHROPIC_API_KEY`
- **Kimi**: `~/.kimi/credentials/kimi-code.json` → `~/.kimi/config.toml` → `MOONSHOT_API_KEY|KIMI_API_KEY`

### Key Principle

The harness remains the sole control plane. Runtimes (`codex`, `claude`, `kimi`) act as execution adapters only. Kimi may request additional workers, but the harness owns all spawn/terminate decisions.

## Architecture diagram

- Diagram source: [docs/architecture/agentic-harness-logic-loops-diagram.html](docs/architecture/agentic-harness-logic-loops-diagram.html)
- Live HTML preview: [Open rendered diagram](https://htmlpreview.github.io/?https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/docs/architecture/agentic-harness-logic-loops-diagram.html)
- External integration map source: [docs/architecture/agentic-harness-external-integration-architecture.md](docs/architecture/agentic-harness-external-integration-architecture.md)
- External integration diagram source: [docs/architecture/agentic-harness-external-integration-diagram.html](docs/architecture/agentic-harness-external-integration-diagram.html)
- External integration live preview: [Open rendered integration diagram](https://htmlpreview.github.io/?https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/docs/architecture/agentic-harness-external-integration-diagram.html)

## Priority integration wave (current plan)

- PRD update: [docs/prd/PRD-GG-CLI-PORTABLE-HARNESS.md](docs/prd/PRD-GG-CLI-PORTABLE-HARNESS.md)
- Action plan: [docs/plans/2026-03-08-priority-integrations-action-plan.md](docs/plans/2026-03-08-priority-integrations-action-plan.md)
- Architecture contract: [docs/architecture/agentic-harness-external-integration-architecture.md](docs/architecture/agentic-harness-external-integration-architecture.md)
- Addon assessment: [docs/assessments/2026-03-08-network-ai-assessment.md](docs/assessments/2026-03-08-network-ai-assessment.md)

## Install

```bash
git clone https://github.com/Geargrindadmin/gg-agentic-harness.git
cd gg-agentic-harness
npm install
npm run build
uv tool install --python python3.13 codegraphcontext
npm run harness:runtime:activate
```

Notes:

- `CodeGraphContext` is optional, but live graph-backed context requires the host `cgc` CLI.
- Verified install path on this machine: `uv tool install --python python3.13 codegraphcontext`.
- Use Python `3.10+` at minimum. On macOS, prefer Python `3.12+` so `CodeGraphContext` can use its default local database path cleanly.
- Restart Codex after `npm run harness:runtime:activate` so repo-scoped MCP changes are loaded into the active session.
- Coordinator `Auto` prefers authenticated local CLIs first, then provider-backed fallbacks, using `GG_COORDINATOR_PREFERENCE=codex,claude,kimi` unless overridden.

## Remote install into a project (one command)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/scripts/install-from-github.sh) /absolute/path/to/target-repo symlink
```

Arguments:

- arg1: target repository path (defaults to current directory)
- arg2: mode `symlink|copy` (defaults to `symlink`)

## Validate

```bash
npm run harness:runtime:status
npm run gg -- --json doctor
npm run harness:runtime-parity
npm run harness:persona:audit
npm run harness:persona:benchmark
npm run gg -- --json workflow run prompt-improver "inspect agent routing" --context-source prefer
```

## Portable bootstrap into another repo

```bash
npm run gg -- portable init /absolute/path/to/target-repo --mode symlink
npm run gg -- --project-root /absolute/path/to/target-repo runtime activate /absolute/path/to/target-repo --runtime codex
npm run gg -- portable verify /absolute/path/to/target-repo --runtime structure
```

Or local installer script:

```bash
./scripts/install-from-github.sh /absolute/path/to/target-repo symlink
```

## Key Commands

### CLI and Workflows

```bash
# List available capabilities
npm run gg -- skills list
npm run gg -- workflow list

# Workflow execution
npm run gg -- workflow run go "ship auth hardening" --prompt-improver auto
npm run gg -- workflow run paperclip-extracted "objective"
npm run gg -- workflow run prompt-improver "fix the login bug"
npm run gg -- workflow run symphony-lite "task" --validate none
npm run gg -- workflow run visual-explainer "subject" --mode diff-review --evidence .agent/runs/latest.json
npm run gg -- workflow run full-doc-update "task summary"
npm run gg -- workflow run hydra-sidecar "evaluate auth hardening route" --hydra-mode shadow --internet-evidence "OWASP ASVS 2025-01-15,https://owasp.org/www-project-application-security-verification-standard/"
npm run gg -- workflow show network-ai-pilot
```

### Runtime and Control Plane

```bash
# Runtime adapter management
npm run harness:runtime:activate    # Activate default runtime (codex)
npm run harness:runtime:status      # Check runtime adapter status
npm run harness:runtime-parity      # Verify cross-runtime parity

# Control plane
npm run control-plane:build         # Build headless control plane
npm run control-plane:start         # Start headless control plane server
npm run control-plane:dev           # Build and start in one command

# macOS control surface (optional)
npm run macos:control-surface:build
npm run macos:control-surface:run
```

### Persona and Registry

```bash
npm run harness:persona:audit       # Validate persona registry
npm run harness:persona:benchmark   # Benchmark persona routing
npm run harness:persona:sync        # Sync persona files with registry

# Resolve personas for a task
node scripts/persona-registry-resolve.mjs --prompt "ship auth hardening" --classification TASK --json

# Resolve with compound persona detection
node scripts/persona-registry-resolve.mjs --prompt "implement oauth login" --classification CRITICAL --json
```

### Validation and Diagnostics

```bash
npm run gg -- doctor                # Run harness doctor
npm run gg -- --json doctor         # JSON output for automation
npm run harness:lint                # Run harness lint
npm run harness:project-context     # Regenerate project context
npm run harness:project-context:check  # Check context freshness
```

## Runtime activation

The harness is model-agnostic, but some runtimes require host-level activation for repo-scoped MCPs. In Codex, `gg-skills` and `filesystem` are project-scoped and must be activated in `~/.codex`.

```bash
npm run harness:runtime:activate
npm run harness:runtime:status
```

You can target a runtime explicitly:

```bash
node scripts/runtime-project-sync.mjs activate . --runtime codex
node scripts/runtime-project-sync.mjs status . --runtime codex
```

Portable targets can be activated from the source harness CLI with runtime adapters:

```bash
node packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo runtime activate /absolute/path/to/target-repo --runtime codex
```

## Coordinator Selection

The coordinator can be chosen in two ways:

1. `Auto` (recommended): the harness selects the coordinator from authenticated runtimes in preference order.
2. `Pinned`: the operator selects `codex`, `claude`, or `kimi`.

Selection policy:

1. `GG_COORDINATOR_RUNTIME=<codex|claude|kimi>` hard-pins the coordinator for headless/server launches.
2. Otherwise the harness uses `GG_COORDINATOR_PREFERENCE`, default `codex,claude,kimi`.
3. The harness prefers a runtime with an authenticated local CLI session.
4. If no local CLI session is available, it falls back to authenticated provider credentials where supported.
5. Sub-agents remain harness-managed regardless of the coordinator choice.

Auth discovery order:

- `codex`: `~/.codex/auth.json` -> `OPENAI_API_KEY`
- `claude`: `~/.claude/.credentials.json` -> `~/.local/share/opencode/auth.json` -> `ANTHROPIC_API_KEY`
- `kimi`: `~/.kimi/credentials/kimi-code.json` -> `~/.kimi/config.toml` -> `MOONSHOT_API_KEY|KIMI_API_KEY`
