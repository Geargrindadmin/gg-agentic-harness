# PRD — GG CLI + Portable Harness + Priority Integrations

**Document ID:** PRD-GG-CLI-PORTABLE-HARNESS  
**Version:** 1.3  
**Date:** 2026-03-08  
**Status:** Implemented for Priority Wave  
**Owners:** Platform Engineering, Agentic Systems

## 1. Problem

The harness now has a stable CLI scaffold and core workflow adapters, but high-impact external integration work is not yet productized. This creates a gap between current capability and desired context quality, intake quality, reporting quality, and sidecar orchestration.

## 2. Objectives

1. Pilot `CodeGraphContext` to improve code-context quality for complex tasks.
2. Upgrade `visual-explainer` from a basic artifact generator to an evidence-linked reporting surface.
3. Add a runtime-agnostic prompt-improver intake workflow based on `claude-code-prompt-improver` patterns.
4. Integrate `Hydra` as an optional sidecar behind feature flags and strict guardrails.
5. Preserve runtime parity (`codex`, `claude`, `kimi`) and deterministic gate semantics.
6. Keep docs and governance contracts accurate before implementation starts.

## 3. Baseline (Current State as of 2026-03-08)

1. Executable adapters exist for:
- `paperclip-extracted`
- `prompt-improver`
- `symphony-lite`
- `visual-explainer`
- `full-doc-update`
- `hydra-sidecar`
- `go` intake routing
2. `visual-explainer` now ingests run artifacts, changed files, validation signals, and citation blocks for `architecture`, `diff-review`, and `audit-recap` modes.
3. `CodeGraphContext` is now represented as an optional runtime contract and pilot context source with fallback to the standard path.
4. The verified host prerequisite for live `CodeGraphContext` in the harness is the `cgc` CLI, installed with `uv tool install --python python3.13 codegraphcontext` on this machine.
5. Prompt-improver intake workflow is now a first-class harness workflow and optional pre-step for `/go` and `paperclip-extracted`.
6. Hydra sidecar is now wired as a feature-flagged optional execution path with `off|shadow|active` modes.

## 4. Scope

### In Scope (Priority Wave)

1. `CodeGraphContext` pilot integration.
2. `visual-explainer` upgrade.
3. Runtime-agnostic prompt-improver intake workflow.
4. `Hydra` sidecar shadow/active modes behind feature flags.
5. PRD, architecture docs, setup docs, and workflow docs aligned to true state.

### Out of Scope (This Wave)

1. Non-priority candidate repositories from the prior long list.
2. Replacement of core harness engine with Hydra or any sidecar.
3. Unbounded autonomous research loops in production paths.

## 5. Functional Requirements

### A. CodeGraphContext Pilot

1. Add profile-level runtime contract entries for optional `CodeGraphContext` usage.
2. Add harness execution path to request graph context when enabled.
3. Record context source in run artifacts (`contextSource: standard|codegraphcontext|hybrid`).
4. Add fallback to standard memory/context path on tool failure.

### B. Visual Explainer Upgrade

1. Extend `workflow run visual-explainer` adapter to ingest evidence from:
- run artifacts
- changed files
- validation outputs
2. Add explainer modes (`architecture`, `diff-review`, `audit-recap`) with deterministic section templates.
3. Add explicit citation block in output linking claims to local files/commands.
4. Preserve `docs/reports/*.md` + `*.html` outputs.

### C. Prompt-Improver Intake Workflow

1. Add a new workflow slug for intake improvement (runtime-agnostic).
2. Accept raw user objective and return:
- normalized objective
- constraints
- acceptance criteria
- risk flags
3. Integrate as optional pre-step for `/go` and `paperclip-extracted`.
4. Keep the workflow deterministic and avoid runtime-specific prompt hooks.

### D. Hydra Sidecar (Feature-Flagged)

