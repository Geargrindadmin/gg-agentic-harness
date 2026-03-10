# PRD — Headless One-Shot Product Harness

**Document ID:** PRD-HEADLESS-ONE-SHOT-PRODUCT-HARNESS  
**Version:** 0.1  
**Date:** 2026-03-09  
**Status:** Draft  
**Owners:** Agentic Systems, Platform Engineering  
**Primary Repo:** `gg-agentic-harness`  
**Downstream Install Target:** `GGV3` after completion  
**Related:** `docs/agentic-harness.md`, `docs/prd/PRD-GG-CLI-PORTABLE-HARNESS.md`, `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`

## 1. Problem

`gg-agentic-harness` already contains real building blocks:

- `gg-cli`,
- `gg-core`,
- `gg-orchestrator`,
- runtime adapters,
- `gg-control-plane-server`,
- skills/workflows,
- portable install flows,
- an optional macOS control surface.

But it does not yet function as a complete headless product-execution system that can take a prompt or PRD and reliably produce a functional enterprise web product in one pass.

Current gaps:

1. the flagship entry points are only partially executable,
2. prompt or PRD inputs are not normalized into a strict canonical product spec,
3. the system does not yet constrain generation to supported product lanes,
4. "enterprise-level output" is not encoded as deterministic packs and gates,
5. downstream repos such as `GGV3` cannot yet rely on the harness as a one-shot product builder.

## 2. Product Goal

Turn `gg-agentic-harness` into a headless execution product that:

1. accepts either a structured PRD or a sufficiently rich prompt,
2. normalizes that input into a canonical product spec,
3. selects a supported delivery lane and enterprise packs,
4. executes the build path headlessly through CLI/MCP/control-plane primitives,
5. emits a functional, buildable, testable output bundle,
6. can then be installed into downstream repos such as `GGV3`.

## 3. Brainstorm Summary

### 3.1 Purpose

The harness is not meant to be another chat wrapper. It is meant to be:

- a headless product operator,
- a deterministic run engine,
- a reusable installation artifact,
- a portable system that downstream projects consume.

### 3.2 Users

Primary users:

1. platform engineers building and hardening the harness itself,
2. teams who want to install the harness into a product repo,
3. operators who want one-shot product generation from a spec or prompt.

Secondary users:

1. downstream repos such as `GGV3`,
2. CI and automation pipelines,
3. optional UI clients such as the macOS control surface.

### 3.3 Headless Definition

Headless means the product must work without:

- the macOS app,
- a browser dashboard,
- an IDE extension,
- manual conversational choreography.

The primary runtime surfaces must be:

1. `gg` CLI,
2. MCP tools,
3. the harness control-plane server,
4. scripts and CI.

The macOS app is explicitly an optional client over the same control plane, not a dependency for core operation.

### 3.4 One-Shot Definition

One-shot does not mean "arbitrary software from any sentence."

One-shot means:

1. the input can be normalized safely,
2. the requested product fits a supported lane,
3. the stack and enterprise packs are chosen from approved templates,
4. the harness can plan, build, validate, and package without needing interactive design intervention,
5. the run exits with a deterministic terminal status and artifact bundle.

### 3.5 Enterprise-Level Definition

For this harness, enterprise-level output means:

1. secure defaults,
2. typed contracts,
3. accessibility baseline,
4. error states and graceful degradation,
5. observability hooks,
6. validation evidence,
7. deployment and operations notes,
8. reproducible docs and artifacts.

### 3.6 Scope Discipline

V1 must not attempt universal product generation.

V1 must support a narrow, high-confidence set of product lanes:

1. marketing site,
2. SaaS dashboard,
3. internal admin panel,
4. API-backed CRUD shell,
5. content or documentation portal.

### 3.7 Repo Boundary

This PRD applies to `gg-agentic-harness`, not `GGV3`.

Rules:

1. implementation belongs in `gg-agentic-harness`,
2. `GGV3` is a downstream consumer and validation environment,
3. no harness-defining functionality should be built first in `GGV3`,
4. once the harness is complete, it should be installed into `GGV3` through the harness portability flow.

## 4. Objectives

