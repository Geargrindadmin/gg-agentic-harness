---
name: minion
description: 'Autonomous out-loop coding agent. Traverses all 8 agentic layer nodes from prompt to validated PR, with explicit escalation checkpoints.'
arguments:
  - name: task
    description: 'The task to execute. Be specific: feature, bugfix, refactor, or chore.'
    required: true
user_invocable: true
---

# /minion — Autonomous Agentic Coding Agent

> **This is GGV3's equivalent of Stripe's Minions.**
> Autonomous by default. Human intervention only at defined escalation checkpoints.
> Human shows up at: (1) the prompt and (2) the PR review.

```
/minion <task description>
```

**Examples:**

```
/minion Add rate limiting middleware to the billing API routes
/minion Fix the escrow release bug in AuctionEscrowService
/minion Refactor WalletService to extract fee calculation into a helper
/minion Add test coverage for StripeBillingService.createSubscription
```

---

// turbo-all

## STEP -1 — Memory Prime (ALWAYS FIRST)

Select runtime profile from `docs/runtime-profiles.md`, then use the profile-specific memory path:

1. `claude` profile primary: `search -> timeline -> get_observations`
2. `codex` profile primary: `search_nodes -> open_nodes`
3. `kimi` profile primary: `search_nodes -> open_nodes`
4. If neither memory path is available, continue and log the gap in run artifact (`mcpCalls` with `status=skipped`)

For `TASK|TASK_LITE|DECISION`, apply `.agent/rules/remote-task-tracking.md`:

1. If configured, list remote queue: `node scripts/gws-task.mjs list --tasklist "$GWS_TASKLIST_ID"`
2. Mirror run `open` and `completed` states via `node scripts/gws-task.mjs sync-run ...`
3. Ensure project context is current: `npm run harness:project-context:check || npm run harness:project-context`

Use retrieved context to:

- Detect if a bead already exists for this task (avoid duplicate work)
- Surface prior Board decisions that apply to this task domain
- Recall known constraints, security requirements, or performance budgets
- Prime the file-claim registry with files that were recently edited

---

## STEP 0 — Pre-Flight: Classify and Gate

Parse `$ARGUMENTS` to determine:

- **Task type**: feature | bugfix | refactor | chore | test
- **Domain(s)**: auth, payments, auction, database, frontend, infra, etc.
- **Complexity**: small (<50 LoC) | medium (50–300 LoC) | large (>300 LoC)
- **Risk level**: LOW (no auth/payments/security) | HIGH (touches auth/payments/security/compliance)

**Board of Directors is REQUIRED if:**

- Risk level = HIGH (auth, payments, escrow, KYC, compliance)
- Complexity = large (>300 LoC)
- Task touches `main`/`release`/`hotfix` branch targets

**Escalate to human if:**

- Goal is ambiguous (>1 valid interpretation)
- Scope conflicts with an active bead/track
- Board rejects the approach
- Fix cycle exceeds 3 retries

---

## NODE 1 — ENTRY (API Layer)

**You are now the Minion.** Execute the 10-step Coordination Loop autonomously until all tasks complete. Do NOT stop between steps.

1. Confirm task from `$ARGUMENTS`
2. Check for active beads that conflict: `bd ready --json`
3. Determine target branch (feature branches auto-push; main/release require PR)
4. Log entry: `[minion] Starting: {task} — {date}`

---

## NODE 2 — SANDBOX (Agent Isolation)

Set up isolated execution environment:

0. **Initialize run artifact:** `node scripts/agent-run-artifact.mjs init --id {bead-id} --runtime {codex|claude|kimi} --classification TASK`
0.1 **Upsert remote task (open):** `node scripts/gws-task.mjs sync-run --tasklist "$GWS_TASKLIST_ID" --run-id {bead-id} --title "{task}" --status open`
1. **Create bead:** `bd create "{task}" --description="{full context}" -t {type} -p {priority} --json`
2. **Claim bead:** `bd update <id> --claim --json`
3. **Create worktree** (for complex/large tasks):
   ```bash
   git worktree add worktrees/{bead-id} -b feature/{bead-id}
   ```
