# GG Agentic Harness

Portable agentic harness extracted from GGV3.

## Includes

- `packages/gg-core` catalog/core resolution utilities
- `packages/gg-cli` operator + automation CLI (`gg`)
- `mcp-servers/gg-skills` MCP server for skills/workflows
- `apps/macos-control-surface` native macOS control surface and viewer imported from the legacy GGAS repo
- `.agent` skills/workflows/rules/templates plus persona files and registries
- Harness scripts for run artifacts, persona routing, runtime parity, feedback loops, context generation, and Obsidian logging

## macOS control surface

The harness now carries a native SwiftUI macOS app at `apps/macos-control-surface`.

Headless control plane:

```bash
npm run control-plane:build
npm run control-plane:start
```

Build it with:

```bash
npm run macos:control-surface:build
```

Open the freshly built bundle from `.dist` with:

```bash
npm run macos:control-surface:run
```

Install or replace the app copy in `~/Applications` or `/Applications` with:

```bash
npm run macos:control-surface:install
```

Install and launch the replaced app with:

```bash
npm run macos:control-surface:run-installed
```

Current scope:

- the harness now exposes a native headless control-plane server at `packages/gg-control-plane-server`
- the macOS app is an optional client over the same HTTP control plane
- the macOS app now includes a `Harness` tab for live architecture visualization plus headless-backed harness settings
- the `Harness` tab now shows control-plane connection state, saves into `.agent/control-plane/server/harness-settings.json`, and makes it explicit that changes affect new runs only
- coordinator runtime selection is `Auto` by default, with explicit `Codex`, `Claude`, and `Kimi` pinning available in the dispatch surface
- swarm steering, run/bus status, worktree browsing, and hardware-governed queueing are wired into the harness-native server
- sub-agents get dedicated worktrees under `.agent/control-plane/worktrees/<runId>/<agentId>`
- Kimi remains harness-controlled: it can request delegation, but the harness owns spawn/terminate policy
- canonical harness policy now lives in `.agent/control-plane/server/harness-settings.json`, not in the app

## Architecture diagram

- Dynamic user diagram source: [docs/architecture/agentic-harness-dynamic-user-diagram.html](docs/architecture/agentic-harness-dynamic-user-diagram.html)
- Dynamic user diagram live preview: [Open rendered dynamic diagram](https://htmlpreview.github.io/?https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/docs/architecture/agentic-harness-dynamic-user-diagram.html)
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
- Headless harness settings are created automatically on first run at `.agent/control-plane/server/harness-settings.json`.

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
npm run gg -- harness settings get
npm run gg -- harness diagram --format json
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

## Key commands

```bash
npm run gg -- skills list
npm run gg -- workflow list
npm run gg -- workflow run go "ship auth hardening" --prompt-improver auto
npm run gg -- workflow run paperclip-extracted "objective"
npm run gg -- workflow run prompt-improver "fix the login bug"
npm run gg -- workflow run symphony-lite "task" --validate none
npm run gg -- workflow run visual-explainer "subject" --mode diff-review --evidence .agent/runs/latest.json
npm run gg -- workflow run full-doc-update "task summary"
npm run gg -- workflow run hydra-sidecar "evaluate auth hardening route" --hydra-mode shadow --internet-evidence "OWASP ASVS 2025-01-15,https://owasp.org/www-project-application-security-verification-standard/"
npm run gg -- workflow show network-ai-pilot
npm run gg -- harness settings get
npm run gg -- harness settings set --key execution.loopBudget --value 32
npm run gg -- harness settings reset
npm run gg -- harness diagram --format html
npm run harness:runtime:status
npm run harness:runtime:activate
npm run control-plane:start
npm run harness:persona:audit
npm run harness:persona:benchmark
npm run harness:runtime-parity
node scripts/persona-registry-resolve.mjs --prompt "ship auth hardening" --classification TASK --json
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

Portable targets also inherit the headless harness settings contract and the dynamic user diagram:

```bash
node packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo harness settings get
node packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo harness diagram --format json
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
