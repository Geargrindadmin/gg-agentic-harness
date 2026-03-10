# Runtime Profiles

This document defines runtime-specific wiring for the portable GG Agentic Harness.

## Profiles

| Profile | Primary Runtime | MCP Source of Truth |
|---|---|---|
| `codex` | Codex CLI sessions | `.agent/registry/mcp-runtime.json` |
| `claude` | Claude Code sessions | `.agent/registry/mcp-runtime.json` + Claude plugins |
| `kimi` | Kimi with the same harness contract | `.agent/registry/mcp-runtime.json` |

## Memory Path by Profile

Codex, Claude, and Kimi must execute the same memory strategy in this order:

1. `claude-mem` query path: `search -> timeline -> get_observations`
2. `memory` MCP fallback: `search_nodes -> open_nodes`
3. Worker HTTP fallback: `/api/search -> /api/timeline -> /api/observations/batch`
4. If all are unavailable, continue and log the skip reason in the run artifact

| Profile | Primary Path | Secondary | Tertiary |
|---|---|---|---|
| `claude` | claude-mem query path | memory MCP | worker HTTP fallback |
| `codex` | claude-mem query path | memory MCP | worker HTTP fallback |
| `kimi` | claude-mem query path | memory MCP | worker HTTP fallback |

## Tool-Dependent Rules

1. Run `npm run harness:runtime-parity` before high-value sessions or after MCP/prompt wiring changes.
2. Never assume optional worker-run transport tools exist. Check the runtime profile first.
3. If an MCP server or tool is unavailable for the active profile, use the documented fallback and continue.
4. Keep workflow docs profile-aware: do not hard-code single-runtime commands as universal.
5. Remote task tracking is CLI-first: use `node scripts/gws-task.mjs` plus `.agent/rules/remote-task-tracking.md` for `TASK|TASK_LITE|DECISION`.
6. `CodeGraphContext` is optional in every profile. When enabled, it uses the local `cgc` CLI if available and must fail closed to the standard memory/project-context path when the binary or graph index is unavailable.
7. Verified host install command for the optional CGC path: `uv tool install --python python3.13 codegraphcontext`.
8. Use Python `3.10+` at minimum for `CodeGraphContext`; on macOS prefer Python `3.12+` so the default local database path is available without extra setup.

## Runtime Project Activation

The harness is runtime-agnostic. Activation is runtime-adapter specific.

Current adapters:

1. `codex`: host-config activation required for repo-scoped MCPs (`gg-skills`, `filesystem`).
2. `claude`: dynamic runtime adapter with local CLI preference for live workers (no host rewrite).
3. `kimi`: harness-owned Kimi adapter with CLI-session preference, Moonshot API fallback, and hardware/env preflight (no host rewrite).
4. The headless control plane is runtime-agnostic and can be started independently of the macOS app with `npm run control-plane:start`.

Commands:

```bash
npm run harness:runtime:activate
npm run harness:runtime:status
```

Portable target from the source harness:

```bash
node packages/gg-cli/dist/index.js --project-root /absolute/path/to/target-repo runtime activate /absolute/path/to/target-repo --runtime codex
```

Behavior:

1. `activate` routes to the selected runtime adapter.
2. For `--runtime codex`, activation backs up existing Codex config files.
3. For `--runtime codex`, activation rewrites project trust plus `gg-skills` and `filesystem` MCP entries for the selected repo.
4. For `--runtime claude|kimi`, activation returns contract status and does not mutate host config.
5. Live-capable workers run as background sessions managed by the control plane. The harness remains the system of record for the run graph, mailbox, worktree allocation, and hardware governor.
6. Kimi worker execution uses the harness adapter, not direct persona invention inside Kimi. The harness resolves persona packets first, then injects them into the Kimi `system` message.
7. Kimi launch preflight checks the selected worktree, the inherited local CLI session or Moonshot credentials, and the configured hardware minimums before dispatch.
8. Kimi transport selection is dynamic:
   - prefer `cli-session` when a local authenticated `kimi` CLI is installed
   - fall back to `api-session` when the CLI session is unavailable
9. Claude transport selection is also dynamic:
   - prefer `background-terminal` when the local `claude` CLI is installed
   - fall back to `contract-only` when the CLI is unavailable
10. Codex uses `background-terminal` for live workers by default.
11. All worker spawn, queue, retry, retask, and terminate actions remain harness-controlled, even for Kimi. Kimi may request delegation, but the harness authorizes every child worker.
12. The harness governor adopts the same safe-capacity formula exposed in the macOS app and uses it as a headless fallback for spawn limits.
13. Dedicated worker worktrees live under `.agent/control-plane/worktrees/<runId>/<agentId>`.
14. Restart Codex after codex activation so the active session loads the new repo-scoped MCP paths.
15. `npm run harness:runtime-parity` should treat missing activation as a warning, not a repo wiring failure.
16. Verified CGC smoke command: `npm run gg -- --json workflow run prompt-improver "inspect agent routing" --context-source prefer`.

## Coordinator Selection

The coordinating runtime is both user-selectable and harness-driven:

1. `Auto` is the default and recommended mode.
2. The user may explicitly pin `codex`, `claude`, or `kimi` for the coordinator in the macOS app or any dispatch client.
3. Sub-agent routing remains harness-controlled even when the coordinator is pinned.
4. Kimi remains harness-controlled. It can request delegation, but it cannot autonomously spawn child workers.

