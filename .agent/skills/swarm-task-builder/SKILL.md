---
name: swarm-task-builder
description: >
  Constructs properly structured Kimi swarm agent task prompts. Use whenever
  spawning a swarm via spawn_kimi_agent or spawn_kimi_swarm. Enforces project
  paths, bus protocol compliance, comm line visibility, and git conventions.
triggers:
  - "spawn swarm"
  - "spawn kimi"
  - "dispatch agents"
  - "create swarm task"
  - "write agent prompt"
---

# Swarm Task Builder Skill

## Purpose
Every Kimi agent task prompt MUST include the standard preamble. This skill
ensures all agents write to the right place, communicate correctly through
the bus (so comm lines appear in the macOS Swarm tab), and commit their output.

## Mandatory Checklist (before every spawn_kimi_agent call)

- [ ] Template file read: `.agent/templates/swarm-agent-preamble.md`
- [ ] All `{{PLACEHOLDERS}}` replaced
- [ ] Output path is under `swarm-output/{{RUN_ID}}/` — never `/tmp/`
- [ ] `post_message` with `toId` in payload is specified for inter-agent comms
- [ ] Assembler agent includes `git add + git commit` (NOT git push)
- [ ] Worker agents do NOT commit — only assembler does
- [ ] `worktree` parameter points to project root OR an isolated git worktree under the project

## Swarm Agent Roles

| Role | Commits? | Git push? | Output path |
|------|----------|-----------|-------------|
| **worker** | No | No | `swarm-output/{{RUN_ID}}/` |
| **assembler** | Yes (`git commit`) | No (coordinator pushes) | `swarm-output/{{RUN_ID}}/` |
| **coordinator** (Claude) | N/A | Yes | N/A |

## How to Construct an Agent Task

```
1. Read .agent/templates/swarm-agent-preamble.md
2. Copy preamble text
3. Replace all {{PLACEHOLDERS}}:
   - AGENT_ID    → e.g. sub-07-01
   - RUN_ID      → e.g. run-7e6423d8
   - ROLE        → worker | assembler | scout
   - OUTPUT_FILE → e.g. sub-07-01.json
   - OTHER_AGENT_ID → ID of target agent for inter-agent messages
   - COMMIT_MESSAGE → short description for git commit
   - SUMMARY     → one-line summary for TASK_COMPLETE
4. Append the agent-specific task description below the preamble
5. Pass the combined text as the `task` parameter to spawn_kimi_agent
```

## Comm Lines Integration
For comm lines to appear in the macOS Swarm tab, agents MUST include
`toId` in the payload of any inter-agent message:

```json
// CORRECT — draws a comm line in the Swarm tab
post_message(type="PROGRESS", payload={"toId": "sub-07-02", "message": "..."})

// WRONG — no comm line drawn
post_message(type="PROGRESS", payload={"message": "..."})
```

## Example: 3-Agent Swarm

```
RUN_ID=run-abc123

# Worker 1
task = preamble(AGENT_ID=sub-01-01, ROLE=worker, OUTPUT_FILE=data-01.json) +
"Your specific task: research X and write findings to your output file."

# Worker 2  
task = preamble(AGENT_ID=sub-01-02, ROLE=worker, OUTPUT_FILE=data-02.json) +
"Your specific task: research Y and write findings to your output file.
When done, send a message to sub-01-03 with toId so it knows to start."

# Assembler
task = preamble(AGENT_ID=sub-01-03, ROLE=assembler, OUTPUT_FILE=index.html) +
"Wait for sub-01-01 and sub-01-02 to complete, then read their output files
and generate index.html. Commit with git. HANDOFF_READY when done."
```

## ⚠️ MANDATORY: Coordinator Monitoring After Every Spawn

**IMMEDIATELY after `spawn_kimi_swarm` or `spawn_kimi_agent` returns, Claude MUST call:**

```typescript
get_kimi_output(sessionId, wait=true, timeoutSeconds=<same as spawn timeout>)
```

This call BLOCKS until Kimi signals `HANDOFF_READY` (or times out), then automatically
reports results to the user. **Never leave Kimi running unmonitored** — the user should
not have to ask "is Kimi done?".

### Correct Pattern (ALWAYS do this)

```
1. spawn_kimi_swarm(task, agents, ...) → { sessionId }
2. Confirm to user: "Swarm launched — session X. Waiting for results..."
3. get_kimi_output(sessionId, wait=true, timeoutSeconds=1800)  ← BLOCKS HERE
4. Report results to user automatically when done
5. git pull --rebase && git push
```

### Wrong Pattern (NEVER do this)

```
1. spawn_kimi_swarm(...) → { sessionId }
2. Tell user "should take 20-30 min, check back later"  ← ❌ WRONG
3. Do nothing
4. User has to ask "is Kimi done?" → session already cleaned up → confusion
```

## Post-Swarm: Coordinator Push (Claude handles this)
After `get_kimi_output(wait=true)` returns:
```bash
git pull --rebase
git push
```
