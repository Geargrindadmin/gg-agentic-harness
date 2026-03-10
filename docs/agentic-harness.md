# GGV3 Agentic Harness — Authoritative Node Configuration

> **Version:** 1.4 | **Date:** 2026-03-09  
> **Purpose:** Canonical reference for all 8 agentic layer nodes.  
> Referenced by: `/minion`, `/go`, `conductor-orchestrator`, all specialist agents.

---

## Node Registry

| #   | Node                        | Stripe Analogy         | GGV3 Implementation                                                                     |
| --- | --------------------------- | ---------------------- | --------------------------------------------------------------------------------------- |
| 1   | Entry Points                | CLI / Web / Slack      | `/go`, `/minion`, GearBox UI                                                             |
| 2   | Agent Sandbox               | Warm DevBox Pool       | Git Worktrees + `agent-factory` + `parallel-dispatch`                                   |
| 3A  | Agent Harness (Antigravity) | Goose fork             | `conductor-orchestrator` + native parallel agents — Claude is sole coordinator          |
| 3B  | Agent Harness (Claude CLI)  | Goose fork             | `conductor-orchestrator` + Claude agent teams concurrently                              |
| 3.5 | Multi-Model Control Plane   | _(GGV3 addition)_      | `gg-orchestrator` + `gg-runtime-adapters` — harness-native worker spawn, delegation, and mailbox bus |
| 4   | Blueprint Engine            | Blueprint              | 5-Cycle Engine + Evaluate-Loop                                                          |
| 5   | Rules / Context             | Rules files            | `GEMINI.md`, `CLAUDE.md`, `.agent/rules/*.md`, `docs/project-context.md`                 |
| 5.5 | Memory Layer                | Session Observation DB | `claude-mem` + SQLite + Chroma + 4 MCP tools (`search`, `timeline`, `get_observations`) |
| 6   | Tool Shed                   | MCP Tool Shed          | Skills + runtime-profile MCP set + workflows + persona registry + compound registry + `kit/` |
| 7   | Validation Layer            | CI + 3M tests          | `/test-quality-gate`, adversarial review rule, `.husky/pre-push`, GitHub Actions        |
| 8   | PR Review                   | GitHub PRs             | `bd close → bd sync → git push → gh pr create`                                          |

---

## Agent Role Matrix

| Role            | Files   | Write              | Commit | Push               |
| --------------- | ------- | ------------------ | ------ | ------------------ |
| **Scout**       | ✅ Read | ❌                 | ❌     | ❌                 |
| **Planner**     | ✅ Read | ✅ docs/plans/PRD/governance only | ❌     | ❌                 |
| **Builder**     | ✅ Read | ✅                 | ✅     | ❌                 |
| **Reviewer**    | ✅ Read | ✅ tests/snapshots/review artifacts only | ❌     | ❌                 |
| **Coordinator** | ✅ Read | ✅                 | ✅     | ✅ feature/\* only |

**File-Claim Protocol:**

- Agent issues: `CLAIM: {path}`
- Coordinator responds: `ACK_CLAIM` (proceed) or `DENY_CLAIM` (wait)
- Concurrent edits to the same file = FORBIDDEN. Serialize via coordinator.

**Commit prefix format (traceability):**

```
[agent:{role}-{bead-id}] {type}: {description}
```

---

## Tool Shed Index (Node 6)

### Skills by Domain

| Domain          | Primary Skills                                                | Chain                                                             |
| --------------- | ------------------------------------------------------------- | ----------------------------------------------------------------- |
| Payments/Stripe | `api-patterns`, `database-design`                             | `api-patterns → vulnerability-scanner`                            |
| Frontend/React  | `frontend-design`, `clean-code`                               | `frontend-design → clean-code → performance-profiling`            |
| Security        | `vulnerability-scanner`, `red-team-tactics`                   | `vulnerability-scanner → red-team-tactics`                        |
| Auth            | `api-patterns`, `vulnerability-scanner`                       | `api-patterns → vulnerability-scanner`                            |
| Testing         | `tdd-workflow`, `testing-patterns`, `webapp-testing`          | `tdd-workflow → verification-before-completion`                   |
| Backend/API     | `api-patterns`, `nodejs-best-practices`                       | `api-patterns → nodejs-best-practices → verification-before-completion` |
| Database        | `database-design`                                             | —                                                                 |
| Deploy/CI       | `deployment-procedures`                                       | `deployment-procedures → verification-before-completion`          |
| Debugging       | `systematic-debugging`                                        | —                                                                 |
| Memory          | `context-loader`, `claude-mem`                                | `search → timeline → get_observations` (fallback: `search_nodes → open_nodes`) |
| Meta            | `board-of-directors`, `context-loader`, persona registry | —                                                                 |

