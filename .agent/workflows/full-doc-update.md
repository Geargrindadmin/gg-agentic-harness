---
name: full-doc-update
description: 'Post-task documentation synchronization workflow. Updates mandatory and impact-driven docs after code changes.'
arguments:
  - name: task_summary
    description: 'Short summary of the task just completed.'
    required: false
user_invocable: true
---

# /full-doc-update — Post-Task Documentation Sync

Use this workflow after any completed task to keep repository documentation current.

## Usage

```bash
/full-doc-update <optional task summary>
```

## Goal

1. Detect what changed.
2. Map changes to required documentation updates.
3. Update mandatory docs every time.
4. Update conditional docs when relevant.
5. Produce a concise docs delta report.

## Step 1 — Collect Change Context

Run:

```bash
git status --short
git diff --name-only HEAD~1..HEAD
```

If task summary is omitted, infer from changed files and latest commit message.

## Step 2 — Always-Update Docs (Every Task)

Update these every task:

1. `Task.md`
2. `CHANGELOG.md` (or `docs/project/changelog.md` if that is the canonical running log)

For each update:

1. Record what changed.
2. Record validation run (at minimum: `tsc`, tests or targeted tests).
3. Record follow-ups that are intentionally out of scope.

## Step 3 — Conditional Docs Matrix (Impact-Driven)

Update based on change type:

1. API route, DTO, contract changes:
   - `docs/api/*`
   - `docs/contracts/*`
   - `docs/API_INVENTORY.md`
2. Architecture/module boundary changes:
   - `docs/architecture/*`
   - ADR in `docs/decisions/*` (or `docs/arch/decisions/*`)
3. Infra/secrets/env/runtime changes:
   - `.env.example`
   - `docs/setup/*`
   - `docs/runbooks/secret-rotation.md` when secret handling policy changes
4. Security/auth/payments/compliance changes:
   - `docs/governance/*`
   - `docs/security/*`
   - relevant ADR
5. Operational behavior (queues, workers, alerting, incidents):
   - `docs/runbooks/*`
   - `docs/operations/*`
6. Developer workflow/process/tooling changes:
   - `README.md`
   - `CONTRIBUTING.md`
   - `AGENTS.md` and `CLAUDE.md` when agent workflow/rules change
7. Product strategy/theory level shifts:
   - `docs/whitepapers/*` (major changes only, not routine bug fixes)

## Step 4 — No-Drift Checks

Before finishing:

1. Ensure docs match behavior (no stale endpoints, env vars, or command examples).
2. Ensure newly introduced env vars/secrets are documented.
3. Ensure any removed feature/process has docs updated or deprecated.

Suggested checks:

```bash
rg -n "TODO|TBD|FIXME" docs README.md CONTRIBUTING.md Task.md
rg -n "STRIPE_|JWT_|API_KEY|SECRET" .env.example docs
```

## Step 5 — Completion Output

Return a report in this format:

```markdown
## Documentation Sync Report

- Task: <summary>
- Mandatory docs updated: <list>
- Conditional docs updated: <list>
- Docs intentionally not updated: <list + rationale>
- Residual follow-ups: <list>
```

## Guardrails

1. Do not create placeholder docs without actionable content.
2. If a required doc is missing, create it and add minimal high-signal content.
3. If change impact is unclear, default to updating `Task.md` + `CHANGELOG.md` and add a follow-up item.