1. Make `gg-agentic-harness` the source-of-truth implementation repo for the finished headless harness.
2. Make `gg go`, `gg minion`, and `gg agentic-status` real executable operator surfaces.
3. Add prompt/PRD normalization into a canonical product spec.
4. Add supported product lanes and enterprise packs as machine-readable contracts.
5. Add deterministic build, verification, and artifact bundling.
6. Prove the harness in its own repo before installing it into `GGV3`.

## 5. Inputs

The harness must support three input classes.

### A. Raw Prompt

Example:

```text
Build a vendor analytics SaaS dashboard with RBAC, Stripe billing, audit logs, and a deployment-ready admin shell.
```

### B. PRD File

Accepted forms:

- `docs/prd/*.md`,
- external markdown file,
- normalized spec file generated by a previous run.

### C. Prompt + Constraints

Additional flags may include:

- product lane,
- target stack,
- runtime preference,
- deployment target,
- required integrations,
- required enterprise packs.

## 6. Outputs

A successful run must leave:

1. generated or updated code,
2. a canonical spec,
3. an implementation plan,
4. run artifacts,
5. validation evidence,
6. delivery docs,
7. a deterministic terminal status:
   - `HANDOFF_READY`,
   - `BLOCKED`,
   - `FAILED`.

## 7. Supported Product Lanes

### V1 Mandatory Lanes

The first release must prove these three lanes end-to-end:

1. `marketing-site`
2. `saas-dashboard`
3. `admin-panel`

The remaining lanes are part of the supported contract, but are not required for first certification.

### Lane 1: Marketing Site

Required baseline:

- responsive design,
- SEO metadata,
- analytics hook points,
- accessibility baseline,
- performance-oriented defaults.

### Lane 2: SaaS Dashboard

Required baseline:

- authenticated app shell,
- navigation system,
- empty/loading/error states,
- typed API integration layer,
- admin/operator-friendly information architecture.

### Lane 3: Internal Admin Panel

Required baseline:

- RBAC-ready structure,
- audit-friendly views,
- operational controls,
- high-signal status and monitoring surfaces.

### Lane 4: API-Backed CRUD Shell

Required baseline:

- typed resource contracts,
- list/detail/edit/create flows,
- forms and validation,
- buildable API integration structure.

### Lane 5: Documentation or Content Portal

Required baseline:

- navigation,
- search-ready structure,
- docs rendering,
- maintainable content organization.

## 8. Enterprise Packs

Enterprise packs must be machine-readable and composable.

Initial pack set:

1. `auth-rbac`
2. `billing-stripe`
3. `observability`
4. `compliance-baseline`
5. `design-system`
6. `notifications`
7. `cms-content`
8. `admin-ops`

### V1 Unattended Pack Policy

The first release must support these packs for fully unattended runs:

1. `design-system`
2. `observability`
3. `auth-rbac`

The following packs are allowed in V1 only behind stricter review and preflight constraints:

1. `billing-stripe`
2. `compliance-baseline`
3. `notifications`
4. `cms-content`
5. `admin-ops`

Each pack must define:

1. compatible lanes,
2. required config,
3. generated files or templates,
4. extra gates,
5. review requirements if high-risk.

## 9. Functional Requirements

### 9.1 Headless Operator Commands

The harness must provide executable headless commands for:

1. `gg workflow run go <goal>`
2. `gg workflow run minion <task>`
3. `gg workflow run agentic-status`
4. `gg product normalize <prompt|path>`
5. `gg product build <spec>`
6. `gg product verify <run-id|path>`

These may be implemented under existing command families or new command families, but must remain headless and deterministic.

### 9.2 Canonical Product Spec

The harness must normalize input into a canonical spec containing:

1. lane,
2. stack,
3. packs,
4. risk tier,
5. constraints,
6. acceptance criteria,
7. validation profile,
8. delivery target.

### 9.3 Lane Resolution

If lane is not explicit, the harness must:

1. infer the lane with confidence scoring,
2. proceed only when confidence is above threshold,
3. otherwise exit `BLOCKED` with a concrete reason.

### 9.4 Approved Stack Templates

Generation must be limited to approved templates.

Examples:

1. `nextjs-app-router + typescript + tailwind + shadcn/ui`
2. `vite-react + typescript + node/express`
3. `mdx-docs-site`

