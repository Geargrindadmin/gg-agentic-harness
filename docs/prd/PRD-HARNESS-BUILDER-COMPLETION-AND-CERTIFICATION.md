# PRD — Harness Builder Completion, Provider Execution, Next Baseline, and Lane Certification

**Document ID:** PRD-HARNESS-BUILDER-COMPLETION-AND-CERTIFICATION  
**Version:** 0.1  
**Date:** 2026-03-09  
**Status:** Draft  
**Owners:** Agentic Systems, Platform Engineering  
**Primary Repo:** `gg-agentic-harness`  
**Related:** `docs/prd/PRD-HEADLESS-ONE-SHOT-PRODUCT-HARNESS.md`, `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`, `docs/plans/2026-03-09-headless-one-shot-product-harness-action-plan.md`, `docs/agentic-harness.md`

## 1. Executive Summary

`gg-agentic-harness` now has a real headless product-builder path, but it is not yet a finished one-shot product system.

Current reality:

1. `workflow run create` can emit a portable Next.js bundle for supported lanes.
2. `workflow run go` and `workflow run minion` normalize product intent, but they do not yet automatically route supported product requests into the builder path.
3. Runtime/provider integration surfaces exist in `gg-runtime-adapters`, `gg-orchestrator`, and `gg-control-plane-server`, but several routes still function more as governed contracts than fully exercised product paths.
4. Generated bundles build successfully, but the emitted Next.js baseline still causes first-build config mutation and workspace-root noise that should be eliminated by the generator.
5. Live proof exists for a marketing site bundle and a SaaS dashboard bundle, but certification is not broad enough yet to claim supported-lane completion.

This PRD defines the work required to close those gaps and turn the current builder proof into a credible, repeatable, headless product system.

## 2. Problem Statement

The harness is close enough to working that vague claims become dangerous.

What is true now:

1. The system can normalize prompt and PRD inputs into a canonical product spec through shared `gg-core` logic.
2. The system can emit bundle artifacts, manifests, readmes, env examples, app structure, and pack-aware modules.
3. The system can return real run artifacts and terminal states.
4. The system has already surfaced and survived at least one real generator bug during live validation.

What is still missing:

1. Automatic routing from `go` and `minion` into `create` for supported product specs.
2. Fully productized provider-level execution paths beyond contract completeness.
3. Clean generator output that does not require Next.js to rewrite config on first build.
4. Benchmark coverage across all supported lanes and pack combinations that matter for V1.

Without those four closures, the harness is still a strong prototype rather than a finished headless product operator.

## 3. Background and Current State

### 3.1 Implemented Baseline

The following surfaces exist and are real today:

1. Shared preflight:
   - `packages/gg-core/src/preflight.ts`
2. Shared canonical product-spec resolution:
   - `packages/gg-core/src/product-spec.ts`
3. Shared product bundle builder:
   - `packages/gg-core/src/product-builder.ts`
4. Executable workflow adapters:
   - `packages/gg-cli/src/index.ts`
5. Runtime adapter contracts and launch plans:
   - `packages/gg-runtime-adapters/src/index.ts`
6. Orchestration plumbing:
   - `packages/gg-orchestrator/src/index.ts`
7. Control-plane worker launch path:
   - `packages/gg-control-plane-server/src/index.ts`
8. Machine-readable lane and pack registries:
   - `.agent/product-lanes/`
   - `.agent/packs/`
9. Canonical product-spec schema:
   - `.agent/schemas/canonical-product-spec.schema.json`
10. Initial benchmark corpus:
    - `evals/headless-product-corpus.json`

### 3.2 Live Evidence Already Collected

Live proof gathered during the implementation pass:

1. A marketing-site bundle was generated, installed, and built successfully.
2. A SaaS dashboard bundle was generated, exposed a real generator bug, was fixed in the builder, then re-generated successfully.
3. Post-fix dashboard verification passed:
   - `npm run typecheck`
   - `npm run lint`
   - `npm run build`
4. The builder emits real artifacts under:
   - `.agent/product-bundles/*`
   - `.agent/runs/*.json`

