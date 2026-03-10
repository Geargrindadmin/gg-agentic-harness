# Multi-Model Control Plane Usage Guide

> **Version:** 1.0  
> **Date:** 2026-03-09

---

## Quick Start

### 1. Install and Activate

```bash
# Clone and install
git clone https://github.com/Geargrindadmin/gg-agentic-harness.git
cd gg-agentic-harness
npm install
npm run build

# Activate runtime adapter (Codex example)
npm run harness:runtime:activate

# Verify activation
npm run harness:runtime:status
```

**Note:** Restart Codex after activation so the active session loads repo-scoped MCP changes.

### 2. Start the Control Plane

```bash
# Start headless control plane server
npm run control-plane:start

# Or build + start in one command
npm run control-plane:dev
```

The control plane exposes an HTTP API at `http://localhost:3000` by default.

### 3. Verify Everything Works

```bash
# Full system check
npm run harness:runtime-parity

# Persona registry validation
npm run harness:persona:audit

# Doctor check
npm run gg:doctor
```

---

## Runtime Selection

### Auto Mode (Recommended)

The harness automatically selects the best available runtime:

```bash
# Default preference order: codex,claude,kimi
export GG_COORDINATOR_PREFERENCE="codex,claude,kimi"

# Run with auto-selection
npm run gg -- workflow run go "implement feature X"
```

Selection priority:
1. Runtime with authenticated local CLI session
2. Runtime with authenticated provider credentials
3. First runtime in preference order (fail at preflight if no credentials)

### Pinned Mode

Explicitly pin the coordinator runtime:

```bash
# Pin to specific runtime
export GG_COORDINATOR_RUNTIME="claude"

# Or use CLI flag
npm run gg -- workflow run go "task" --runtime claude
```

### Runtime-Specific Setup

#### Codex

```bash
# Requires OpenAI credentials
export OPENAI_API_KEY="sk-..."
# Or use ~/.codex/auth.json

# Activate for this repo
npm run harness:runtime:activate -- --runtime codex
```

#### Claude

```bash
# Requires Anthropic credentials
export ANTHROPIC_API_KEY="sk-ant-..."
# Or use ~/.claude/.credentials.json

# No host activation needed
npm run harness:runtime:status -- --runtime claude
```

#### Kimi

```bash
# Requires Moonshot credentials
export MOONSHOT_API_KEY="..."
# Or use ~/.kimi/credentials/kimi-code.json

# Verify CLI or API access
npm run harness:runtime:status -- --runtime kimi
```

---

## Persona Routing

### Resolve Personas for a Task

```bash
# Resolve which personas should handle a task
node scripts/persona-registry-resolve.mjs \
  --prompt "implement user authentication" \
  --classification TASK \
  --json
```

Output:
```json
{
  "primary": "orchestrator",
  "collaborators": ["backend-specialist", "security-auditor", "test-engineer"],
  "compoundPersona": "compound:auth-hardening:v1",
  "confidence": 0.95
}
```

### Available Personas

**Builders:**
- `backend-specialist` — APIs, services, validation
- `frontend-specialist` — UI components, React, CSS
- `database-architect` — Schema, migrations, queries
- `devops-engineer` — CI/CD, deployment, infrastructure
- `mobile-developer` — React Native, Flutter
- `game-developer` — Unity, Godot, gameplay
- `debugger` — Root cause analysis, incident fixes
- `performance-optimizer` — Profiling, Core Web Vitals
- `seo-specialist` — Metadata, indexability

**Reviewers:**
- `test-engineer` — Unit tests, coverage, TDD
- `qa-automation-engineer` — E2E tests, Playwright
- `security-auditor` — Security review, threat analysis
- `penetration-tester` — Offensive security testing

**Planners:**
- `project-planner` — Task breakdown, milestones
- `product-manager` — Requirements, acceptance criteria
- `product-owner` — Roadmap, prioritization
- `documentation-writer` — Docs, runbooks, specs

**Scouts:**
- `explorer-agent` — Codebase discovery
- `code-archaeologist` — Legacy code analysis

**Coordinators:**
- `orchestrator` — Multi-agent coordination

### Compound Personas

For complex tasks, use compound personas that coordinate multiple specialists:

```bash
# Auth hardening (orchestrator + backend + security + test + frontend)
npm run gg -- workflow run go "harden authentication flow"

# Payment reliability (orchestrator + backend + security + database + test)
npm run gg -- workflow run go "fix payment retry logic"

# Incident response (orchestrator + debugger + devops + security + test)
npm run gg -- workflow run go "investigate production outage"
```

