# Headless One-Shot Product Harness Action Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the finished headless product harness in `gg-agentic-harness`, prove it inside this repo, and only then install it into `GGV3` as a downstream consumer.

**Architecture:** Keep workflow markdown as contracts, but move actual behavior into shared TypeScript runtime modules across `gg-core`, `gg-cli`, `gg-orchestrator`, `gg-runtime-adapters`, and the control-plane server. The macOS app remains optional. The finished product is a headless harness that can take a prompt or PRD and produce a supported enterprise web product with evidence and terminal outcomes.

**Tech Stack:** TypeScript, Node.js CLI tooling, control-plane HTTP server, existing run artifact scripts, runtime activation scripts, machine-readable registries, markdown PRDs, JSON schemas.

---

## Brainstorm Decisions

### Decision 1: Source-of-Truth Repo

**Question:** Where should the finished harness be implemented?

**Decision:** `gg-agentic-harness` only.

**Reasoning:** This repo is the product. `GGV3` is a consumer. Building core harness logic in the consumer repo would create drift immediately.

### Decision 2: Product Shape

**Question:** Is the product an IDE or a headless execution engine?

**Decision:** The product is a headless execution engine first. Optional UI surfaces come second.

**Reasoning:** Headless operation is the core requirement. UI clients can sit on top of that later.

### Decision 3: Execution Runtime

**Question:** What is the actual runtime: workflow markdown or code?

**Decision:** Code. Workflow markdown remains contract and guidance only.

**Reasoning:** A headless product needs deterministic code paths, exit codes, and artifacts.

### Decision 4: One-Shot Scope

**Question:** Should the harness attempt arbitrary software generation?

**Decision:** No. V1 is constrained to supported enterprise web-product lanes.

**Reasoning:** Constrained lanes make quality and reliability measurable.

### Decision 5: Downstream Proof

**Question:** When should `GGV3` be involved?

**Decision:** After the harness is functional in its own repo.

**Reasoning:** `GGV3` should validate installability and downstream behavior, not serve as the development ground for harness internals.

### Decision 6: V1 Certification Targets

**Question:** Which lanes and packs must be proven first?

**Decision:** Mandatory lanes are `marketing-site`, `saas-dashboard`, and `admin-panel`. Unattended V1 packs are `design-system`, `observability`, and `auth-rbac`.

**Reasoning:** These give the harness a credible enterprise web-product baseline without overcommitting to the highest-risk domains first.

---

## Program Order

1. Freeze the product contract in this repo.
2. Eliminate runtime drift and activation ambiguity.
3. Build the shared headless execution engine.
4. Make `agentic-status` executable and trustworthy.
5. Make `go` executable for prompt/PRD normalization and planning.
6. Make `minion` executable for unattended execution.
7. Add canonical product spec normalization.
8. Add supported lanes and enterprise packs.
9. Add product builders and verification paths.
10. Add benchmark certification and downstream install proof.

---

## Task 1: Freeze the Harness Product Contract

**Goal:** Define the finished product in `gg-agentic-harness` terms, not `GGV3` terms.

**Files:**
- Create: `docs/prd/PRD-HEADLESS-ONE-SHOT-PRODUCT-HARNESS.md`
- Modify: `README.md`
- Modify: `docs/agentic-harness.md`
- Modify: `docs/prd/PRD-GG-CLI-PORTABLE-HARNESS.md`

**Execution Tasks:**
- Add the headless one-shot PRD in this repo.
- Update README language to frame `GGV3` as downstream install target.
- Update harness docs to distinguish headless engine from optional control surfaces.
- Clarify supported lanes and enterprise packs as V1 boundaries.

**Validation:**
- `rg -n "Headless One-Shot|downstream install target|supported lanes|enterprise packs" README.md docs docs/prd`

**Exit Criteria:**
- There is one clear product contract rooted in this repo.

---

## Task 2: Runtime Drift and Activation Elimination

**Goal:** Ensure the harness can prove it is actually active and correctly wired in its own repo.