### 9.5 Planner

The planner must generate:

1. normalized spec,
2. selected packs,
3. execution plan,
4. validation plan,
5. rollback strategy,
6. artifact bundle map.

### 9.6 Executor

The executor must:

1. use deterministic paths whenever possible,
2. use agentic reasoning only where appropriate,
3. emit continuous evidence,
4. enforce bounded retries,
5. stop on unresolved failures.

### 9.7 Resume

Interrupted runs must be resumable from artifact state.

### 9.8 Downstream Install Compatibility

The finished harness must remain installable into a downstream repo using:

1. `portable init`,
2. runtime activation commands,
3. install scripts such as `scripts/install-from-github.sh`.

## 10. Non-Functional Requirements

1. headless-first,
2. deterministic exit codes,
3. JSON output for machine use,
4. runtime-agnostic orchestration contract across `codex`, `claude`, and `kimi`,
5. no hidden reliance on the macOS client,
6. evidence-first operation,
7. portable installation into downstream repos.

## 11. Architecture Fit Within This Repo

### Primary Packages

1. `packages/gg-core`
2. `packages/gg-cli`
3. `packages/gg-orchestrator`
4. `packages/gg-runtime-adapters`
5. `packages/gg-control-plane-server`
6. `mcp-servers/gg-skills`

### Execution Principle

The real runtime must live in code, not in markdown workflow files.

Workflow markdown remains:

1. contract,
2. operator documentation,
3. prompt/runtime guidance.

Executable behavior must live in shared TypeScript runtime modules and be invoked by CLI/control-plane surfaces.

### Control Surface Principle

The macOS app in `apps/macos-control-surface` is a client.

It may display:

- status,
- swarm data,
- worktrees,
- settings,
- terminal surfaces.

But it must not be a requirement for one-shot product execution.

## 12. Validation and Quality Gates

### Global Gates

1. build or type-check,
2. lint,
3. targeted tests,
4. artifact completeness,
5. documentation bundle presence.

### Product-Specific Gates

Depending on lane and packs:

1. accessibility checks,
2. UI smoke or browser checks,
3. API contract checks,
4. security baseline checks,
5. deploy preflight.

## 13. One-Shot Readiness Contract

A run is one-shot ready only if:

1. input normalization succeeds,
2. a supported lane is selected,
3. an approved stack template is chosen,
4. required packs are available,
5. runtime activation is valid,
6. deterministic gates pass,
7. delivery docs and artifacts are emitted,
8. unresolved risks are either absent or explicitly surfaced.

## 14. Out of Scope for V1

1. arbitrary software generation outside supported lanes,
2. native mobile products,
3. unconstrained infrastructure mutation,
4. silent best-guess execution on ambiguous prompts,
5. GUI-first harness operation.

## 15. Success Metrics

1. `gg workflow run go "<goal>"` returns a real terminal result for supported lanes.
2. `gg workflow run minion "<task>"` executes a real unattended path.
3. `gg workflow run agentic-status --json` reports activation, drift, and run state accurately.
4. At least three supported lanes can be generated headlessly with passing gates.
5. The harness can be installed into `GGV3` and run the same contract there.

## 16. Risks and Mitigations

### Risk 1: Prompt vagueness produces poor builds

Mitigation:

- canonical spec normalization,
- lane confidence thresholds,
- explicit `BLOCKED` outcomes.

### Risk 2: Workflow docs diverge from execution behavior

Mitigation:

- shared execution engine in code,
- adapter smoke tests,
- markdown treated as contract only.

### Risk 3: Runtime config drift breaks real usage

Mitigation:

- hard status checks,
- activation drift detection,
- repo-root consistency validation.

### Risk 4: Optional UI client becomes accidental dependency

Mitigation:

- headless command parity first,
- control-plane server remains canonical,
- macOS app treated as optional client only.

## 17. Open Questions

1. V1 mandatory lanes are `marketing-site`, `saas-dashboard`, and `admin-panel`.
2. V1 unattended packs are `design-system`, `observability`, and `auth-rbac`.
3. The harness must validate against an internal fixture corpus first; `GGV3` is the downstream install proof after the harness passes its own benchmark suite.