### MCP Servers

Source of truth: `.agent/registry/mcp-runtime.json` (profile-specific and machine-validated).

| Server | Primary Use | Node |
| --- | --- | --- |
| gg-skills | Skills/workflows runtime loading | 6 |
| github | Repository and PR automation | 6, 8 |
| sentry | Production issue investigation | 3, 6 |
| stripe | Payments tooling | 6 |
| MongoDB | Data queries and validation | 6, 7 |
| browserbase | Browser automation and UI checks | 7 |
| apify | Research/data collection | 3, 6 |
| n8n-mcp | Workflow node/tool support | 6 |
| docker | Runtime/container diagnostics | 6, 7 |
| browser-use | Browser actions/extraction | 6, 7 |
| context7 | External docs context | 6 |
| chrome-devtools | Browser diagnostics and tracing | 7 |
| codacy | Quality/security scan signals | 7 |
| filesystem | Local file operations | All |
| memory | Persistent cross-session context | 5.5 |
| sequentialthinking | Multi-step reasoning | 3, 4 |
| time | Audit timestamps | All |
| Ref | Documentation retrieval | 6 |
| CodeLogic | Impact analysis and CI generation | 6 |
| everything | MCP protocol sanity testing | 6 |
| exa | Web/code search context | 6 |
| google-maps-platform-code-assist | Maps platform docs/tools | 6 |
| ide | Utility/debug helper tools | 6 |

Runtime-adapter rule:

1. `gg-skills` and `filesystem` are repo-scoped MCPs for the codex runtime adapter.
2. Before a codex runtime session in a new repo, run `npm run harness:runtime:activate` (defaults to `--runtime codex`).
3. `runtime-project-sync.mjs` supports `codex|claude|kimi` and routes activation/status by adapter capability.
4. `npm run harness:runtime-parity` may warn if host activation has not been applied on the current machine, but the local repo install can still be structurally correct.
5. Restart Codex after runtime activation so the active session reloads repo-scoped MCP changes for the selected repo.
6. Optional `CodeGraphContext` pilot mode requires the host `cgc` CLI. Verified host install command: `uv tool install --python python3.13 codegraphcontext`.

---

## Workflow Overlays (Node 6)

Use these as command-level overlays when standard skill chains are not enough:

| Workflow | Purpose | Typical Entry |
| --- | --- | --- |
| `paperclip-extracted` | Intake triage, capability routing, and explicit stage gates | `/go`, coordinator planning, architecture-heavy requests |
| `prompt-improver` | Runtime-agnostic intake normalization packet for vague or underspecified objectives | `/go`, `paperclip-extracted`, coordinator intake |
| `symphony-lite` | Single-task autonomous execution contract with strict terminal state | `/minion` one-shot implementation runs |
| `visual-explainer` | Generate evidence-linked visual explanations for plans/diffs/audits | Handoffs, PR reviews, status updates |
| `full-doc-update` | Post-task documentation synchronization and drift-prevention report | End of `/minion`, `/go`, and autonomous task completion |
| `hydra-sidecar` | Feature-flagged sidecar advisory/delegation packet with dual-research gate | Optional routing recommendation for `/go` and `paperclip-extracted` |
| `network-ai-pilot` | Shadow-first pilot workflow for optional Network-AI sidecar evaluation | Controlled addon evaluation without core-path replacement |

---

## Priority Integration Program (2026-03-08)

