# Multi-Model Control Plane Operations

**Version:** 1.0  
**Date:** 2026-03-09  
**Scope:** Headless control plane, runtime adapters, coordinator selection, swarm operations

---

## Overview

The GG Agentic Harness now includes a headless control-plane server (`packages/gg-control-plane-server`) that provides runtime-agnostic coordination across `codex`, `claude`, and `kimi`. This document provides operational guidance for running and managing the control plane.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Control Plane Server                        │
│              (packages/gg-control-plane-server)                 │
├─────────────────────────────────────────────────────────────────┤
│  Run Registry │ Worker Lifecycle │ Message Bus │ Worktree Mgr  │
├─────────────────────────────────────────────────────────────────┤
│              Runtime Adapters (codex/claude/kimi)               │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │
│  │  Codex  │  │ Claude  │  │  Kimi   │  │ macOS Control   │   │
│  │  CLI    │  │  CLI    │  │  CLI    │  │    Surface      │   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Starting the Control Plane

### Development Mode

```bash
# Build and start
npm run control-plane:dev

# Or separately
npm run control-plane:build
npm run control-plane:start
```

### Production Mode

```bash
# Build all packages
npm run build

# Start server
npm run control-plane:start
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GG_COORDINATOR_RUNTIME` | `auto` | Hard-pin coordinator (`codex`, `claude`, `kimi`) |
| `GG_COORDINATOR_PREFERENCE` | `codex,claude,kimi` | Preference order for auto-selection |
| `HARNESS_RESERVED_RAM_GB` | `max(2.0, totalRAM * 0.20)` | Override hardware governor reserve |
| `HARNESS_HYDRA_MODE` | `off` | Hydra sidecar mode (`off`, `shadow`, `active`) |

---

## Coordinator Selection

### Auto Mode (Default)

The harness automatically selects the best available coordinator:

1. Check `GG_COORDINATOR_RUNTIME` — if set, use that runtime
2. Otherwise, evaluate runtimes in `GG_COORDINATOR_PREFERENCE` order
3. Prefer runtime with authenticated local CLI session
4. Fall back to authenticated provider credentials
5. Fall back to locally installed runtime CLI

### Pinned Mode

Explicitly select a coordinator:

```bash
# Environment variable
export GG_COORDINATOR_RUNTIME=codex

# Or in dispatch surface (macOS app or API call)
# Set coordinator to "codex", "claude", or "kimi"
```

### Verification

```bash
# Check which runtime is selected
npm run harness:runtime:status

# Full parity check across all runtimes
npm run harness:runtime-parity
```

---

## Runtime Adapter Management

### Activation

Each runtime adapter has different activation behavior:

```bash
# Codex - mutates host config (~/.codex/)
npm run harness:runtime:activate
# Or: node scripts/runtime-project-sync.mjs activate . --runtime codex

# Claude - contract-only validation
node scripts/runtime-project-sync.mjs activate . --runtime claude

# Kimi - contract-only validation
node scripts/runtime-project-sync.mjs activate . --runtime kimi
```

### Status Check

```bash
# Check specific runtime
node scripts/runtime-project-sync.mjs status . --runtime codex

# Check all runtimes
npm run harness:runtime-parity
```

### Credential Discovery

The harness discovers credentials in this order:

**Codex:**
1. `~/.codex/auth.json` or `CODEX_AUTH_FILE`
2. `OPENAI_API_KEY`

**Claude:**
1. `~/.claude/.credentials.json` or `CLAUDE_CREDENTIALS_FILE`
2. `~/.local/share/opencode/auth.json` or `OPENCODE_AUTH_FILE`
3. `ANTHROPIC_API_KEY`

**Kimi:**
1. `~/.kimi/credentials/kimi-code.json` or `KIMI_CREDENTIALS_FILE`
2. `~/.kimi/config.toml` or `KIMI_CONFIG_FILE`
3. `MOONSHOT_API_KEY` or `KIMI_API_KEY`

---

## Swarm Operations

### Worker Lifecycle

Workers are managed through the control plane API:

```bash
# Spawn a worker (coordinator action)
POST /api/workers/:runId/:agentId/spawn

# Send guidance to a worker
POST /api/workers/:runId/:agentId/message

# Retry a failed worker
POST /api/workers/:runId/:agentId/retry

# Retask a worker to different objective
POST /api/workers/:runId/:agentId/retask

# Terminate a worker
POST /api/workers/:runId/:agentId/terminate
```

### Worktree Management

Each worker gets a dedicated worktree:

```bash
# Base path
.agent/control-plane/worktrees/<runId>/<agentId>/

# Allocation uses git worktree add --detach
# Branchless detached worktree for ephemeral sessions
```

### Hardware Governor

The control plane enforces spawn limits based on hardware capacity:

```
reserved = max(2.0, totalRAMGB * 0.20)
afterModel = max(0, availableRAMGB - modelVRAMGB)
usable = max(0, afterModel - reserved)
raw = usable / perAgentOverheadGB
clamped = max(1, min(64, floor(raw)))
```

Override for testing:
```bash
HARNESS_RESERVED_RAM_GB=4 npm run control-plane:start
```

---

## API Endpoints

### Run Registry

```
GET    /api/runs              # List runs
POST   /api/runs              # Create run
GET    /api/runs/:id          # Get run details
GET    /api/task/:id          # Get task details
POST   /api/runs/register     # Register a new run
```

### Worker Management

```
GET    /api/workers                    # List workers
GET    /api/workers/:runId/:agentId    # Get worker status
POST   /api/workers/:runId/:agentId/spawn
POST   /api/workers/:runId/:agentId/message
POST   /api/workers/:runId/:agentId/retry
POST   /api/workers/:runId/:agentId/retask
POST   /api/workers/:runId/:agentId/terminate
```

### Message Bus

```
GET    /api/bus               # Get bus status
GET    /api/bus/:runId/status # Get run-specific bus status
POST   /api/bus/:runId/post   # Post message to bus
```

### Worktree

```
GET    /api/worktree                    # List worktrees
GET    /api/worktree/:runId/:agentId    # Get worktree details
```

### Governor

```
GET    /api/governor/status   # Get hardware governor status
```

### Integration Settings

```
GET    /api/integrations/settings
PUT    /api/integrations/settings
GET    /api/integrations/catalog
```

---

## Monitoring and Debugging

### Logs

Control plane logs are written to:
```
.agent/control-plane/server/logs/
```

### Health Check

```bash
# Server health
curl http://localhost:3000/api/health

# Full status
npm run harness:runtime:status
```

### Run Artifacts

Every run produces an artifact:
```
.agent/runs/{run-id}.json
```

View artifact schema:
```bash
cat .agent/schemas/run-artifact.schema.json
```

---

## Troubleshooting

### Control Plane Won't Start

1. Check port 3000 is available
2. Verify all packages are built: `npm run build`
3. Check logs in `.agent/control-plane/server/logs/`

### Runtime Not Detected

1. Verify credentials are configured
2. Run `npm run harness:runtime:status` for details
3. Check credential discovery paths above

### Worker Spawn Failures

1. Check hardware governor status: `GET /api/governor/status`
2. Verify git worktree capability: `git worktree list`
3. Check available disk space

### MCP Tools Unavailable

1. Verify runtime activation: `npm run harness:runtime:status`
2. For codex: check `~/.codex/mcp.json` paths
3. Restart runtime session after activation

---

## Security Considerations

1. **Sub-agent Isolation**: Each worker gets a dedicated worktree
2. **Harness Ownership**: The harness owns all spawn/terminate decisions
3. **Kimi Control**: Kimi can request delegation but cannot autonomously spawn
4. **Credential Isolation**: Runtime credentials are never shared between workers
5. **Hardware Limits**: Governor prevents resource exhaustion

---

## Related Documentation

- [Control Plane Design](../plans/2026-03-08-harness-control-surface-design.md)
- [Runtime Profiles](../runtime-profiles.md)
- [Persona Registry Dispatch](../decisions/0004-persona-registry-dispatch.md)
- [Compound Persona Runtime](../decisions/0005-compound-persona-runtime.md)
- [Runtime Activation Adapters](../decisions/0007-runtime-activation-adapters.md)