**Files:**
- Modify: `scripts/runtime-project-sync.mjs`
- Modify: `scripts/runtime-parity-smoke.mjs`
- Modify: `packages/gg-cli/src/index.ts`
- Modify: `.mcp.json`
- Modify: `docs/runtime-profiles.md`
- Modify: `docs/setup/portable-agentic-harness-setup.md`

**Execution Tasks:**
- Add repo-root consistency checks for `gg-skills` and `filesystem`.
- Make CLI status explicitly report active vs stale host config.
- Make `doctor` fail when execution-critical activation is broken.
- Remove or reject stale local MCP declarations that conflict with registry policy.
- Ensure downstream target activation is documented as a second-stage install action.

**Validation:**
- `npm run harness:runtime:status`
- `npm run harness:runtime-parity:json`
- `npm run gg -- --json doctor`

**Exit Criteria:**
- The harness can state whether it is actually runnable in the current repo.

---

## Task 3: Shared Headless Execution Engine

**Goal:** Centralize real execution behavior in shared packages.

**Files:**
- Create: `packages/gg-core/src/execution/types.ts`
- Create: `packages/gg-core/src/execution/result.ts`
- Create: `packages/gg-core/src/execution/preflight.ts`
- Create: `packages/gg-core/src/execution/run-lifecycle.ts`
- Create: `packages/gg-core/src/spec/`
- Modify: `packages/gg-core/src/index.ts`
- Modify: `packages/gg-cli/src/index.ts`
- Modify: `packages/gg-orchestrator/src/index.ts`

**Execution Tasks:**
- Define terminal result contracts:
  - `HANDOFF_READY`
  - `BLOCKED`
  - `FAILED`
- Add preflight helpers for runtime activation, context freshness, and required files.
- Add run artifact lifecycle wrappers instead of ad hoc script branching.
- Expose shared functions that both CLI and control-plane server can call.

**Validation:**
- `npm run gg:build`
- `npm run gg -- --json doctor`

**Exit Criteria:**
- Execution behavior is shareable and not trapped inside one CLI file.

---

## Task 4: Executable `agentic-status`

**Goal:** Make status the first trusted headless surface.

**Files:**
- Modify: `packages/gg-cli/src/index.ts`
- Create: `packages/gg-core/src/status/agentic-status.ts`
- Modify: `.agent/workflows/agentic-status.md`
- Create: `scripts/harness-status-smoke.mjs`

**Execution Tasks:**
- Implement a real `agentic-status` adapter.
- Report:
  - runtime activation state,
  - config drift,
  - latest run artifacts,
  - failed gates,
  - dirty worktree warnings,
  - control-plane reachability,
  - optional-client availability.
- Support `--json`.

**Validation:**
- `npm run gg -- --json workflow run agentic-status`
- `node scripts/harness-status-smoke.mjs`

**Exit Criteria:**
- Operators can understand harness state without reading source files.

---

## Task 5: Executable `go`

**Goal:** Make prompt/PRD-to-plan a real headless path.

**Files:**
- Modify: `packages/gg-cli/src/index.ts`
- Create: `packages/gg-core/src/execution/go.ts`
- Create: `packages/gg-core/src/spec/normalize-input.ts`
- Create: `packages/gg-core/src/spec/lane-resolver.ts`
- Create: `packages/gg-core/src/spec/schema.ts`
- Modify: `.agent/workflows/go.md`
- Modify: `scripts/agent-run-artifact.mjs`

**Execution Tasks:**
- Accept prompt input or PRD path.
- Normalize into canonical product spec.
- Resolve lane, confidence, packs, and risk.
- Run preflight and fail fast if activation is invalid.
- Emit:
  - normalized spec,
  - planning artifact,
  - run artifact,
  - terminal result.
- Block on unsupported lane or unresolved ambiguity.

**Validation:**
- `npm run gg -- --json workflow run go "Build a SaaS analytics dashboard with RBAC"`
- `npm run gg -- --json workflow run go docs/prd/PRD-HEADLESS-ONE-SHOT-PRODUCT-HARNESS.md`

**Exit Criteria:**
- `go` is no longer scaffold-only.

---

## Task 6: Executable `minion`

**Goal:** Make unattended execution real for supported work.

