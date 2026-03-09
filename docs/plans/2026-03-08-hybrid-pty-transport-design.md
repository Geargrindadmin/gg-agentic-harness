# Hybrid PTY Transport Design

> First implementation slice for live worker communication in `gg-agentic-harness`.

## Goal

Add near-real-time communication for harness workers without giving up run-graph governance, per-agent worktrees, or the hardware governor.

## Discovery

BridgeSpace behaves like a PTY swarm manager:

1. one terminal session per worker,
2. app-mediated stdin/stdout control,
3. shell marker parsing for session state,
4. shared repo/filesystem state as the common substrate.

The harness should copy the PTY transport pattern, but keep the harness mailbox as the system of record.

## Decision

Use a hybrid model:

1. The harness owns the run graph, mailbox, worktree allocation, and hardware governor.
2. Live-capable runtimes run inside background PTY sessions managed by the control plane.
3. The macOS app is an optional viewer/control surface over the same headless server.
4. Messages never go directly from coordinator terminal to worker terminal.
5. All guidance is recorded on the mailbox first, then written into the worker PTY.
6. Worker PTY output is parsed into structured harness messages and state transitions.

## Worker Transport Rules

| Runtime | Preferred Live Transport | Autonomous Flag |
|---|---|---|
| `kimi` | local authenticated CLI session | `--yolo` |
| `claude` | background terminal | `--dangerously-skip-permissions` |
| `codex` | background terminal | `--dangerously-bypass-approvals-and-sandbox` |

Notes:

1. These flags are runtime-specific and must not be normalized to a fake universal `--yolo`.
2. Background sessions inherit the logged-in local CLI state for the current user.
3. Kimi remains harness-controlled. It may request delegation, but the harness authorizes every child worker.

## Structured Stream Markers

Workers must emit structured markers on single lines:

```text
@@GG_MSG {"type":"PROGRESS","body":"Completed API scaffold"}
@@GG_MSG {"type":"BLOCKED","body":"Need schema decision","requiresAck":true}
@@GG_STATE {"status":"handoff_ready","summary":"Ready for review"}
@@GG_STATE {"status":"blocked","reason":"Need credential from coordinator"}
```

These markers are parsed by the control plane and re-emitted onto the mailbox.

## First Slice

1. Add interactive launch plans in `gg-runtime-adapters`.
2. Add a PTY session manager in `gg-control-plane-server`.
3. Route live-capable workers through the PTY manager instead of one-shot execution.
4. Keep `/api/bus/:runId/stream` open and publish new messages live.
5. Add `/api/workers/:runId/:agentId/stream` for worker-specific output.
6. Deliver operator guidance into the live PTY when the worker session is active.

## Deferred Work

1. Add richer parser support for OSC prompt/cwd markers.
2. Add runtime-native delegation request envelopes beyond the generic `@@GG_MSG` format.
3. Add macOS app native worker terminal panes wired to the new worker stream endpoint.
4. Add end-to-end tests for live PTY sessions with fake CLIs.
