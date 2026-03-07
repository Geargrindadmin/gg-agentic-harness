---
description: Install, verify, and configure the claude-mem agentic memory plugin for GGV3
---

# /claude-mem-setup — Agentic Memory System Setup

> **PRD:** `docs/prd/PRD-AGENT-MEMORY.md`  
> **Plugin:** `thedotmack/claude-mem`

---

## Step 1 — Install Plugin (Claude Code only)

Run inside a Claude Code session:

```
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
```

> ⚠️ IMPORTANT: Do NOT use `npm install -g claude-mem` — this installs the SDK only and does NOT register the lifecycle hooks. Always install via `/plugin`.

## Step 2 — Restart Claude Code

Close and reopen Claude Code. The worker service auto-starts on the next launch.

## Step 3 — Verify Worker Service

// turbo
```bash
curl -s http://localhost:37777/health
```

Expected: `{"status":"ok"}` or similar 200 response.

## Step 4 — Verify Runtime Dependencies

// turbo
```bash
bun --version && echo "Bun OK"
uv --version && echo "uv OK"
```

Expected: both print version strings.

## Step 5 — Open Web Viewer

Navigate to http://localhost:37777 in browser. You should see the claude-mem web UI showing sessions and observations.

## Step 6 — Run Warm-Up Session

Perform any natural action in Claude Code (ask a question, read a file). Observations will be captured automatically via PostToolUse hook.

## Step 7 — Test MCP Search

In Claude Code, test that the MCP tools respond:

```
search(query="recent", limit=3)
```

Expected: returns an index (may be empty on first run).

## Step 8 — Verify Full Integration

// turbo
```bash
curl -s http://localhost:37777/api/sessions | head -c 500
```

Expected: JSON array with at least 1 session after warm-up.

---

## Troubleshooting

| Issue | Resolution |
|-------|-----------|
| `curl` returns connection refused | Claude Code not running, or plugin not installed correctly |
| Bun not found | Auto-install failed — run `curl -fsSL https://bun.sh/install \| bash` |
| uv not found | Run `pip install uv` or `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `search()` returns nothing | Normal for first session — run /claude-mem-setup again after 1 natural session |
| Web UI blank | Clear browser cache, try http://localhost:37777 in incognito |

---

## Switch to Beta Channel (Optional)

Beta offers Endless Mode (biomimetic memory for extended sessions):
- Open http://localhost:37777 → Settings → Switch to Beta

---

## Uninstall

```
/plugin uninstall claude-mem
```

No database cleanup needed unless you want to remove `~/.claude-mem/` manually.