**Files:**
- Modify: `packages/gg-cli/src/index.ts`
- Create: `packages/gg-core/src/execution/minion.ts`
- Create: `packages/gg-core/src/execution/validation-plan.ts`
- Modify: `.agent/workflows/minion.md`
- Modify: `scripts/agent-run-artifact.mjs`

**Execution Tasks:**
- Reuse normalized spec or direct task input.
- Execute:
  - preflight,
  - planning resolution,
  - validation profile selection,
  - doc sync,
  - terminal artifact completion.
- Support unattended output contracts with precise failure reasons.

**Validation:**
- `npm run gg -- --json workflow run minion "Implement a harness status endpoint"`
- `npm run gg -- --json workflow run symphony-lite "Implement a harness status endpoint" --validate none --doc-sync off`

**Exit Criteria:**
- `minion` can run a real unattended path and return a real terminal state.

---

## Task 7: Canonical Product Spec

**Goal:** Prevent vague prompts from flowing directly into generation.

**Files:**
- Create: `packages/gg-core/src/spec/types.ts`
- Create: `packages/gg-core/src/spec/normalizers/prompt.ts`
- Create: `packages/gg-core/src/spec/normalizers/prd.ts`
- Create: `packages/gg-core/src/spec/normalizers/constraints.ts`
- Create: `.agent/schemas/canonical-product-spec.schema.json`
- Create: `evals/headless-product-spec-fixtures/`

**Execution Tasks:**
- Define the canonical product spec schema.
- Parse prompt and PRD inputs into that schema.
- Add lane confidence scoring.
- Add unsupported-domain and insufficient-context rules.
- Add fixture corpus for normalization tests.

**Validation:**
- Add tests in:
  - `packages/gg-core/test/`
  - `packages/gg-cli/test/`

**Exit Criteria:**
- The harness never executes from raw vague input without first producing a canonical spec.

---

## Task 8: Supported Lanes and Enterprise Packs

**Goal:** Encode the generation space as explicit contracts.

**Files:**
- Create: `.agent/product-lanes/marketing-site.json`
- Create: `.agent/product-lanes/saas-dashboard.json`
- Create: `.agent/product-lanes/admin-panel.json`
- Create: `.agent/product-lanes/crud-shell.json`
- Create: `.agent/product-lanes/content-portal.json`
- Create: `.agent/packs/auth-rbac.json`
- Create: `.agent/packs/billing-stripe.json`
- Create: `.agent/packs/observability.json`
- Create: `.agent/packs/compliance-baseline.json`
- Create: `.agent/packs/design-system.json`
- Create: `.agent/packs/notifications.json`

**Execution Tasks:**
- Define lane compatibility.
- Define pack compatibility and required config.
- Define extra gates and review requirements.
- Make lane/pack resolution machine-readable and testable.
- Mark `marketing-site`, `saas-dashboard`, and `admin-panel` as `v1Mandatory=true`.
- Mark `design-system`, `observability`, and `auth-rbac` as `v1Unattended=true`.

**Validation:**
- Add lane-pack compatibility tests.
- `rg -n "saas-dashboard|billing-stripe|auth-rbac" .agent/product-lanes .agent/packs`

**Exit Criteria:**
- The harness builds from explicit product contracts rather than improvisation.

---

## Task 9: Product Builders

**Goal:** Generate real supported products from canonical specs.

