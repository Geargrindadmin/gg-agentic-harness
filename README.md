# GG Agentic Harness

Portable agentic harness extracted from GGV3.

## Includes

- `packages/gg-core` catalog/core resolution utilities
- `packages/gg-cli` operator + automation CLI (`gg`)
- `mcp-servers/gg-skills` MCP server for skills/workflows
- `.agent` skills/workflows/rules/templates plus persona files and registries
- Harness scripts for run artifacts, persona routing, runtime parity, feedback loops, context generation, and Obsidian logging

## Install

```bash
git clone https://github.com/Geargrindadmin/gg-agentic-harness.git
cd gg-agentic-harness
npm install
npm run build
npm run harness:codex:activate
```

## Remote install into a project (one command)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/scripts/install-from-github.sh) /absolute/path/to/target-repo symlink
```

Arguments:

- arg1: target repository path (defaults to current directory)
- arg2: mode `symlink|copy` (defaults to `symlink`)

## Validate

```bash
npm run harness:codex:status
npm run gg -- --json doctor
npm run harness:runtime-parity
npm run harness:persona:audit
npm run harness:persona:benchmark
```

## Portable bootstrap into another repo

```bash
npm run gg -- portable init /absolute/path/to/target-repo --mode symlink
npm run gg -- --project-root /absolute/path/to/target-repo codex activate /absolute/path/to/target-repo
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
npm run gg -- workflow run paperclip-extracted "objective"
npm run gg -- workflow run symphony-lite "task" --validate none
npm run gg -- workflow run visual-explainer "subject" --evidence docs/README.md
npm run harness:codex:status
npm run harness:codex:activate
npm run harness:persona:audit
npm run harness:persona:benchmark
npm run harness:runtime-parity
node scripts/persona-registry-resolve.mjs --prompt "ship auth hardening" --classification TASK --json
```

## Codex activation

`gg-skills` and `filesystem` are project-scoped MCPs. A fresh install is not complete for Codex until the target project has been activated into `~/.codex`.

```bash
npm run harness:codex:activate
npm run harness:codex:status
```

Portable targets can be activated from the source harness CLI:

```bash
node packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo codex activate /absolute/path/to/target-repo
```
