---
name: go
description: 'The single entry point to the Conductor system - state your goal and everything is handled automatically'
arguments:
  - name: goal
    description: 'Your goal — what you want to build, fix, or change'
    required: false
user_invocable: true
---

# /go — Goal-Driven Entry Point

**The single entry point to the entire Conductor system.**

Just state your goal. The system handles everything else.

## Usage

```
/go <your goal>
```

## Examples

```
/go Add Stripe payment integration
/go Fix the login bug where users get logged out
/go Build a dashboard with analytics
/go Refactor the API layer to use caching
```

## Agentic Layer Nodes (In-Loop Mode)

`/go` operates in **in-loop mode** — human can supervise, steer, and resume at any point. For **fully-unattended out-loop execution**, use `/minion <task>` instead.

| #   | Node             | In-Loop (/go) Status             |
| --- | ---------------- | -------------------------------- |
| 1   | Entry Points     | ✅ CLI / IDE                     |
| 2   | Agent Sandbox    | ✅ Git worktrees (optional)      |
| 3   | Harness          | ✅ Conductor Orchestrator        |
| 4   | Blueprint Engine | ✅ Evaluate-Loop (auto-selected) |
| 5   | Rules / Context  | ✅ Subdirectory-scoped           |
| 6   | Tool Shed        | ✅ intelligent-routing selects   |
| 7   | Validation       | ✅ tsc + lint + tests            |
| 8   | PR Review        | ✅ Human-approved push           |

> See `docs/agentic-harness.md` for full node specifications.

---

## Your Task

You ARE the `/go` entry point. When invoked, follow this process:

### 0. Memory Prime (FIRST — before anything else)

Select runtime profile from `docs/runtime-profiles.md` and apply profile memory rules:

1. `claude` profile: `search -> timeline -> get_observations`
2. `codex` profile: `search_nodes -> open_nodes`
3. `kimi` profile: `search_nodes -> open_nodes`
3. If memory tooling is unavailable, proceed and log `mcpCalls` status as `skipped` in run artifact

Inject retrieved context before goal analysis. This prevents duplicate tracks, surfaces prior Board decisions, and avoids redundant work.

For `TASK|TASK_LITE|DECISION`, also follow remote task protocol:

1. if configured, list remote tasks: `node scripts/gws-task.mjs list --tasklist "$GWS_TASKLIST_ID"`
2. rule source: `.agent/rules/remote-task-tracking.md`
3. ensure project context is current: `npm run harness:project-context:check || npm run harness:project-context`

Initialize run evidence at the start of execution:

```bash
node scripts/agent-run-artifact.mjs init --id go-{timestamp} --runtime {codex|claude|kimi} --classification TASK
# For TASK|TASK_LITE|DECISION: node scripts/gws-task.mjs sync-run --tasklist "$GWS_TASKLIST_ID" --run-id go-{timestamp} --title "<short task title>" --status open
```

### 1. Goal Analysis

Parse the user's goal from `$ARGUMENTS`:

- Identify the type (feature, bugfix, refactor, etc.)
- Estimate complexity
- Extract key requirements

If no arguments provided, check for an active track in `conductor/tracks.md` and resume it. If no active track exists, ask the user what they want to work on.

### 2. Track Detection

Check `conductor/tracks.md` for matching existing tracks:

- If match found: Resume that track from its current state
- If no match: Create a new track

### 3. For New Tracks

1. Create track directory: `conductor/tracks/{goal-slug}_{date}/`
2. Generate `spec.md` from the goal
3. Generate `plan.md` with DAG
4. Create `metadata.json` with v3 schema **AND** set `superpower_enhanced: true` (new tracks use superpowers by default)

**Example metadata.json:**

```json
{
  "version": 3,
  "track_id": "goal-slug_20260213",
  "type": "feature",
  "status": "new",
  "superpower_enhanced": true,
  "loop_state": {
    "current_step": "NOT_STARTED",
    "step_status": "NOT_STARTED"
  }
}
```

### 4. Run the Evaluate-Loop

Invoke the conductor-orchestrator agent to run the full evaluate-loop:

```
Use the conductor-orchestrator agent to run the evaluate-loop for this track.
```

The orchestrator will:

- Detect current step from metadata
- Check `superpower_enhanced` flag to determine which agents to use:
  - **If true (new tracks):** Dispatch superpowers (superpowers:writing-plans, superpowers:executing-plans, superpowers:systematic-debugging)
  - **If false/missing (legacy):** Dispatch legacy loop agents (loop-planner, loop-executor, loop-fixer)
- Monitor progress and handle failures
- Complete the track or escalate if blocked

On completion or terminal failure, finalize run artifact:

```bash
node scripts/agent-run-artifact.mjs complete --id go-{timestamp} --status <success|failed>
# For TASK|TASK_LITE|DECISION: node scripts/gws-task.mjs sync-run --tasklist "$GWS_TASKLIST_ID" --run-id go-{timestamp} --title "<short task title>" --status completed
```

## Workflow Routing Add-Ons

Route to specialized workflows when they match the goal shape:

- `/paperclip-extracted <objective>` for objective-level delivery that needs explicit intake, routing, and stage gates.
- `/symphony-lite <task>` for one isolated autonomous execution path with strict terminal states.
- `/visual-explainer <subject>` when the deliverable includes architecture/diff/audit communication artifacts.

## Escalation Points

Stop and ask user when:

- Goal is ambiguous
- Multiple interpretations possible
- Scope conflicts with existing tracks
- Board rejects the plan
- Fix cycle exceeds 3 iterations

## Resume Existing Work

```
/go                    # Continues the active track
/go continue           # Same as above
```

## What Happens End-to-End

```
User: /go Add a hello world API

1. Goal Analysis → type: feature, complexity: small
2. Track Detection → no existing match
3. Create Track → conductor/tracks/add-hello-world-api_20260216/
   - spec.md generated
   - plan.md generated with DAG
   - metadata.json created
4. Evaluate-Loop begins:
   PLAN → EVALUATE PLAN → EXECUTE → EVALUATE EXECUTION
                                          │
                                     PASS → COMPLETE
                                     FAIL → FIX → re-EVALUATE (loop)
5. Track marked complete
6. Report delivered to user
```

## Related

- `/conductor implement` — Run evaluate-loop on existing track
- `/conductor status` — Check current track progress
- `/conductor new-track` — Create track manually (more control)
- `/paperclip-extracted` — Gated objective routing and execution checklist
- `/symphony-lite` — Single-task autonomous run contract
- `/visual-explainer` — Visual report generation workflow
- `conductor/workflow.md` — Full evaluate-loop documentation (repo-local copy)
- `.agent/conductor-docs/workflow.md` — Authoritative workflow source