---

## Workflow Commands

### Standard Workflows

```bash
# General task execution with planning
npm run gg -- workflow run go "implement feature"

# One-shot autonomous task
npm run gg -- workflow run symphony-lite "fix typo in readme"

# Intake triage and routing
npm run gg -- workflow run paperclip-extracted "objective"

# Prompt improvement/normalization
npm run gg -- workflow run prompt-improver "vague request"

# Visual explanation generation
npm run gg -- workflow run visual-explainer "subject" --mode diff-review

# Post-task documentation sync
npm run gg -- workflow run full-doc-update "task summary"

# Hydra sidecar evaluation
npm run gg -- workflow run hydra-sidecar "evaluate route" --hydra-mode shadow
```

### Skills and Discovery

```bash
# List available skills
npm run gg -- skills list

# List available workflows
npm run gg -- workflow list

# Show workflow details
npm run gg -- workflow show go
```

---

## Control Plane API

### Create a Run

```bash
curl -X POST http://localhost:3000/api/v1/runs \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "implement user auth",
    "classification": "TASK",
    "runtime": "auto"
  }'
```

### Spawn a Worker

```bash
curl -X POST http://localhost:3000/api/v1/runs/{runId}/spawn \
  -H "Content-Type: application/json" \
  -d '{
    "persona": "backend-specialist",
    "task": "Implement login endpoint"
  }'
```

### Check Run Status

```bash
curl http://localhost:3000/api/v1/runs/{runId}
```

### List Worktrees

```bash
curl http://localhost:3000/api/v1/worktrees
```

---

## macOS Control Surface

### Build and Run

```bash
# Build the macOS app
npm run macos:control-surface:build

# Run the macOS app
npm run macos:control-surface:run
```

### Features

- **Dispatch View:** Create and monitor runs
- **Swarm View:** Visualize active workers
- **Worktree Panel:** Browse allocated worktrees
- **Live Log:** Real-time worker output
- **Config View:** Runtime and coordinator settings

---

## Portable Installation

### Install into Another Repository

```bash
# One-command remote install
bash <(curl -fsSL https://raw.githubusercontent.com/Geargrindadmin/gg-agentic-harness/main/scripts/install-from-github.sh) /path/to/target-repo symlink

# Or use the CLI
npm run gg -- portable init /path/to/target-repo --mode symlink
npm run gg -- --project-root /path/to/target-repo runtime activate /path/to/target-repo --runtime codex
```

### Verify Portable Install

```bash
npm run gg -- portable verify /path/to/target-repo --runtime structure
```

---

## Troubleshooting

### Runtime Activation Issues

```bash
# Check current status
npm run harness:runtime:status

# Re-activate
npm run harness:runtime:activate

# Check for missing credentials
cat ~/.codex/auth.json  # Codex
cat ~/.claude/.credentials.json  # Claude
cat ~/.kimi/credentials/kimi-code.json  # Kimi
```

### Persona Routing Issues

```bash
# Validate registry
npm run harness:persona:audit

# Test resolution
node scripts/persona-registry-resolve.mjs --prompt "test" --classification TASK --json

# Check benchmark scores
npm run harness:persona:benchmark
```

### Control Plane Issues

```bash
# Check if server is running
curl http://localhost:3000/api/v1/health

# Restart control plane
npm run control-plane:dev

# Check logs
# Logs are emitted to stdout/stderr by the control plane server
```

### Worktree Issues

```bash
# Clean up orphaned worktrees
bd prime --json

# Check worktree status
ls -la .agent/control-plane/worktrees/

# Manual cleanup (if needed)
rm -rf .agent/control-plane/worktrees/{runId}
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GG_COORDINATOR_RUNTIME` | Pin coordinator runtime | (auto) |
| `GG_COORDINATOR_PREFERENCE` | Runtime preference order | `codex,claude,kimi` |
| `OPENAI_API_KEY` | Codex API key | — |
| `ANTHROPIC_API_KEY` | Claude API key | — |
| `MOONSHOT_API_KEY` | Kimi/Moonshot API key | — |
| `HARNESS_RESERVED_RAM_GB` | Override RAM reservation | (calculated) |
| `GG_CONTROL_PLANE_PORT` | Control plane HTTP port | `3000` |

---

## See Also

- [Implementation Notes](../implementation-notes/multi-model-control-plane-implementation.md)
- [Runtime Profiles](../runtime-profiles.md)
- [Agentic Harness](../agentic-harness.md)
- [Operational Runbook](./multi-model-control-plane-runbook.md)