### 3.3 Known Defects and Completion Gaps

This PRD specifically addresses four gaps:

1. Builder routing gap:
   - `create` builds the product bundle, but `go` and `minion` do not yet route into `create` automatically.
2. Provider execution gap:
   - provider-level integrations still retain contract-first behavior and are not fully hardened as first-class execution products.
3. Next baseline gap:
   - generated bundles should emit a cleaner `next.config.ts`, `tsconfig.json`, and related baseline so Next does not adjust files on first build.
4. Certification gap:
   - the benchmark proof is too narrow to claim supported-lane completion.

## 4. Product Goal

Turn the current builder proof into a finished, headless, execution-grade product system that:

1. accepts a prompt, PRD, or normalized spec,
2. resolves whether the request fits a supported lane,
3. automatically routes eligible product requests from `go` and `minion` into the builder pipeline,
4. executes provider-backed or runtime-backed steps through fully productized adapters rather than documentation-only contracts,
5. emits clean, stable, build-ready Next bundles with no first-build config rewrites,
6. proves quality across the supported-lane matrix with repeatable benchmark evidence.

## 5. Non-Goals

This PRD does not authorize the following:

1. arbitrary software generation outside the supported lane model,
2. claiming enterprise completeness for unimplemented packs such as full Stripe billing or full compliance execution when only structure exists,
3. replacing the core harness with a sidecar or external provider system,
4. making the macOS control surface a dependency for the core runtime,
5. using `GGV3` as the primary development ground for harness internals.

## 6. Users and Stakeholders

Primary readers and operators:

1. platform engineers implementing harness internals,
2. future LLMs resuming the build-out,
3. downstream operators installing the harness into another repo,
4. reviewers deciding whether the harness is ready for downstream rollout.

Secondary readers:

1. control-plane client authors,
2. runtime adapter authors,
3. benchmark and evaluation owners.

## 7. Definitions

### 7.1 Supported Product Request

A request is supported when all of the following are true:

1. it normalizes cleanly into a canonical product spec,
2. the lane resolves to a supported V1 lane,
3. the requested packs are allowed for that lane,
4. missing configuration does not exceed the unattended threshold,
5. preflight is runnable.

### 7.2 Builder Routing

Builder routing means `go` and `minion` can detect a supported product request and delegate into the same core creation path used by `create`, rather than stopping at normalized intake or separate workflow delegation.

### 7.3 Provider-Level Integration

For this PRD, provider-level integration means a runtime or external execution path that goes beyond static launch contracts and supports real execution semantics, error mapping, traceability, retry policy, and deterministic failure behavior.

### 7.4 Clean Next Baseline

A clean Next baseline means a newly generated bundle can run its first install/build sequence without Next.js rewriting committed config files or requiring manual cleanup to reach a stable baseline.

### 7.5 Lane Certification

Lane certification means the harness has repeated benchmark evidence that a supported lane builds successfully and meets the defined quality gates, not merely that one example happened to work.

## 8. Product Requirements

### 8.1 Requirement Group A — Automatic Builder Routing

#### A.1 Objective

Make `go` and `minion` automatically route supported product requests into the shared bundle builder path.

#### A.2 Current Limitation

Current behavior is split:

1. `create` is the real product builder surface.
2. `go` normalizes and plans.
3. `minion` normalizes and delegates into an autonomous workflow path.

This split is useful for development, but it prevents the product from behaving like a unified one-shot builder.

#### A.3 Required Behavior

For supported product requests:

1. `go` must resolve the canonical product spec.
2. `go` must determine whether the request is:
   - builder-eligible,
   - builder-ineligible,
   - builder-eligible but review-blocked.
3. When builder-eligible, `go` must produce a planning artifact that explicitly states the next executable path is builder-backed.
4. `go` must support an option to invoke the builder directly, or default to direct invocation if policy says that is the correct one-shot path.
5. `minion` must use the same eligibility logic.
6. When `minion` receives a supported product request and preflight passes, it must route into the shared product creation pipeline instead of ending with only delegated autonomous execution.
7. `create` must remain the explicit builder entrypoint, but it must no longer be the only real builder surface.

