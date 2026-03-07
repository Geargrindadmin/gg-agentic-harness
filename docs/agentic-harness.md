# GGV3 Agentic Harness — Authoritative Node Configuration

> **Version:** 1.3 | **Date:** 2026-03-07  
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
| 3.5 | Swarm Bridge (Optional)     | _(GGV3 addition)_      | Optional bridge-only transports. Default profile uses native coordinator + agent teams.  |
| 4   | Blueprint Engine            | Blueprint              | 5-Cycle Engine + Evaluate-Loop                                                          |
| 5   | Rules / Context             | Rules files            | `GEMINI.md`, `CLAUDE.md`, `.agent/rules/*.md`, `docs/project-context.md`                 |
| 5.5 | Memory Layer                | Session Observation DB | `claude-mem` + SQLite + Chroma + 4 MCP tools (`search`, `timeline`, `get_observations`) |
| 6   | Tool Shed                   | MCP Tool Shed          | Skills + runtime-profile MCP set + workflows + `intelligent-routing` + `kit/`            |
| 7   | Validation Layer            | CI + 3M tests          | `/test-quality-gate`, adversarial review rule, `.husky/pre-push`, GitHub Actions        |
| 8   | PR Review                   | GitHub PRs             | `bd close → bd sync → git push → gh pr create`                                          |

---

## Agent Role Matrix

| Role            | Files   | Write              | Commit | Push               |
| --------------- | ------- | ------------------ | ------ | ------------------ |
| **Scout**       | ✅ Read | ❌                 | ❌     | ❌                 |
| **Planner**     | ✅ Read | ✅ docs/plans only | ❌     | ❌                 |
| **Builder**     | ✅ Read | ✅                 | ✅     | ❌                 |
| **Reviewer**    | ✅ Read | ✅ comments only   | ❌     | ❌                 |
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
| Meta            | `board-of-directors`, `intelligent-routing`, `context-loader` | —                                                                 |

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

---

## Workflow Overlays (Node 6)

Use these as command-level overlays when standard skill chains are not enough:

| Workflow | Purpose | Typical Entry |
| --- | --- | --- |
| `paperclip-extracted` | Intake triage, capability routing, and explicit stage gates | `/go`, coordinator planning, architecture-heavy requests |
| `symphony-lite` | Single-task autonomous execution contract with strict terminal state | `/minion` one-shot implementation runs |
| `visual-explainer` | Generate evidence-linked visual explanations for plans/diffs/audits | Handoffs, PR reviews, status updates |

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
6. Final status (`success` or `failed`) and rollback details if applicable

---

## IDE Mode Switching (Node 3 — NEW in v1.1)

Two parallelism modes selected by `.agent-mode` (written by `setup.sh` at install time):

```bash
AGENT_MODE=$(cat .agent-mode 2>/dev/null || echo "antigravity")
```

| Mode          | Trigger                                                     | Strategy                                                 |
| ------------- | ----------------------------------------------------------- | -------------------------------------------------------- |
| `antigravity` | `ANTHROPIC_BASE_URL=localhost` in `~/.claude/settings.json` | Claude = sole coordinator, native parallel agents        |
| `claude-cli`  | Claude CLI + `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true`    | Claude agent teams concurrently                          |

**Flag location:** `~/.claude/settings.json` → `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`  
**Configured by:** `kit/setup.sh` (interactive prompt + auto-detection)  
**Runtime use:** `/minion` NODE 3 reads `.agent-mode` before dispatching parallelism

### Hard Rules (both modes)

- `auth`, `payments`, `escrow`, `KYC`: Claude handles directly
- Workers never push — always emit `HANDOFF_READY`, coordinator reviews + pushes
- File-Claim Protocol active at all levels

---

## Session Lifecycle Checklist

### Start

- [ ] `bd prime --json` — no orphaned beads
- [ ] Select runtime profile from `docs/runtime-profiles.md` (`codex`, `claude`, or `kimi`)
- [ ] Prime memory according to selected profile (`docs/memory.md`)
- [ ] Ensure context file is current: `npm run harness:project-context:check` (or regenerate)
- [ ] If configured, list remote tasks: `node scripts/gws-task.mjs list --tasklist "$GWS_TASKLIST_ID"`
- [ ] Classify request (SIMPLE / TASK / DECISION / CRITICAL)
- [ ] If TASK: `bd create` → `bd update --claim`
- [ ] Load `agentic-harness.md` and `context-loader` skill
- [ ] Initialize run artifact: `node scripts/agent-run-artifact.mjs init --id <run-id> --runtime <codex|claude|kimi> --classification <...>`
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