1. Add sidecar mode flags:
- `HARNESS_HYDRA_MODE=off|shadow|active`
2. `off`: no Hydra calls.
3. `shadow`: record what Hydra would route, no execution delegation.
4. `active`: allow delegated routing where policy permits.
5. Always preserve deterministic gate ownership in harness core.
6. Record sidecar decisions/events in run artifacts.
7. Before any sidecar decision or routing recommendation, require dual-research evidence:
- codebase evidence (repo paths/pattern findings)
- internet evidence (dated external sources)
8. If either evidence set is missing, fail closed to native harness routing.

## 6. Non-Functional Requirements

1. No regression to existing deterministic gates.
2. Runtime parity checks must pass after each stream integration.
3. Feature flags must default to safe mode (`off`).
4. Failure behavior must be bounded and auditable.
5. New docs must distinguish:
- implemented
- pilot
- planned
6. Setup docs must name external host prerequisites explicitly when optional pilots depend on local binaries.

## 7. Architecture and Governance Impacts

1. Update integration architecture docs to show only active priority wave.
2. Update workflow docs where completion/reporting behavior changes.
3. Keep `docs/agentic-harness.md` as authoritative node contract.
4. Update setup docs and README command lists for adapter accuracy.
5. Keep Codex repo-scope activation and optional `CodeGraphContext` host requirements explicit in setup docs.

## 8. Acceptance Criteria

1. Priority action plan exists with phases, dependencies, and gates.
2. PRD and referenced docs reflect the implemented baseline.
3. `CodeGraphContext` pilot design is documented with fallback contract, runtime contract entries, and verified host installation requirements.
4. Visual explainer upgrade is executable with evidence-linking and citations.
5. Prompt-improver workflow is executable with normalized intake schema.
6. Hydra sidecar supports `off|shadow|active` behavior and guardrails.
7. Runtime parity and harness lint are runnable after the integration pass.
8. Sidecar decision policy explicitly enforces dual-research evidence before routing decisions.

## 9. Rollout Plan

### Phase 0 — Documentation and Design Freeze

1. Land PRD v1.3 and integration action plan.
2. Align setup/governance/README wording to baseline truth.
3. Confirm no docs claim implementation that does not yet exist.

### Phase 1 — CodeGraphContext Pilot

1. Add config and profile contracts.
2. Implement optional context path and fallback behavior.
3. Capture pilot metrics in run artifacts.

### Phase 2 — Visual Explainer Upgrade

1. Extend adapter output model and evidence ingestion.
2. Add mode-specific templates.
3. Validate with at least one architecture and one diff-review report.

### Phase 3 — Prompt-Improver Intake Workflow

1. Add workflow contract + adapter.
2. Integrate optional invocation path in `/go` and `paperclip-extracted`.
3. Validate deterministic outputs across runtimes.

### Phase 4 — Hydra Sidecar

1. Add feature flag and shadow mode first.
2. Add active mode with policy gates.
3. Validate fallback behavior and event traceability.

## 10. Risks and Mitigations

1. Context overfitting or noisy graph context:
- Mitigation: optional pilot mode + fallback path + artifact telemetry.
2. Prompt normalization drift:
- Mitigation: deterministic output schema + acceptance criteria checks.
3. Sidecar complexity and routing ambiguity:
- Mitigation: `off` default, shadow-first rollout, explicit policy ownership.
4. Documentation drift during phased rollout:
- Mitigation: require `/full-doc-update` report at phase completion.

## 11. Success Metrics

1. Reduced rework from missing context in complex code tasks.
2. Higher-quality handoff/explainer artifacts with source-linked claims.
3. Better intake clarity (fewer ambiguous task starts).
4. Zero parity regressions while adding optional sidecar capability.

## 12. Addon Candidate (Under Evaluation)

Repository: `jovanSAPFIONEER/Network-AI`

Decision: approved for **pilot evaluation only** as optional sidecar augmentation, not as harness-core replacement in this wave.

Pilot contract:

1. Shadow-first mode.
2. Reversible feature flag.
3. Deterministic harness gate ownership remains unchanged.
4. Governance review required before any active delegation.
5. Governance decision must include codebase citations plus dated internet citations.
