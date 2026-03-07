# GG Agentic Harness

Portable agentic harness extracted from GGV3.

## Includes

- `packages/gg-core` catalog/core resolution utilities
- `packages/gg-cli` operator + automation CLI (`gg`)
- `mcp-servers/gg-skills` MCP server for skills/workflows
- `.agent` skills/workflows/rules/templates
- Harness scripts for run artifacts, context generation, and Obsidian logging

## Install

```bash
git clone https://github.com/Geargrindadmin/gg-agentic-harness.git
cd gg-agentic-harness
npm install
npm run build
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
npm run gg -- --json doctor
```

## Portable bootstrap into another repo

```bash
npm run gg -- portable init /absolute/path/to/target-repo --mode symlink
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
```