Auto-selection policy:

1. If `GG_COORDINATOR_RUNTIME=<codex|claude|kimi>` is set, the harness uses that runtime.
2. Otherwise the harness evaluates runtimes in `GG_COORDINATOR_PREFERENCE`, default order `codex,claude,kimi`.
3. First preference is a runtime with an authenticated local CLI session.
4. Second preference is a runtime with authenticated provider credentials.
5. Third preference is a locally installed runtime CLI.
6. If none are discovered, the harness falls back to the first runtime in the preference order and fails clearly at launch preflight if credentials are still missing.

This means:

- `Auto` prefers local authenticated CLIs before remote API transport.
- users can still pin the coordinator explicitly.
- the harness remains the control plane regardless of the chosen coordinator.

## Credential Discovery

The harness discovers local auth state before choosing transport.

### Codex

1. `~/.codex/auth.json` or `CODEX_AUTH_FILE`
2. `OPENAI_API_KEY`

Transport policy:

1. prefer `background-terminal` when the local Codex CLI and auth store are present
2. otherwise fail closed for live workers until credentials are configured

### Claude

1. `~/.claude/.credentials.json` or `CLAUDE_CREDENTIALS_FILE`
2. `~/.local/share/opencode/auth.json` or `OPENCODE_AUTH_FILE`
3. `ANTHROPIC_API_KEY`

Transport policy:

1. prefer `background-terminal` when the local Claude CLI is installed and authenticated
2. keep the harness as system of record for worktrees, message bus, and spawn control

### Kimi

1. `~/.kimi/credentials/kimi-code.json` or `KIMI_CREDENTIALS_FILE`
2. `~/.kimi/config.toml` or `KIMI_CONFIG_FILE`
3. `MOONSHOT_API_KEY` or `KIMI_API_KEY`

Transport policy:

1. prefer `cli-session` when the local authenticated `kimi` CLI is installed
2. fall back to `api-session` only when the local CLI session is unavailable
3. keep child-worker delegation harness-authorized

## Live Worker Transport

The hybrid transport model is:

1. The harness owns the run graph, worker state, mailbox, worktree, and hardware governor.
2. Live-capable runtimes execute inside background PTY sessions.
3. Operator or coordinator guidance always goes through the harness mailbox first.
4. The control plane writes that guidance into the target worker session.
5. Worker output is parsed in real time for structured markers and routed back onto the mailbox.

Structured worker markers:

- `@@GG_MSG {"type":"PROGRESS","body":"<summary>"}`
- `@@GG_MSG {"type":"BLOCKED","body":"<reason>","requiresAck":true}`
- `@@GG_STATE {"status":"handoff_ready","summary":"<summary>"}`
- `@@GG_STATE {"status":"blocked","reason":"<reason>"}`

## Unattended CLI Flags

These are the exact flags the harness uses for autonomous background workers:

| Runtime | Launch Mode | Exact Flag | Notes |
|---|---|---|---|
| `kimi` | live background PTY | `--yolo` | `--print` also implies `--yolo`, but live workers use interactive mode plus `--yolo` |
| `claude` | live background PTY | `--dangerously-skip-permissions` | used with the local `claude` CLI session |
| `codex` | live background PTY | `--dangerously-bypass-approvals-and-sandbox` | fully autonomous mode for harness workers |

Operational notes:

1. These flags are runtime-specific. Do not normalize them to a fake universal `--yolo`.
2. Background sessions inherit the currently authenticated local CLI state for the logged-in user.
3. The harness still controls spawning, retasking, and termination even when the worker itself is running with an autonomous flag.
4. For controlled local smoke tests on constrained machines, the headless governor can be tuned with `HARNESS_RESERVED_RAM_GB=<value>` without changing the default production safety formula.

## Control Plane Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `GG_COORDINATOR_RUNTIME` | Hard-pin coordinator runtime | `codex`, `claude`, or `kimi` |
| `GG_COORDINATOR_PREFERENCE` | Preference order for auto-selection | `codex,claude,kimi` (default) |
| `GG_CODEX_TRANSPORT` | Override Codex transport | `background-terminal` |
| `GG_CLAUDE_TRANSPORT` | Override Claude transport | `background-terminal` |
| `GG_KIMI_TRANSPORT` | Override Kimi transport | `cli-session` or `api-session` |
| `CODEX_BINARY` | Path to Codex CLI binary | `/usr/local/bin/codex` |
| `CLAUDE_BINARY` | Path to Claude CLI binary | `/usr/local/bin/claude` |
| `KIMI_BINARY` | Path to Kimi CLI binary | `/usr/local/bin/kimi` |
| `HARNESS_RESERVED_RAM_GB` | Tune headless governor for constrained machines | `4` |

## Validation

Run `node scripts/harness-lint.mjs` to verify:

- prompt mirrors are aligned,
- persona registry and compound registry files exist,
- runtime docs reference the same MCP registry and artifact contracts shipped by the harness.

Run `npm run harness:runtime:status` to confirm the current machine/runtime adapter status for the repo you are working in.

Run `npm run harness:runtime-parity` to verify runtime parity across codex, claude, and kimi adapters.
