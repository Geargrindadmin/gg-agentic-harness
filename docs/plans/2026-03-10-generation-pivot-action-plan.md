# Harness Generation Pivot Action Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Pivot `gg-agentic-harness` from a template-heavy first-pass product generator into a control-plane and verification system that drives content-aware generation and a second-pass quality refinement loop.

**Architecture:** Keep the harness responsible for normalization, routing, verification, artifacts, and lane/pack governance. Move first-pass quality improvements into a dedicated generation/refinement path: richer PRD signal extraction, content-aware lane builders, and a bounded second-pass evaluator/refiner that upgrades generated output before handoff.

**Tech Stack:** TypeScript, Node.js, Next.js App Router bundle generation, JSON registries, CLI workflow adapters, local benchmark fixtures.

---

## Pivot Decisions

1. The harness remains the source of truth for routing, preflight, artifacts, and verification.
2. The harness should stop presenting acceptance metadata as end-user landing-page content.
3. Supported lanes still build deterministically, but generation quality should come from structured source extraction plus bounded refinement.
4. UI/UX skills should inform a second-pass evaluator/refiner contract rather than remain implicit or manual.
5. Provider MCPs remain phase-scoped. Core control-plane MCP surfaces remain phase-stable.

## Phase 1: Stop Generating Internal Scaffolding as Customer-Facing UI

### Task 1: Add PRD-aware marketing signal extraction

**Files:**
- Modify: `packages/gg-core/src/product-builder.ts`
- Test: `packages/gg-core/test/core.test.mjs`

**Implementation:**
- Read PRD source content when `spec.sourceType === "prd"` and `spec.sourcePath` is present.
- Extract structured marketing signals:
  - product name
  - audience
  - primary goal
  - core narrative
  - brand direction
  - messaging requirements
  - product themes
  - use cases
  - pricing framing
  - FAQ prompts
- Fall back cleanly when signals are missing.

**Acceptance:**
- `marketing-site` bundles use source-aware brand and narrative content instead of generic summary + acceptance scaffolding.

### Task 2: Replace generic marketing content model

**Files:**
- Modify: `packages/gg-core/src/product-builder.ts`
- Test: `packages/gg-core/test/core.test.mjs`

**Implementation:**
- Replace or demote:
  - acceptance cards on homepage
  - pack cards on homepage
  - lane capability cards as primary story blocks
- Add richer marketing content blocks:
  - trust strip
  - proof metrics
  - product themes/features
  - use cases
  - case studies
  - FAQ
  - final CTA

**Acceptance:**
- Generated homepage reads like a SaaS landing page, not like an internal harness manifest.

### Task 3: Upgrade marketing page rendering and styling

**Files:**
- Modify: `packages/gg-core/src/product-builder.ts`
- Test: `packages/gg-core/test/core.test.mjs`

**Implementation:**
- Update `renderMarketingHomePage()`, `renderPricingPage()`, and `renderContactPage()`.
- Add CSS support for:
  - trust/logo strip
  - metric band
  - FAQ list
  - CTA banner
  - richer section hierarchy
- Preserve responsive behavior and existing build stability.

**Acceptance:**
- Generated page structure includes clear enterprise SaaS storytelling sections and avoids exposing harness governance language in the hero.

## Phase 2: Introduce a Quality Evaluator / Refiner Path

### Task 4: Define the refinement contract

**Files:**
- Create: `packages/gg-core/src/refinement.ts`
- Modify: `packages/gg-core/src/index.ts`
- Create: `docs/prd/PRD-HARNESS-QUALITY-REFINEMENT-LOOP.md`

**Implementation:**
- Define a machine-readable quality report:
  - structure score
  - copy score
  - design score
  - lane compliance
  - missing sections
  - generic-copy flags
  - weak CTA flags
- Add a bounded refiner action plan format for patching generated bundles.

**Acceptance:**
- The harness can score a generated bundle before claiming `HANDOFF_READY`.

### Task 5: Wire `create` and `go` into refinement mode