4. **Initialize dirty baseline:** `bash scripts/dirty-worktree-guard.sh init`
5. **Initialize File-Claim registry** — no parallel agent may edit a file without ACK from this coordinator.

> **File-Claim Protocol:**
> Before any agent writes to a file, register it:
> `CLAIM: {path}` → receive `ACK_CLAIM` or `DENY_CLAIM`
> Concurrent edits are FORBIDDEN. Serialize conflicting writes.

---

## NODE 3 — HARNESS BOOT (Conductor Orchestrator)

Boot the conductor and load context:

1. **Load harness config:** Read `docs/agentic-harness.md` for node responsibilities and role matrix.
2. **Load context** via `context-loader` skill — subdirectory-scoped only, NOT the full codebase.
3. **Run Board of Directors** (if required per NODE 1 gate):
   - Invoke `/board-meeting {task description}` with full context
   - All Board directives MUST be written to the task plan before proceeding
   - Board votes 5-0 required for HIGH risk tasks (any dissent → escalate to human)
4. **Assign agent roles:**
   - Scout: reads codebase, surfaces questions
   - Planner: writes task scope + acceptance criteria
   - Builder: writes code
   - Reviewer: runs tests + linting
   - Coordinator: this agent (claims files, serializes writes, resolves conflicts)

5. **Parallelism Mode Detection:**

   Read `.agent-mode` (written by `setup.sh`) to determine the parallelism strategy:

   ```bash
   AGENT_MODE=$(cat .agent-mode 2>/dev/null || echo "antigravity")
   ```

   | `.agent-mode` value | Parallelism strategy |
   | ------------------- | ---------------------------------------------------------------------------------------------------------- |
   | `antigravity`       | **Antigravity Mode** — use native `parallel-dispatch` / agent teams; optional bridge tools only if available |
   | `claude-cli`        | **Claude CLI Mode** — Claude sub-agent teams first; optional bridge/swarm tools if profile supports them |

---

### NODE 3A — Antigravity Mode (Native Parallelism First)

> **Use when**: `.agent-mode` = `antigravity` OR `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is not set

Claude acts as sole coordinator. Use native `parallel-dispatch` and message-bus protocols by default.

If explicit worker-run tools are present in the active runtime profile, they may be used for large tasks.

**Do NOT block immediately.** While the worker pool runs, the coordinator continues:

- Updates docs / writes notes
- Runs Board decisions for upcoming choices
- Works on smaller parallel backlog tasks

Between coordinator steps, poll for worker signals:

```
output = get_worker_status(runId)
```

- `ESCALATE:` detected → run `/board-meeting` → dispatch decision back to worker
- `AGENT_FAILED:` detected → retry failed worker with adjusted task

When coordinator work is done, block until worker pool finishes:

```
result = watch_run(runId, agentIds, { timeoutMs: 1800000 })
```

Review worker output → run NODE 7 gates → NODE 8 PR.

---

### NODE 3B — Claude CLI Mode (Agent Teams + Optional Bridge)

> **Use when**: `.agent-mode` = `claude-cli` AND `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true` in `~/.claude/settings.json`

Claude uses **parallel sub-agent teams** for Claude-native work. Bridge/swarm tools are optional and profile-dependent.

**For medium tasks** (50–300 LoC): spawn Claude sub-agents only:

```
# Claude agent team handles it
# Sub-agents run in parallel via CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# Each sub-agent has its own context window and tool access
```

**For large tasks** (>300 LoC): run parallel teams; add worker-run transport only if available:

```
# 1. Claude sub-agents for work that must stay in Claude context:
#    - Board of Directors deliberation
#    - Security/auth review (never delegated outside coordinator controls)
#    - Documentation + PR description generation
#    - Test generation for high-risk paths