**Files:**
- Create: `packages/gg-core/src/product/template-resolver.ts`
- Create: `packages/gg-core/src/product/pack-resolver.ts`
- Create: `packages/gg-core/src/product/build.ts`
- Create: `packages/gg-core/src/product/docs-bundle.ts`
- Create: `packages/gg-core/src/product/output-plan.ts`
- Modify: `packages/gg-cli/src/index.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Execution Tasks:**
- Select approved stack templates by lane.
- Apply enterprise packs.
- Generate file plan and output bundle.
- Write code/docs in deterministic stages.
- Expose the same build path through headless CLI and control-plane APIs.

**Validation:**
- Build fixture outputs in a temporary directory.
- Assert required files exist for each lane.

**Exit Criteria:**
- The harness can produce a functional supported web product skeleton from a spec.

---

## Task 10: Enterprise Verification

**Goal:** Prove product quality with real gates.

**Files:**
- Create: `packages/gg-core/src/verify/verify-product.ts`
- Create: `packages/gg-core/src/verify/gates.ts`
- Create: `scripts/headless-product-smoke.mjs`
- Modify: `packages/gg-cli/src/index.ts`
- Modify: `packages/gg-control-plane-server/src/governor.ts`

**Execution Tasks:**
- Add verification profiles by lane and pack.
- Run:
  - build/type-check,
  - lint,
  - targeted tests,
  - docs bundle presence,
  - smoke product checks.
- Add advanced optional gates:
  - accessibility,
  - browser smoke,
  - API contract validation,
  - deploy preflight.

**Validation:**
- `node scripts/headless-product-smoke.mjs`
- `npm run test`

**Exit Criteria:**
- The harness can prove output quality instead of merely claiming it.

---

## Task 11: Resume, Bundling, and Control-Plane Parity

**Goal:** Make runs restartable and consistent across CLI and server control paths.

**Files:**
- Modify: `scripts/agent-run-artifact.mjs`
- Modify: `.agent/schemas/run-artifact.schema.json`
- Create: `packages/gg-core/src/execution/resume.ts`
- Create: `packages/gg-core/src/execution/bundle.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Execution Tasks:**
- Extend artifacts with:
  - normalized spec path,
  - lane,
  - packs,
  - output bundle metadata,
  - resume checkpoint.
- Add resume logic to the engine.
- Expose equivalent control-plane endpoints for status, resume, and bundle retrieval.

**Validation:**
- Start run -> interrupt -> resume -> inspect artifact.

**Exit Criteria:**
- Partial runs can resume cleanly and remain observable through the same control plane.

---

## Task 12: One-Shot Benchmark and Downstream Install Proof

**Goal:** Certify the harness in its own repo, then prove it installs into `GGV3`.

**Files:**
- Create: `evals/headless-product-corpus.json`
- Create: `scripts/headless-harness-eval.mjs`
- Create: `docs/governance/headless-harness-scorecard.md`
- Modify: `README.md`
- Modify: `docs/setup/portable-agentic-harness-setup.md`

**Execution Tasks:**
- Define a benchmark corpus for supported lanes, with fixture-first certification.
- Run scorecard evaluation in this repo.
- Add pass/fail thresholds for one-shot readiness.
- Install the harness into `GGV3`.
- Verify:
  - portable init,
  - runtime activation,
  - headless status,
  - one supported build flow.

**Validation:**
- `node scripts/headless-harness-eval.mjs`
- `npm run gg -- portable init /absolute/path/to/ggv3 --mode symlink`
- `npm run gg -- --project-root /absolute/path/to/ggv3 runtime activate /absolute/path/to/ggv3 --runtime codex`

**Exit Criteria:**
- The harness is proven first in `gg-agentic-harness`, then validated as installable into `GGV3`.

---

## Rollout Phases

### Phase 1

Tasks 1 through 4.

**Outcome:** correct product contract, corrected runtime truth, first trustworthy headless status surface.

### Phase 2

Tasks 5 through 7.

**Outcome:** real prompt/PRD normalization and execution semantics for `go` and `minion`.

### Phase 3

Tasks 8 through 10.

**Outcome:** constrained enterprise product generation with real gates.

### Phase 4

Tasks 11 through 12.

**Outcome:** resumable runs, one-shot certification, and downstream install proof into `GGV3`.

---

## Critical Success Conditions

1. `gg-agentic-harness` remains the implementation source of truth.
2. Headless CLI/control-plane paths work without the macOS app.
3. `go`, `minion`, and `agentic-status` stop being scaffold-only.
4. Supported lanes are excellent before more lanes are added.
5. `GGV3` is used only after the harness is proven here.

## Failure Conditions

1. Harness internals continue to be built in downstream repos.
2. Runtime activation remains ambiguous.
3. The control-plane server and CLI diverge in behavior.
4. The macOS app becomes a required dependency for core operation.
5. "Enterprise" remains undefined or unvalidated.
