---
name: agentic-status
description: 'Live status dashboard for all 8 GGV3 agentic layer nodes. Shows active beads, sandbox state, blueprint phase, last validation result, and open agent PRs.'
arguments: []
user_invocable: true
aliases:
  - /minion-status
  - /harness-status
---

# /agentic-status — Agentic Layer Status Board

Inspect the live state of all 8 nodes in GGV3's agentic layer.

```
/agentic-status
```

---

// turbo-all

## Execution

When invoked, run all of the following checks and synthesize into the Output Format below.

### NODE 1 — Entry Points

```bash
# Check for recent coordinator activity
ls .agent/logs/ 2>/dev/null | head -20
# Active workflows that were recently invoked
git log --oneline --grep="\[agent:" --since="24 hours ago" | head -10
```

### NODE 2 — Active Sandboxes

```bash
# List all active worktrees
git worktree list

# Check for claimed files (File-Claim Protocol)
ls .agent/logs/*.jsonl 2>/dev/null | tail -5
```

### NODE 3 — Harness State

```bash
# Active beads (in-progress work)
bd ready --json 2>/dev/null | head -50

# All open beads
bd list --status=open --json 2>/dev/null | head -100
```

### NODE 4 — Blueprint Phase

```bash
# Active conductor tracks
ls conductor/tracks/ 2>/dev/null
cat conductor/tracks/*/metadata.json 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        print(f\"Track: {d.get('track_id')} | Status: {d.get('status')} | Step: {d.get('loop_state',{}).get('current_step','?')}\")
    except: pass
" 2>/dev/null
```

### NODE 5 — Rules Loaded

```bash
# List active rule files
ls .agent/rules/*.md 2>/dev/null
```

### NODE 6 — Tool Shed Health

```bash
# Count available skills
ls .agent/skills/ | wc -l

# Count available workflows
ls .agent/workflows/ | wc -l

# Count available agents
ls AGENTS/*.md | wc -l
```

### NODE 7 — Last Validation Results

```bash
# Last TypeScript check
npx tsc --noEmit 2>&1 | tail -5 && echo "TSC: ✅" || echo "TSC: ❌"

# Last lint check
npm run lint 2>&1 | tail -3 && echo "LINT: ✅" || echo "LINT: ❌"

# Last test run result (from git log)
git log --oneline --grep="tests" -n 3
```

### NODE 8 — Open Agent PRs

```bash
# PRs created by minion agents
gh pr list --label "agent" 2>/dev/null || \
gh pr list --search "[Minion]" 2>/dev/null | head -10
```

---

## Output Format

Synthesize all checks into this report:

```markdown
## 🤖 GGV3 Agentic Layer — Status Board

**As of:** {timestamp}

### NODE 1 — Entry Points

| Entry              | Status          |
| ------------------ | --------------- |
| CLI (/minion, /go) | ✅ Available    |
| GearBox Web UI     | {status}        |
| Coordinator Bus    | {active / idle} |

### NODE 2 — Active Sandboxes

| Worktree        | Branch   | Age    |
| --------------- | -------- | ------ |
| {worktree path} | {branch} | {time} |

**In-progress files (claimed):** {list or "none"}

### NODE 3 — Harness

**Active Beads:**
| ID | Title | Priority | Status |
|---|---|---|---|
| {bead-id} | {title} | {priority} | {status} |

**Orphaned beads:** {count} — {list or "none"}

### NODE 4 — Blueprint Phase

| Track      | Type   | Current Step | Status   |
| ---------- | ------ | ------------ | -------- |
| {track_id} | {type} | {step}       | {status} |

**No active tracks:** {if applicable}

### NODE 5 — Rules

**Active rules:** {count} files loaded
**Anti-mocking:** ✅ | **Push policy:** ✅ | **Traceability:** ✅

### NODE 6 — Tool Shed

| Resource    | Count | Health |
| ----------- | ----- | ------ |
| Skills      | {N}   | ✅     |
| Workflows   | {N}   | ✅     |
| Agents      | {N}   | ✅     |
| MCP Servers | {N}   | ✅     |

### NODE 7 — Last Validation

| Gate         | Result            | Last Run |
| ------------ | ----------------- | -------- |
| TypeScript   | {✅/❌}           | {time}   |
| ESLint       | {✅/❌}           | {time}   |
| Tests        | {✅/❌}           | {time}   |
| Quality Gate | {✅/❌ / not run} | {time}   |

### NODE 8 — Open Agent PRs

| PR   | Title   | Status       | Created |
| ---- | ------- | ------------ | ------- |
| #{N} | {title} | {draft/open} | {time}  |

**No open agent PRs** {if applicable}

---

### 📋 Action Items

{List any issues found: orphaned beads, failing gates, stale sandboxes, draft PRs awaiting review}

### 🚀 Ready to Run
```

/minion <your next task>

```

```