# 2. Optional worker-run transport for isolated implementation chunks
#    - only if runtime profile exposes bridge/swarm tools
```

**Coordination loop** (both in flight simultaneously):

```
while not all_done:
    output = get_worker_status(runId)
    if "ESCALATE:" in output:
        run /board-meeting → send decision to assigned worker
    if "AGENT_FAILED:" in output:
        retry worker
    # Claude sub-agents self-report via message bus
```

**Hard rules for Claude CLI mode:**

- `auth`, `payments`, `escrow`, `KYC` tasks: Claude sub-agents ONLY
- Bridge workers never push — always HANDOFF_READY → Claude reviews + pushes
- Coordinator serializes all file merges (File-Claim Protocol still active)

---

## NODE 4 — BLUEPRINT ENGINE (Code + Agents Interleaved)

Select blueprint mode based on complexity:

### Mode A — 5-Cycle Engine (medium/large tasks)

```
C1: Research + Architecture
  → Scout agent reads relevant files and surfaces questions
  → Board deliberation if needed
  → Write implementation_plan.md with rollback plan

C2: Implementation + Security
  → Builder agent writes TypeScript-first, security-first code
  → Every new function/endpoint/component MUST have a test
  → DETERMINISTIC: npx tsc --noEmit (must exit 0 before continuing)

C3: UI/UX Quality (if frontend)
  → Review against cyber-component-dev-guide.md
  → 5-Pass Redesign Loop on every created/modified UI item
  → DETERMINISTIC: npm run lint --workspace=client

C4: Hardening
  → Edge cases, error boundaries, performance
  → DETERMINISTIC: npx jest --findRelatedTests {changed files}

C5: Documentation + Ship
  → Update walkthrough.md
  → DETERMINISTIC (all of Node 7 runs here)