#### A.4 Routing Decision Matrix

`go` and `minion` must implement a deterministic routing decision:

1. If preflight fails:
   - return `BLOCKED`
   - do not route into builder
2. If spec normalization fails:
   - return `BLOCKED`
   - emit unresolved ambiguity reasons
3. If lane is unsupported:
   - return `BLOCKED`
   - recommend alternative supported lanes or explicit manual workflow
4. If requested packs are incompatible:
   - return `BLOCKED`
   - emit incompatible pack IDs
5. If requested configuration is missing but review is allowed:
   - route to `go` planning mode or `HANDOFF_READY` planning artifact
6. If the spec is supported, configuration is sufficient, and policy allows unattended build:
   - route into `create`
   - emit builder artifact metadata in the run artifact

#### A.5 Required Repository Impact

The routing completion work must touch, at minimum:

1. `packages/gg-cli/src/index.ts`
2. `packages/gg-core/src/product-spec.ts`
3. `packages/gg-core/src/product-builder.ts`
4. `packages/gg-core/src/preflight.ts`
5. `packages/gg-core/src/index.ts`
6. `.agent/workflows/go.md`
7. `.agent/workflows/minion.md`
8. `.agent/workflows/create.md`
9. `packages/gg-cli/test/cli.test.mjs`
10. `packages/gg-core/test/core.test.mjs`

#### A.6 Artifact Requirements

When routing occurs, the run artifact must include:

1. `resolvedExecutionPath`
2. `builderEligible`
3. `builderInvoked`
4. `bundlePath`
5. `bundleManifestPath`
6. `selectedLane`
7. `selectedPacks`
8. `reviewRequired`
9. `blockingIssues`

#### A.7 Acceptance Criteria

The routing requirement is complete only when:

1. `go` can automatically route a supported product prompt into builder execution or builder-backed planning.
2. `minion` can automatically route a supported product prompt into builder execution.
3. the result is visible in run artifacts and JSON output.
4. unsupported requests fail closed with specific reasons.
5. tests cover:
   - supported prompt
   - supported PRD
   - normalized spec input
   - incompatible packs
   - unsupported lane
   - preflight failure

### 8.2 Requirement Group B — Provider-Level Execution Productization

#### B.1 Objective

Convert provider-facing execution paths from “documented contract plus partial path” into fully supported, validated runtime execution surfaces.

#### B.2 Scope Clarification

This requirement applies to runtime/provider execution within the harness itself, not business-domain packs like Stripe billing UI generation.

Primary code surfaces:

1. `packages/gg-runtime-adapters/src/index.ts`
2. `packages/gg-orchestrator/src/index.ts`
3. `packages/gg-control-plane-server/src/index.ts`
4. `packages/gg-runtime-adapters/test/runtime-adapters.test.mjs`
5. `packages/gg-orchestrator/test/orchestrator.test.mjs`
6. `packages/gg-control-plane-server/test/*.test.mjs`
7. `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`

#### B.3 Current Limitation

The current runtime adapter layer is structurally strong, but some paths still behave as contracts first:

1. adapter modes exist:
   - `host-activated`
   - `contract-only`
   - `provider-api`
2. launch transports exist:
   - `contract-only`
   - `background-terminal`
   - `api-session`
   - `cli-session`
3. several routes are validated and rendered, but not yet treated as fully benchmarked product paths across the complete worker lifecycle.

#### B.4 Required Behavior

Provider/runtime execution completion must include:

1. real launch validation before worker execution,
2. explicit capability detection per runtime,
3. normalized error classes across runtimes,
4. transcript capture and artifact traceability,
5. retry rules that are bounded and recorded,
6. fail-closed behavior when transport/provider requirements are missing,
7. JSON-safe status reporting for the control plane,
8. replayable evidence from launch request through terminal result.

#### B.5 Runtime Requirements

For each active runtime path:

1. `codex`
   - project activation must be verified before execution
   - background-terminal path must be documented and tested as a real path, not only a launch plan
2. `claude`
   - supported transport modes must be explicit
   - unsupported transports must fail with deterministic messaging
3. `kimi`
   - `api-session` and any allowed CLI path must behave as real execution surfaces with concrete validation and response capture
4. `hydra-sidecar`
   - must remain gated
   - must preserve deterministic gate ownership in the harness
5. control-plane worker launch
   - must persist request, transcript, response, failure reason, and final worker state consistently

#### B.6 Required Repository Impact

The provider productization work must include:

1. lifecycle-state review in `packages/gg-control-plane-server/src/index.ts`
2. adapter capability review in `packages/gg-runtime-adapters/src/index.ts`
3. launch envelope and worker contract review in `packages/gg-orchestrator/src/index.ts`
4. stronger end-to-end tests for launch, execution, and failure mapping
5. updated runtime documentation in:
   - `docs/agentic-harness.md`
   - `docs/runtime-profiles.md`
   - `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`

#### B.7 Acceptance Criteria

This requirement is complete only when:

1. every supported provider/runtime path has a tested launch-to-result lifecycle,
2. unsupported combinations fail deterministically,
3. control-plane launch artifacts are complete and replayable,
4. tests cover happy path, auth/config missing path, transport mismatch path, timeout path, and transcript capture path.

### 8.3 Requirement Group C — Clean Next.js Generator Baseline

#### C.1 Objective

Ensure newly generated bundles start from a stable Next.js baseline with no first-build config churn.

#### C.2 Current Limitation

Current generated bundles build, but the first build still exposes baseline issues:

1. Next.js may rewrite `tsconfig.json`.
2. the generated baseline may require Next to add or change JSX/compiler settings.
3. workspace-root inference may produce noise when bundles are generated inside the harness repo tree.
4. the generator should own the config shape instead of relying on Next to correct it.

#### C.3 Required Behavior

The builder must emit baseline config that satisfies all of the following:

1. the first install/build/typecheck/lint cycle succeeds without generated config files being rewritten by Next.js,
2. `tsconfig.json` already includes the correct Next-required settings,
3. `next.config.ts` explicitly handles workspace-root behavior where required,
4. lint config is stable on first run,
5. the generated baseline is identical before and after first build unless the app itself changes.

#### C.4 Required Generator Surfaces

The baseline cleanup work must review and potentially modify:

1. `packages/gg-core/src/product-builder.ts`
2. emitted `tsconfig.json`
3. emitted `next.config.ts`
4. emitted `eslint.config.mjs`
5. emitted `package.json`
6. emitted `.gitignore`
7. emitted optional root metadata such as `README.md` and env examples when they describe build behavior

#### C.5 Required Validation Contract

For every benchmarked bundle:

1. capture generated config files before install/build,
2. run install,
3. run typecheck,
4. run lint,
5. run build,
6. diff the generated config files after build,
7. fail the benchmark if Next.js modified tracked config unexpectedly.

#### C.6 Acceptance Criteria

This requirement is complete only when:

1. the generated marketing-site bundle passes first-build validation with zero config rewrites,
2. the generated SaaS dashboard bundle passes first-build validation with zero config rewrites,
3. the generated admin-panel bundle passes first-build validation with zero config rewrites,
4. the benchmark suite asserts the no-config-mutation rule explicitly.

### 8.4 Requirement Group D — Supported-Lane Benchmark Certification

#### D.1 Objective

Prove that the harness works across the supported-lane space rather than on two anecdotal examples.

#### D.2 V1 Certification Target

V1 certification must cover the mandatory lanes:

1. `marketing-site`
2. `saas-dashboard`
3. `admin-panel`

Certification must also cover at least the V1 unattended packs:

1. `design-system`
2. `observability`
3. `auth-rbac`

#### D.3 Required Corpus Shape

The benchmark corpus must include:

1. at least three prompts per mandatory lane,
2. at least one PRD-based input per mandatory lane,
3. at least one normalized-spec input per mandatory lane,
4. at least one pack-heavy case per mandatory lane,
5. at least one negative case per lane family.

#### D.4 Required Measurements

Each benchmark run must record:

1. input source type,
2. resolved lane,
3. resolved packs,
4. review-required flag,
5. output bundle path,
6. build success or failure,
7. lint success or failure,
8. typecheck success or failure,
9. config-mutation status,
10. run duration,
11. failure signature if failed.

#### D.5 Required Outputs

Certification must produce:

1. a machine-readable results file,
2. a human-readable benchmark report,
3. a per-lane pass/fail scorecard,
4. a known-failures section with normalized signatures,
5. a release-readiness decision for the builder slice.

#### D.6 Required Repository Impact

The certification work must at minimum affect:

1. `evals/headless-product-corpus.json`
2. new benchmark runner scripts under `scripts/`
3. new or updated docs under `docs/reports/`
4. run artifact handling where needed
5. tests for corpus validation and benchmark reporting

#### D.7 Acceptance Criteria

Certification is complete only when:

1. all three mandatory lanes have repeated passing benchmark evidence,
2. the generated bundles pass typecheck, lint, and build,
3. config files remain stable across first build,
4. failure signatures are captured for any remaining misses,
5. the harness can present an honest lane-readiness score rather than a binary “works/does not work” claim.

## 9. Functional Requirements by Surface

### 9.1 `workflow run create`

`create` must remain:

1. the canonical explicit builder entrypoint,
2. the easiest place to validate bundle generation in isolation,
3. the shared creation path called by routed `go` and `minion` flows.

`create` must not become a divergent code path.

### 9.2 `workflow run go`

`go` must become:

1. the primary intent-resolution and routing surface,
2. the builder gateway for supported product inputs,
3. the place where unsupported requests are rejected early with specific reasons.

### 9.3 `workflow run minion`

`minion` must become:

1. the unattended executor for supported product specs,
2. the builder-backed one-shot surface when the request is within supported policy,
3. a fail-fast surface when policy or preflight blocks execution.

### 9.4 `workflow run agentic-status`

`agentic-status` must expose:

1. builder readiness,
2. runtime readiness,
3. benchmark readiness,
4. current known blockers.

## 10. Non-Functional Requirements

The completed slice must satisfy:

1. deterministic routing,
2. deterministic failure semantics,
3. machine-readable artifacts,
4. honest status reporting,
5. bounded retries,
6. minimal drift between docs and executable behavior,
7. runtime parity discipline across supported runtimes.

## 11. Documentation Requirements

The implementation is not complete unless docs are updated in the same pass.

Required documentation updates:

1. `README.md`
2. `docs/agentic-harness.md`
3. `docs/runtime-profiles.md`
4. `docs/prd/PRD-HEADLESS-ONE-SHOT-PRODUCT-HARNESS.md`
5. `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`
6. `docs/setup/portable-agentic-harness-setup.md`
7. `docs/reports/` benchmark outputs

Documentation must distinguish:

1. implemented,
2. partially implemented,
3. contract-only,
4. benchmark-certified,
5. planned.

## 12. Rollout Plan

### Phase 0 — Spec Freeze

1. Land this PRD.
2. Mark the four gaps as tracked against explicit repository surfaces.
3. Ensure related PRDs reference this closure work.

### Phase 1 — Builder Routing Completion

1. unify eligibility logic,
2. route `go` into builder-backed execution,
3. route `minion` into builder-backed execution,
4. add run artifact markers,
5. add routing tests.

### Phase 2 — Provider Productization

1. audit supported runtime/provider transports,
2. harden worker launch lifecycle,
3. normalize error mapping,
4. improve transcript and artifact capture,
5. add control-plane lifecycle tests.

### Phase 3 — Next Baseline Cleanup

1. fix emitted config baselines,
2. add no-config-mutation validation,
3. verify all mandatory lanes against the first-build rule.

### Phase 4 — Certification

1. expand the corpus,
2. add benchmark runner and scorecard,
3. execute repeated lane validation,
4. publish release-readiness evidence.

