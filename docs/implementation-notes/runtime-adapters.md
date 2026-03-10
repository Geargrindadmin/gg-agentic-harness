# Implementation Notes: Runtime Adapters

**Date:** 2026-03-09  
**Status:** Implemented  
**Packages:** `gg-runtime-adapters`, `gg-orchestrator`

---

## Overview

The runtime adapter system provides a unified interface for spawning and managing workers across different AI runtimes (Codex, Claude, Kimi). Each adapter handles runtime-specific authentication, transport selection, and execution while exposing a common contract to the orchestrator.

---

## Architecture

### Adapter Interface

```ts
interface RuntimeAdapter {
  id: 'codex' | 'claude' | 'kimi';
  spawnWorker(input: SpawnWorkerInput): Promise<SpawnedWorker>;
  sendMessage(input: SendMessageInput): Promise<void>;
  fetchInbox(input: FetchInboxInput): Promise<BusMessage[]>;
  acknowledgeMessage(input: AckMessageInput): Promise<void>;
  getWorkerStatus(input: WorkerStatusInput): Promise<WorkerStatus>;
  terminateWorker(input: TerminateWorkerInput): Promise<void>;
  listCapabilities(): RuntimeCapabilities;
}
```

### Adapter Modes

| Mode | Description | Runtimes |
|------|-------------|----------|
| `host-activated` | Requires host-level config mutation (e.g., `~/.codex/config.toml`) | codex, claude, kimi (cli-session) |
| `contract-only` | Validation without host mutation | claude (fallback) |
| `provider-api` | Direct API integration | kimi (api-session) |

### Transport Types

| Transport | Description | Runtimes |
|-----------|-------------|----------|
| `background-terminal` | PTY session in background | codex, claude |
| `cli-session` | Inherited local CLI session | kimi |
| `api-session` | Direct API calls | kimi |
| `contract-only` | Validation only, no execution | claude (fallback) |

---

## Runtime-Specific Details

### Codex Adapter

**Binary Resolution:**
- Environment: `CODEX_BINARY`
- PATH search: `which codex`

**Credential Discovery:**
1. `~/.codex/auth.json` (OAuth tokens or API key)
2. `OPENAI_API_KEY` environment variable

**Launch Transport:**
- Preferred: `background-terminal`
- Requires authenticated local CLI session

**Autonomous Flag:**
```
--dangerously-bypass-approvals-and-sandbox
```

**Activation:**
- Rewrites `~/.codex/config.toml` for project trust
- Adds `gg-skills` and `filesystem` MCP entries
- Backs up existing config before modification

### Claude Adapter

**Binary Resolution:**
- Environment: `CLAUDE_BINARY`
- PATH search: `which claude`

**Credential Discovery:**
1. `~/.claude/.credentials.json`
2. `~/.local/share/opencode/auth.json`
3. `ANTHROPIC_API_KEY` environment variable

**Launch Transport:**
- Preferred: `background-terminal` (when CLI authenticated)
- Fallback: `contract-only` (validation only)

**Autonomous Flag:**
```
--dangerously-skip-permissions
```

**Activation:**
- Contract-only adapter (no host config mutation)
- Validates local CLI availability and credentials

### Kimi Adapter

**Binary Resolution:**
- Environment: `KIMI_BINARY`
- PATH search: `which kimi`

**Credential Discovery:**
1. `~/.kimi/credentials/kimi-code.json`
2. `~/.kimi/config.toml`
3. `MOONSHOT_API_KEY` or `KIMI_API_KEY` environment variable

**Launch Transport:**
- Preferred: `cli-session` (when CLI authenticated)
- Fallback: `api-session` (direct Moonshot API)

**Autonomous Flag:**
```
--yolo
```

**Activation:**
- Contract-only adapter (no host config mutation)
- Prepares Kimi share directory with copied credentials
- Generates agent YAML and system prompts

**Preflight Checks:**
- Minimum CPU cores: 4
- Minimum total memory: 8 GB
- Worktree existence
- MCP config availability (optional)

---

## Coordinator Selection

The coordinator selection algorithm:

1. **Pinned Mode:** If `GG_COORDINATOR_RUNTIME` is set, use that runtime
2. **Auto Mode:** Evaluate runtimes in `GG_COORDINATOR_PREFERENCE` order (default: `codex,claude,kimi`)
3. **Selection Priority:**
   - First: Runtime with authenticated local CLI session
   - Second: Runtime with authenticated provider credentials
   - Third: Runtime with installed CLI binary
   - Fallback: First runtime in preference order

---

## Worker Launch Flow

1. **Preflight Evaluation:**
   - Check worktree exists
   - Verify runtime binary available
   - Validate credentials
   - Check hardware requirements (Kimi)

2. **Launch Spec Generation:**
   - Render persona contract as system prompt
   - Generate runtime-specific invocation
   - Prepare request/response/transcript files

3. **Execution:**
   - Spawn background PTY session
   - Write initial prompt
   - Parse output for structured markers
   - Route markers to message bus

4. **Completion:**
   - Capture exit status
   - Write response file
   - Update run artifact
   - Emit HANDOFF_READY or BLOCKED message

---

## Structured Markers

Workers emit markers for real-time harness parsing:

```text
@@GG_MSG {"type":"PROGRESS","body":"<summary>"}
@@GG_MSG {"type":"BLOCKED","body":"<reason>","requiresAck":true}
@@GG_MSG {"type":"DELEGATE_REQUEST","body":"<why>","payload":{"requestedRuntime":"...","requestedRole":"..."}}
@@GG_STATE {"status":"handoff_ready","summary":"<summary>"}
@@GG_STATE {"status":"blocked","reason":"<reason>"}
```

---

## File Locations

### Execution Files
```
.agent/control-plane/executions/<runId>/<agentId>/
  <executionId>.request.json
  <executionId>.response.json
  <executionId>.transcript.md
```

### Run State Files
```
.agent/control-plane/runs/<runId>.json
.agent/runs/<runId>.json          (run artifact)
```

### Worktrees
```
.agent/control-plane/worktrees/<runId>/<agentId>/
```

---

## Testing

Run the runtime adapter tests:

```bash
npm run test --workspace=@geargrind/gg-runtime-adapters
```

Run the full runtime parity smoke test:

```bash
npm run harness:runtime-parity
```

---

## References

- PRD: `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`
- ADR: `docs/decisions/0007-runtime-activation-adapters.md`
- Runtime Profiles: `docs/runtime-profiles.md`
- Agentic Harness: `docs/agentic-harness.md`