**Files:**
- Modify: `packages/gg-cli/src/index.ts`
- Modify: `.agent/workflows/create.md`
- Modify: `.agent/workflows/go.md`
- Test: `packages/gg-cli/test/cli.test.mjs`

**Implementation:**
- Add a `--quality-pass` mode:
  - `off`
  - `report`
  - `refine`
- Default supported marketing-site builds to `report` first, with `refine` available once the patch path is stable.

**Acceptance:**
- Builder runs can emit a quality artifact and optionally apply a second pass.

## Phase 3: Pull UI/UX Intelligence Into a Real Runtime Path

### Task 6: Create a lane-specific design brief generator

**Files:**
- Create: `packages/gg-core/src/design-brief.ts`
- Modify: `packages/gg-core/src/product-builder.ts`
- Test: `packages/gg-core/test/core.test.mjs`

**Implementation:**
- Derive a design brief from:
  - lane
  - brand direction
  - target audience
  - product narrative
  - CTA strategy
- Emit the brief into bundle artifacts and run artifacts.

**Acceptance:**
- Future model-backed or skill-backed refinement has a deterministic input contract.

### Task 7: Expose a generator/refiner integration seam

**Files:**
- Create: `packages/gg-runtime-adapters/src/generation-adapter.ts`
- Modify: `packages/gg-runtime-adapters/src/index.ts`
- Modify: `packages/gg-control-plane-server/src/index.ts`

**Implementation:**
- Add an adapter contract for external or model-backed design generation.
- Do not make it mandatory for base bundle generation.
- Keep the harness as orchestrator and verifier.

**Acceptance:**
- The harness can evolve beyond deterministic templates without rewriting lane orchestration.

## Phase 4: Tighten Quality Gates

### Task 8: Add homepage quality regression tests

**Files:**
- Modify: `packages/gg-core/test/core.test.mjs`
- Modify: `packages/gg-cli/test/cli.test.mjs`

**Implementation:**
- Assert that marketing bundles include:
  - extracted product name
  - use-case section
  - FAQ section
  - case studies
  - no acceptance-criteria section on the homepage

**Acceptance:**
- Generic scaffolding regressions fail fast.

### Task 9: Expand benchmark coverage for quality

**Files:**
- Modify: `evals/headless-product-corpus.json`
- Modify: `scripts/headless-product-benchmark.mjs`
- Create: `docs/governance/headless-quality-scorecard.md`

**Implementation:**
- Add structure and content checks for `marketing-site`.
- Track:
  - product naming quality
  - section completeness
  - CTA presence
  - generic-copy flags

**Acceptance:**
- Benchmark reports include quality signals, not just build success.

## Immediate Execution Order

1. Implement PRD-aware marketing signal extraction.
2. Replace the marketing homepage content model and renderer.
3. Add homepage regression tests.
4. Verify with `gg workflow run go <prd>` and live browser preview.
5. Only then start the formal refinement loop implementation.

## Verification Commands

Run from `/Users/shawn/Documents/gg-agentic-harness`:

```bash
npm run test --workspace=@geargrind/gg-core
npm run test --workspace=@geargrind/gg-cli
npm run lint --workspace=@geargrind/gg-core
npm run lint --workspace=@geargrind/gg-cli
node packages/gg-cli/dist/index.js --json --project-root /Users/shawn/Documents/gg-agentic-harness workflow run go evals/fixtures/saas-landing-page-demo-prd.md
```

## Risks

1. Richer marketing content can become fake or over-claimed if generation rules are too loose.
2. PRD parsing can become brittle if it relies on exact heading names only.
3. A second-pass refiner without strong bounds can damage deterministic stability.
4. UI quality improvements can regress build stability if the generator starts mutating config or adding unverified complexity.

## Rollback

If the richer marketing builder destabilizes bundle generation:

1. Revert `packages/gg-core/src/product-builder.ts`
2. Re-run:
```bash
npm run test --workspace=@geargrind/gg-core
npm run test --workspace=@geargrind/gg-cli
```
3. Restore the previous bundle builder while keeping the action plan and regression tests for the next pass.