### Phase 5 — Downstream Proof

1. only after certification, install the harness into `GGV3`,
2. validate the same builder path there,
3. treat downstream proof as consumer validation, not core development.

## 13. Risks and Mitigations

### Risk 1 — `go` and `minion` diverge from `create`

Mitigation:

1. one shared core builder invocation path,
2. one shared eligibility resolver,
3. one shared artifact model.

### Risk 2 — provider execution looks complete but is not replayable

Mitigation:

1. require launch-to-result artifact traceability,
2. require transcript capture,
3. require negative-path tests.

### Risk 3 — Next baseline changes again under dependency upgrades

Mitigation:

1. make no-config-mutation an explicit benchmark rule,
2. diff config before and after first build in CI-like verification,
3. fail fast when generated config drifts.

### Risk 4 — benchmark coverage becomes anecdotal again

Mitigation:

1. require repeated lane coverage,
2. require both positive and negative cases,
3. publish scorecards rather than vague success claims.

## 14. Success Metrics

The slice is successful only when all of the following are true:

1. `go` routes supported product requests into the builder path automatically.
2. `minion` routes supported product requests into the builder path automatically.
3. supported provider/runtime execution paths are lifecycle-tested and artifact-complete.
4. generated bundles do not experience first-build config mutation.
5. all three mandatory lanes have repeatable benchmark proof.
6. documentation accurately states what is real, what is partial, and what is still contract-only.

## 15. Release Readiness Gate

This PRD is complete only when the following release gate passes:

1. mandatory lane benchmarks are green,
2. builder routing tests are green,
3. runtime/provider lifecycle tests are green,
4. no-config-mutation checks are green,
5. README and operator docs are updated,
6. downstream install into `GGV3` has not introduced contradictions with the source-of-truth behavior.

## 16. Implementation Notes for Future LLMs

This section is intentionally operational.

If you are resuming this work later, start here:

1. read:
   - `docs/prd/PRD-HEADLESS-ONE-SHOT-PRODUCT-HARNESS.md`
   - `docs/prd/PRD-MULTI-MODEL-CONTROL-PLANE.md`
   - this PRD
2. inspect current code surfaces:
   - `packages/gg-cli/src/index.ts`
   - `packages/gg-core/src/product-spec.ts`
   - `packages/gg-core/src/product-builder.ts`
   - `packages/gg-core/src/preflight.ts`
   - `packages/gg-runtime-adapters/src/index.ts`
   - `packages/gg-orchestrator/src/index.ts`
   - `packages/gg-control-plane-server/src/index.ts`
3. inspect current registries:
   - `.agent/product-lanes/`
   - `.agent/packs/`
   - `.agent/schemas/canonical-product-spec.schema.json`
4. inspect current proof artifacts:
   - `.agent/product-bundles/live-marketing-bundle`
   - `.agent/product-bundles/live-dashboard-bundle`
   - `.agent/runs/`
5. re-run the current verification baseline before claiming anything:
   - `npm run test --workspace=@geargrind/gg-core`
   - `npm run test --workspace=@geargrind/gg-cli`
   - `npm run lint --workspace=@geargrind/gg-core`
   - `npm run lint --workspace=@geargrind/gg-cli`

Do not claim the harness is finished because `create` works. The completion bar is the four gaps defined in Section 3.3.

## 17. Appendix — Concrete Expected Deliverables

Expected code deliverables:

1. shared builder-routing logic,
2. shared builder invocation from `go` and `minion`,
3. provider/runtime lifecycle hardening,
4. cleaner emitted Next baseline,
5. benchmark runner and scorecard outputs.

Expected documentation deliverables:

1. updated product PRDs,
2. updated operator docs,
3. updated setup docs,
4. benchmark reports,
5. honest release-readiness summary.

Expected proof deliverables:

1. run artifacts,
2. bundle manifests,
3. transcript artifacts where provider execution applies,
4. per-lane benchmark results,
5. downstream consumer proof after source-repo certification.
