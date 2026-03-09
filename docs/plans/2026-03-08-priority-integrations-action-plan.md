# Priority Integrations Action Plan

Date: 2026-03-08  
Scope: `CodeGraphContext` pilot, `visual-explainer` upgrade, prompt-improver intake workflow, `Hydra` sidecar.

## 1. Planning Principles

1. Docs-first: no implementation stream starts until the contract docs are accurate.
2. Safety by default: optional integrations default to off/fallback paths.
3. Runtime parity: every stream validates behavior across `codex`, `claude`, `kimi`.
4. Deterministic evidence: every stream emits run-artifact evidence and verification output.

## 2. Current Baseline (Verified)

1. `gg workflow run` executable adapters:
- `paperclip-extracted`
- `prompt-improver`
- `symphony-lite`
- `visual-explainer`
- `full-doc-update`
- `hydra-sidecar`
- `go` intake routing
2. `visual-explainer` now ingests run artifacts, changed files, validation signals, and explicit citations.
3. `CodeGraphContext`, prompt-improver workflow, and Hydra sidecar are implemented as safe, optional harness paths.

## 3. Workstreams and Sequence

Status update: the four priority streams are now wired. Remaining work is hardening, telemetry tuning, and any future promotion of the `Network-AI` pilot lane.

## Workstream A — CodeGraphContext Pilot (Highest Impact)

### Deliverables

1. Runtime profile contract update for optional `CodeGraphContext`.
2. Pilot path in context-loading flow with explicit fallback.
3. Run artifact extension for context-source telemetry.
4. Pilot evaluation report with quality deltas and failure patterns.

### Dependencies

1. Finalized MCP contract shape.
2. Fallback contract approved in harness docs.

### Exit Gate

1. Pilot can be enabled/disabled without behavior breakage.
2. Runs record source attribution (`standard|codegraphcontext|hybrid`).
3. Runtime parity smoke still passes.

## Workstream B — Visual Explainer Upgrade (Fast Win)

### Deliverables

1. Upgraded adapter with evidence ingestion from run artifacts + changed files + validation outputs.
2. Mode-based templates:
- architecture
- diff-review
- audit-recap
3. Output contract updated in workflow doc and README examples.

### Dependencies

1. Stable run artifact schema references.
2. Report template decisions approved.

### Exit Gate

1. Two sample explainers generated from real repo state.
2. Every major claim includes a source reference block.

## Workstream C — Prompt-Improver Intake Workflow

### Deliverables

1. New workflow slug and contract for prompt improvement intake.
2. Deterministic output schema:
- normalized objective
- constraints
- acceptance criteria
- risk flags
3. Optional integration path in `/go` and `paperclip-extracted`.

### Dependencies

1. Intake schema approval.
2. Workflow adapter contract approved in PRD.

### Exit Gate

1. Output is stable for equivalent inputs.
2. Runtime-agnostic behavior verified.
3. No Claude-specific assumptions remain.

## Workstream D — Hydra Sidecar (Feature-Flagged)

### Deliverables

1. Sidecar mode config:
- `HARNESS_HYDRA_MODE=off|shadow|active`
2. Shadow mode event logging in run artifacts.
3. Active mode routing for eligible tasks only.
4. Fallback and timeout policy with deterministic recovery.

### Dependencies

1. Policy boundary definition for allowed delegated tasks.
2. Sidecar availability and health-check contract.

### Exit Gate

1. `off` mode is default and safe.
2. `shadow` mode logs routes without execution delegation.
3. `active` mode can be reverted instantly to `off`.

## 4. Cross-Stream Governance Gates

1. `npm run harness:runtime-parity`
2. `npm run harness:persona:audit`
3. `npm run gg:build`
4. `npm run gg -- workflow list`
5. `/full-doc-update` report generated at each phase close.

## 5. Documentation Update Checklist (Before Implementation per Stream)

1. PRD updated for stream scope and acceptance criteria.
2. `docs/agentic-harness.md` updated for node-level behavior changes.
3. Workflow contracts updated under `.agent/workflows`.
4. Setup/README command examples updated if CLI behavior changed.
5. Architecture docs show implemented vs planned status clearly.

## 6. Opportunity Log

1. Add a deterministic `docs-sync` gate to the logic-loop diagram and Node 7 sequence so docs completion is explicit, not implied.
2. Add a single `integration-status.md` dashboard to reduce drift between PRD, architecture docs, and workflow contracts.
3. Extend run-artifact schema with `integrationFlags` and `contextSource` now, before multiple streams land.
4. Evaluate `Network-AI` as a shadow-first addon sidecar to compare control-plane telemetry against planned Hydra behavior.

## 7. Suggested Execution Order

1. Workstream A (CodeGraphContext pilot)
2. Workstream B (visual-explainer upgrade)
3. Workstream C (prompt-improver intake)
4. Workstream D (Hydra sidecar)

Rationale: highest context-quality gain first, fastest visible value second, intake normalization third, and highest operational risk last.

## 8. Addon Pilot Lane (Network-AI)

This lane does not alter the priority sequence above.

1. Run `/network-ai-pilot "<objective>"` in shadow mode only.
2. Capture telemetry comparison and fallback behavior in run artifacts.
3. Present findings to governance before enabling any active mode.
4. If overlap with Hydra is high and measurable benefit is low, keep as optional addon only.
