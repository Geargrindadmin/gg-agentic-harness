# Memory Protocol

This document defines the portable memory contract for GG Agentic Harness installs.

## Purpose

Prime session context before planning or coding to reduce duplicate work, preserve decisions, and keep cross-session continuity across Codex, Claude, and Kimi.

Runtime selection is defined in `docs/runtime-profiles.md`.

## Unified Memory Contract

All runtimes use the same 3-layer pattern before planning or coding:

1. `search(query="<task domain> recent", limit=8)`
2. `timeline(id|anchor=<top result>)`
3. `get_observations(ids=[<top 3-5 IDs>])`

Target memory-prime budget: under 3K tokens.

## Fallback Layer 1: `memory` MCP

If the query tools are unavailable, use:

1. `search_nodes(query="<task domain> recent")`
2. `open_nodes(names=[<top 3 entities>])`

## Fallback Layer 2: Worker HTTP API

If MCP tools are unavailable but the worker is reachable:

1. `GET /api/search?query=<task-domain>&limit=8`
2. `GET /api/timeline?query=<task-domain>&limit=8`
3. `POST /api/observations/batch` with selected IDs

If all memory paths are unavailable, proceed and record `status=skipped` with reason in the run artifact.

## Session Checklist

1. Run `npm run harness:runtime-parity`
2. Prime memory using the unified path or a documented fallback
3. Run `bd prime --json`
4. Classify the request (SIMPLE / TASK / DECISION / CRITICAL)
5. Continue into `/go` or `/minion`

## Related

- `docs/runtime-profiles.md`
- `docs/agentic-harness.md`
- `docs/setup/multi-model-control-plane-usage.md` — Usage guide for the multi-model control plane
- `docs/implementation-notes/multi-model-control-plane-implementation.md` — Implementation details