Status legend: `implemented` = available now, `pilot` = optional controlled rollout, `planned` = approved but not yet merged.

| Stream | Target | Status | Contract |
| --- | --- | --- | --- |
| Context quality | `CodeGraphContext` | implemented (pilot) | Optional context-source path with fallback to standard memory chain; host requires `cgc` CLI for live graph-backed context |
| Reporting quality | `visual-explainer` upgrade | implemented | Evidence-linked architecture/diff/audit reports with citations and validation ingest |
| Intake quality | Prompt-improver workflow | implemented | Runtime-agnostic objective normalization before execution routing |
| Sidecar orchestration | `Hydra` | implemented (feature-flagged) | `off|shadow|active` sidecar mode with deterministic fallback and mandatory dual-research decision gate |
| Addon sidecar candidate | `Network-AI` | pilot planned | Shadow-first evaluation workflow and reversible integration contract |

Reference plan: `docs/plans/2026-03-08-priority-integrations-action-plan.md`.
Reference assessment: `docs/assessments/2026-03-08-network-ai-assessment.md`.

---

## Selective BMAD Imports

Cherry-picked patterns integrated into GGV3 (without replacing core harness):

1. **Project Context Workflow**
- Command: `npm run harness:project-context`
- Output: `docs/project-context.md`
- Purpose: maintain concise, repo-derived context for all runtimes (`codex`, `claude`, `kimi`).

2. **Adversarial Review Discipline**
- Rule: `.agent/rules/adversarial-review.md`
- Purpose: enforce findings-first review quality and block low-signal "looks good" outputs.

---

## Retry and Rollback Policy (Per Node)

### Retry Policy (universal)

- Max 3 attempts per failing step
- Exponential backoff: 1s → 2s → 4s (cap 30s)
- Retryable HTTP: 429, 502, 503, 504, ECONNRESET, ETIMEDOUT
- Non-retryable: 400, 401, 403, 404, 409, 422, any 5xx from OUR service
- After 3 failures: STOP. Execute rollback. Create bead. Notify human. NEVER fall through.

### Rollback Procedure

Every `implementation_plan.md` MUST contain a rollback plan:

```markdown
## Rollback Plan

### Files to Revert

- `{path}` — pre-change commit: `{hash}`

### Commands

git checkout {hash} -- {path}
npm uninstall {package} # if dependencies were added

### Validation

npx tsc --noEmit && npm test

### Trigger Conditions

- 3 failed validation retries
- PRE_LAUNCH_GATE.md fails after fixes
- Board rejects implementation mid-run
```

Rollback bead format:

```bash
bd create "Rollback needed: {task}" \
  --description "Root cause: {error}. Agent exhausted 3 retries." \
  -t bug -p 0 \
  --deps discovered-from:{original-bead-id} --json
```

---

## Board of Directors Escalation

**Trigger conditions (REQUIRED):**

- Task size > 50 LoC AND touches auth/payments/security
- Task size > 300 LoC (any domain)
- Architecture decision with multiple valid approaches
- Breaking change to a shared interface

**Trigger conditions (OPTIONAL but recommended):**

- Novel pattern not established in codebase
- Third-party service integration
- Performance-sensitive hot path

**Board output requirements:**

- All directives written to `docs/PRD.md` before implementation begins
- Unanimous vote (5-0) required for HIGH risk — any dissent → escalate to human
- Majority vote (3-2+) acceptable for MEDIUM risk
- Every decision packet must include:
  - codebase evidence citations
  - internet evidence citations with source dates

---

## In-Loop vs Out-Loop Decision Matrix

| Factor                            | Uses In-Loop (/go, Cursor, Claude Code) | Uses Out-Loop (/minion) |
| --------------------------------- | --------------------------------------- | ----------------------- |
| Building the agentic layer itself | ✅                                      | ❌                      |
| Highly novel / ambiguous task     | ✅                                      | ❌                      |
| Requires real-time human steering | ✅                                      | ❌                      |
| Well-defined feature or bugfix    | ❌                                      | ✅                      |
| Parallelizable across files       | ❌                                      | ✅                      |
| Test coverage tasks               | ❌                                      | ✅                      |
| Refactoring with clear scope      | ❌                                      | ✅                      |
| Chore / maintenance               | ❌                                      | ✅                      |