```

### Mode B — Evaluate-Loop (simple/chore tasks)

```
/loop-planner → create plan.md from task
/loop-plan-evaluator → PASS/FAIL verdict
/loop-executor → implement from verified plan
/loop-execution-evaluator → dispatch to eval-code-quality | eval-integration | eval-ui-ux | eval-business-logic
/loop-fixer → fix FAIL verdicts (max 3 retries)
```

### Deterministic Nodes (NO LLM — always execute these as code):

| Step            | Command                               | On Failure                       |
| --------------- | ------------------------------------- | -------------------------------- |
| TypeScript gate | `npx tsc --noEmit`                    | STOP. Fix errors. Retry (max 3). |
| Lint gate       | `npm run lint`                        | STOP. Fix errors. Retry (max 3). |
| Targeted tests  | `npx jest --findRelatedTests {files}` | STOP. Fix. Retry (max 3).        |
| Bead hygiene    | `bd prime --json`                     | STOP if orphaned beads found.    |
| Dirty state     | `bash scripts/dirty-worktree-guard.sh check` | STOP if unexpected newly-dirty paths. |

> **After 3 failures on any deterministic gate → ROLLBACK.**
> See rollback procedure in `docs/agentic-harness.md`.

---

## NODE 5 — RULES LOAD (Context Engineering)

Load only what is needed for the active task:

1. **Subdirectory rules** — automatically apply `.agent/rules/*.md` constraining the current domain.
2. **Anti-mocking rule** — load `.agent/rules/anti-mocking.md`. Never mock what you can use for real.
3. **Push policy** — load `.agent/rules/push-policy.md`. Feature branches auto-push. Main requires PR.
4. **Traceability** — all commits must use: `[agent:builder-{bead-id}] {conventional commit message}`
5. **Scope enforcement** — if bugs are found outside this task's scope:
   ```bash
   bd create "Found: {description}" --description="{context}" -p 2 --deps discovered-from:{current-bead-id} --json
   ```
   Do NOT fix them. Continue with the assigned task.

---

## NODE 6 — TOOL SHED (Auto-Selected Skills + MCPs)

The `intelligent-routing` skill automatically selects the right stack. Reference this map:
Use `.agent/registry/mcp-runtime.json` as the server source of truth.

| Domain          | Skills                                                  | MCPs            |
| --------------- | ------------------------------------------------------- | --------------- |
| Payments/Stripe | `api-patterns`, `database-design`                       | MongoDB, Sentry |
| Frontend/React  | `frontend-design`, `clean-code`, `performance-profiling` | Browserbase     |
| Testing         | `tdd-workflow`, `testing-patterns`, `verification-before-completion` | — |
| Security        | `vulnerability-scanner`, `red-team-tactics`            | Codacy          |
| Database        | `database-design`                                       | MongoDB         |
| Debugging       | `systematic-debugging`                                  | Sentry, MongoDB |
| Docs            | `documentation-templates`                               | Filesystem      |

**Multi-Skill Chains** (apply in order when multiple domains detected):

- Auth: `api-patterns → vulnerability-scanner`
- Frontend+Perf: `frontend-design → clean-code → performance-profiling`
- Stripe+Security: `api-patterns → vulnerability-scanner`
- New API endpoint: `api-patterns → nodejs-best-practices → verification-before-completion`
- New feature+TDD: `tdd-workflow → verification-before-completion`

**Workflow overlays** (invoke when shape matches):

- `/paperclip-extracted` for intake + routing + gate-managed objective execution
- `/symphony-lite` for strict one-task autonomous runs with `HANDOFF_READY`/`BLOCKED`
- `/visual-explainer` to emit evidence-linked handoff artifacts for PR or stakeholder review

---

## NODE 7 — VALIDATION LAYER (Shift-Left Feedback)

Run ALL gates before any commit leaves the sandbox:

### Gate 1 — TypeScript (Non-negotiable)

```bash
npx tsc --noEmit
```

Must exit 0. If not: fix and retry (max 3 times). Then rollback.

### Gate 2 — Lint

```bash
npm run lint
```

Must exit 0. Fix critical errors first (security > lint > style).

### Gate 3 — Tests

```bash
npx jest --findRelatedTests $(git diff --name-only HEAD)
```

Must exit 0. New code requires 100% pass rate.

### Gate 4 — Test Quality Gate

Invoke `/test-quality-gate` — 11 specialized sub-agents verify test quality.
All 11 must return PASS. Hard stop on any FAIL.

### Gate 5 — Security (if HIGH risk task)

```bash
python .agent/skills/vulnerability-scanner/scripts/security_scan.py .
```

### Gate 6 — PRE_LAUNCH_GATE (if pushing to protected branch)

Read and pass all checks in `PRE_LAUNCH_GATE.md`.

### Inter-Agent Quality Gate (before any handoff between agents):

1. `npx tsc --noEmit` → exit 0
2. `npm run lint` → exit 0
3. `npx jest --findRelatedTests {changed-files}` → exit 0
4. `git status` → clean
5. `bash scripts/dirty-worktree-guard.sh check` → pass

> **Retry Policy:** Max 3 attempts per gate. Exponential backoff: 1s → 2s → 4s.
> After 3 failures → execute rollback → create discovered bead → notify human.
> NEVER fall through to success path after 3 failures.

### Run Evidence (required)

Record deterministic evidence in `.agent/runs/{bead-id}.json`:

1. `node scripts/agent-run-artifact.mjs gate --id {bead-id} --name tsc --command "npx tsc --noEmit" --exit-code {code} --attempt {n}`
2. `node scripts/agent-run-artifact.mjs gate --id {bead-id} --name lint --command "npm run lint" --exit-code {code} --attempt {n}`
3. `node scripts/agent-run-artifact.mjs gate --id {bead-id} --name tests --command "npx jest --findRelatedTests ..." --exit-code {code} --attempt {n}`

---

## NODE 8 — PR CREATION + HUMAN REVIEW REQUEST

When all validation gates pass:

### 1. Commit

```bash
git add -A
git commit -m "[agent:builder-{bead-id}] {type}: {description}

- {change 1}
- {change 2}
- {change 3}

Closes bead: {bead-id}
Validation: tsc ✅ | lint ✅ | tests ✅ | quality-gate ✅"
```

### 2. Push

```bash
git pull --rebase
git push -u origin feature/{bead-id}
```

### 2.5 Finalize Run Artifact

```bash
node scripts/agent-run-artifact.mjs complete --id {bead-id} --status success
# For TASK|TASK_LITE|DECISION:
node scripts/gws-task.mjs sync-run --tasklist "$GWS_TASKLIST_ID" --run-id {bead-id} --title "{task}" --status completed
```

### 3. Create PR

```bash
gh pr create \
  --title "[Minion] {task description}" \
  --body "## What

{description of changes}

## Why

{motivation and context}

## Validation

- [x] \`npx tsc --noEmit\` → ✅
- [x] \`npm run lint\` → ✅
- [x] \`npm test\` → ✅ ({N} tests)
- [x] Test Quality Gate → ✅ (all 11 sub-agents PASS)
- [x] Security scan → ✅ (if applicable)

## Bead

{bead-id}: {bd show <bead-id>}

## Files Changed

{git diff --stat HEAD~1}

---
🤖 *This PR was created by a GGV3 Minion agent. Human engineering review required before merge.*" \
  --draft
```

### 4. Close Bead

```bash
bd close {bead-id} --reason "PR created: {pr-url}" --json
bd sync
```

### 5. Deliver Report

```markdown
## ✅ Minion Complete

**Task:** {task}
**Bead:** {bead-id}
**Branch:** feature/{bead-id}
**PR:** {pr-url} (draft — awaiting your review)

### Nodes Traversed

- [x] Node 1: Entry — {entry mode}
- [x] Node 2: Sandbox — worktree `{path}`
- [x] Node 3: Harness — conductor booted, {board: yes/no}
- [x] Node 4: Blueprint — {5-Cycle C{N} / Evaluate-Loop PASS}
- [x] Node 5: Rules — {rules loaded}
- [x] Node 6: Tool Shed — {skills applied}
- [x] Node 7: Validation — tsc ✅ lint ✅ tests ✅ quality-gate ✅
- [x] Node 8: PR — {pr-url}

### Stats

- Files changed: {N}
- Lines added: +{N} / removed: -{N}
- Tests added: {N}
- Beads created: {N} (main + {N} discovered)

**Your turn:** Review the PR and merge when satisfied.
```

---

## Rollback Procedure

Triggered by: 3 failed validation retries OR PRE_LAUNCH_GATE failure after fixes.

```bash
# 1. Reset to pre-minion state
git checkout {pre-run-commit-hash} -- {changed files}

# 2. Close bead as failed
bd close {bead-id} --reason "Rollback: {failure reason}" --json

# 3. Create follow-up bead
bd create "Minion rollback: {task}" \
  --description "Minion failed after 3 retries. Root cause: {error}. Needs human investigation." \
  -t bug -p 1 \
  --deps discovered-from:{bead-id} --json

# 4. Remove worktree
git worktree remove worktrees/{bead-id} --force
git branch -D feature/{bead-id}

# 5. Notify
echo "🔴 Minion rolled back. Bead {bead-id} closed. New investigation bead created: {new-bead-id}"
```

---

## Escalation Points (Stop and Notify Human)

| Trigger                                         | Action                                                |
| ----------------------------------------------- | ----------------------------------------------------- |
| Goal ambiguous (>1 interpretation)              | Ask for clarification before doing anything           |
| Board rejects plan                              | Present Board feedback, ask human to decide           |
| 3 validation retries exhausted                  | Execute rollback. Notify human with full failure log. |
| Found bug outside scope                         | Create `discovered-from` bead. Continue task.         |
| Token budget at 25K/30K                         | Summarize state. Request handoff.                     |
| `PRE_LAUNCH_GATE.md` fails after 3 fix attempts | Rollback + human escalation                           |
