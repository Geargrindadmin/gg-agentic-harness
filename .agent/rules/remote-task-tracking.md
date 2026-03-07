# Remote Task Tracking — Google Workspace CLI

This rule standardizes remote task tracking across all runtime profiles (`codex`, `claude`, `kimi`) using Google Tasks via `gws`.

## Intent

`Task.md` remains the detailed local execution ledger.
Google Tasks is the remote operational queue for visibility and remote access.

## Required Environment

At least one auth method must be configured:

1. `GOOGLE_WORKSPACE_CLI_TOKEN`, or
2. local OAuth session for `gws`.

Required list identifier:

1. `GWS_TASKLIST_ID` (preferred), or
2. create/find default list with:
   - `npm run task:remote:ensure-default`

## Mandatory Usage Rules

For request classes `TASK`, `TASK_LITE`, and `DECISION`:

1. Session start:
   - list remote tasks:
     - `node scripts/gws-task.mjs list --tasklist "$GWS_TASKLIST_ID"`
2. After run artifact init:
   - upsert remote run task with `open` status:
     - `node scripts/gws-task.mjs sync-run --tasklist "$GWS_TASKLIST_ID" --run-id "<run-id>" --title "<short task title>" --status open --notes "bead:<id>"`
3. Completion:
   - mark remote run task `completed`:
     - `node scripts/gws-task.mjs sync-run --tasklist "$GWS_TASKLIST_ID" --run-id "<run-id>" --title "<short task title>" --status completed`

## Fallback Behavior

If Google Workspace CLI auth/list config is unavailable:

1. Continue with local `Task.md` + `bd` flow.
2. Record skip reason in run artifact (CLI unavailable/auth missing/list missing).
3. Do not claim remote tracking completed.

## Scope

This rule is process-only. It does not replace:

1. `bd` lifecycle requirements.
2. `Task.md` checklists and acceptance criteria.
3. validation gates.