**Rule of thumb:** >50% of engineer attention should be in-loop (building the system). Features ship out-loop.

---

## Validation Gate Sequence (Node 7)

```
Gate 1:  npx tsc --noEmit             (TypeScript — always first)
Gate 2:  npm run lint                  (ESLint)
Gate 3:  npx jest --findRelatedTests   (Targeted tests on changed files)
Gate 4:  /test-quality-gate            (11 sub-agents — hard stop)
Gate 5:  security_scan.py             (HIGH risk tasks only)
Gate 6:  PRE_LAUNCH_GATE.md           (protected branch targets only)
```

All gates must pass before Node 8 (PR creation). No exceptions.

---

## Run Artifact Contract (Node 7.5)

Every non-trivial run must emit a machine-readable artifact:

- Path: `.agent/runs/{run-id}.json`
- Schema: `.agent/schemas/run-artifact.schema.json`
- Helper: `node scripts/agent-run-artifact.mjs`

Minimum required evidence:

1. Request classification + runtime profile
2. Selected skills list
3. MCP smoke/tool calls executed
4. Validation gates with command, exit code, attempt count
5. Remote task sync status (`gws-task.mjs`) or explicit skip reason
6. Persona routing evidence (`personaRouting`) including compound persona when present
7. Final status (`success` or `failed`) and rollback details if applicable

---

## Multi-Model Control Plane (Node 3.5 — NEW in v1.4)

The harness now provides a first-class multi-model orchestration layer. The active coordinator runtime can request work from another runtime under explicit policy, with deterministic traceability, bounded authority, and shared validation semantics.

### Control Plane Packages

| Package | Purpose | Location |
|---------|---------|----------|
| `gg-orchestrator` | Run registry, worker lifecycle, delegation policy, message bus | `packages/gg-orchestrator` |
| `gg-runtime-adapters` | Runtime adapter interface for `codex`, `claude`, `kimi` | `packages/gg-runtime-adapters` |
| `gg-control-plane-server` | Headless HTTP control plane for external clients | `packages/gg-control-plane-server` |

### Runtime Adapter Contract

Each runtime adapter implements:

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

### Launch Transport Modes

| Runtime | Transport | Mode | Autonomous Flag |
|---------|-----------|------|-----------------|
| `codex` | `background-terminal` | `host-activated` | `--dangerously-bypass-approvals-and-sandbox` |
| `claude` | `background-terminal` | `host-activated` | `--dangerously-skip-permissions` |
| `kimi` | `cli-session` | `host-activated` | `--yolo` |
| `kimi` | `api-session` | `provider-api` | N/A (API-based) |

### Worker Lifecycle

1. **Create Run**: `createRun` establishes a run context with coordinator runtime selection
2. **Spawn Worker**: `spawnWorker` creates a worker record with persona, role, and launch spec
3. **Delegate Task**: `delegateTask` evaluates governance policy before approving child workers
4. **Execute**: `executeWorker` runs preflight checks and launches the runtime adapter
5. **Message Bus**: Workers communicate via mailbox-style bus with directed messages and acks
6. **Terminate**: Workers emit `@@GG_STATE` markers; harness controls spawn/terminate policy

### Structured Worker Markers

Workers emit these markers for real-time harness parsing:

```text
@@GG_MSG {"type":"PROGRESS","body":"Completed API scaffold"}
@@GG_MSG {"type":"BLOCKED","body":"Missing schema decision","requiresAck":true}
@@GG_MSG {"type":"DELEGATE_REQUEST","body":"Need specialist","payload":{"requestedRuntime":"kimi","requestedRole":"builder","personaId":"..."}}
@@GG_STATE {"status":"handoff_ready","summary":"Ready for review"}
@@GG_STATE {"status":"blocked","reason":"Need credential from coordinator"}
```

### Delegation Policy

Delegation decisions are policy-based and recorded in run artifacts:

| Scenario | Policy |
|----------|--------|
| Task role = `builder`, risk = `low/medium`, parallelizable | Approve delegation to `kimi` |
| Task role = `coordinator` or `reviewer` | Retain with active runtime |
| Risk tier = `high` or touches `auth/payments/secrets` | Require board approval |
| Runtime parity check fails | Reject with rationale |

### Coordinator Selection

The coordinator runtime supports both harness-driven and operator-pinned selection:

1. `Auto` (default): harness selects from authenticated runtimes in preference order
2. `Pinned`: operator selects `codex`, `claude`, or `kimi` explicitly
3. Selection respects `GG_COORDINATOR_RUNTIME` and `GG_COORDINATOR_PREFERENCE` environment variables
4. Auto-selection prefers authenticated local CLI sessions before provider-backed API transport

### Hard Rules (all modes)

- `auth`, `payments`, `escrow`, `KYC`: active runtime handles directly, but board approval and reviewer evidence are mandatory
- Persona registry and compound registry govern all specialist dispatch: run `node scripts/persona-registry-audit.mjs` and `node scripts/persona-registry-resolve.mjs --prompt "<task>" --classification <...> --json` before fanout
- If routing confidence is low, keep orchestration under the coordinator; if `createPersonaSuggested=true`, follow `.agent/rules/persona-dispatch-governance.md`
- If resolver returns `compoundPersona`, use that compound's primary/collaborators as the effective dispatch contract and record it in the run artifact
- Workers never push — always emit `HANDOFF_READY`, coordinator reviews + pushes
- File-Claim Protocol active at all levels
- Only the harness may spawn children — workers can request delegation but cannot autonomously spawn

---

## Session Lifecycle Checklist

### Start

- [ ] `bd prime --json` — no orphaned beads
- [ ] `npm run harness:runtime-parity` — Codex/Claude/Kimi parity intact
- [ ] Select runtime profile from `docs/runtime-profiles.md` (`codex`, `claude`, or `kimi`)
- [ ] Prime memory according to selected profile (`docs/memory.md`)
- [ ] Ensure context file is current: `npm run harness:project-context:check` (or regenerate)
- [ ] Audit persona registry: `npm run harness:persona:audit`
- [ ] Resolve approved personas for the task: `node scripts/persona-registry-resolve.mjs --prompt "<task>" --classification <...> --json > .agent/runs/<run-id>.persona-routing.json`
- [ ] If configured, list remote tasks: `node scripts/gws-task.mjs list --tasklist "$GWS_TASKLIST_ID"`
- [ ] Classify request (SIMPLE / TASK / DECISION / CRITICAL)
- [ ] If TASK: `bd create` → `bd update --claim`
- [ ] Load `agentic-harness.md` and `context-loader` skill
- [ ] Initialize run artifact: `node scripts/agent-run-artifact.mjs init --id <run-id> --runtime <codex|claude|kimi> --classification <...>`
- [ ] Record persona routing in the artifact: `node scripts/agent-run-artifact.mjs persona --id <run-id> --resolution-file .agent/runs/<run-id>.persona-routing.json`
- [ ] For `TASK|TASK_LITE|DECISION`, upsert remote task open status via `.agent/rules/remote-task-tracking.md`

### During

- [ ] Minimal diff only — touch only files in scope
- [ ] TypeScript mandatory — no `any` without justification
- [ ] Scope enforcement — out-of-scope bugs get a `discovered-from` bead, not a fix
- [ ] File-Claim Protocol active — no concurrent edits

### End (Land the Plane)

- [ ] `npm run lint && npm test` → both exit 0
- [ ] `bd close {bead-id} --reason "Done" --json`
- [ ] `bd sync`
- [ ] `git pull --rebase`
- [ ] `git push`
- [ ] `git status` shows "up to date with origin"
- [ ] `bd prime` shows zero orphaned beads
- [ ] PR created (if code changes) — draft for human review
- [ ] Complete run artifact: `node scripts/agent-run-artifact.mjs complete --id <run-id> --status <success|failed>`
