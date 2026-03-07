# PRD — GG CLI + Portable Agentic Harness

**Document ID:** PRD-GG-CLI-PORTABLE-HARNESS  
**Version:** 1.1  
**Date:** 2026-03-07  
**Status:** Approved for Scaffold  
**Owners:** Platform Engineering, Agentic Systems

## 1. Problem

The harness currently requires manual setup across files, scripts, and MCP wiring. This slows onboarding and increases drift between projects.

## 2. Objectives

1. Introduce a first-party CLI (`gg`) for deterministic harness operations.
2. Share one logic layer for catalog/discovery between agent tooling and CLI tooling.
3. Provide a portable bootstrap flow for installing the harness into new projects.
4. Reduce setup time and improve consistency across repositories.

## 3. Scope

### In Scope (V1 Scaffold)

- New workspace packages:
- `packages/gg-core`: shared catalog/path/search primitives.
- `packages/gg-cli`: command router and deterministic wrappers.
- CLI command families:
- `doctor`, `skills`, `workflow`, `run`, `context`, `validate`, `obsidian`, `portable`.
- Global machine-readable output mode:
- `--json` supported for all command groups.
- Portable bootstrap command:
- `gg portable init <targetDir> [--mode symlink|copy]`.
- Executable workflow adapters:
- `workflow run paperclip-extracted|symphony-lite|visual-explainer`.
- Documentation updates:
- README usage, setup guide, governance policy.

### Out of Scope (V1)

- Full workflow execution engine for every workflow slug.
- Remote package publishing for `gg`.
- Automatic mutation of external CI providers.

## 4. User Stories

1. As an engineer, I can run `gg doctor` to verify harness readiness quickly.
2. As an engineer, I can discover skills/workflows with deterministic CLI output.
3. As an operator, I can initialize run artifacts and validation evidence without manual script calls.
4. As a platform lead, I can bootstrap a new project with a portable harness setup command.

## 5. Functional Requirements

1. `gg` must resolve project root based on `.agent` + `package.json`.
2. `gg skills` and `gg workflow` must read local catalog files from `.agent`.
3. `gg run` must proxy to `scripts/agent-run-artifact.mjs`.
4. `gg context` must proxy to project-context generation/check.
5. `gg validate` must run deterministic quality gates (`tsc`, `lint`, `test`).
6. `gg obsidian` must proxy to existing Obsidian scripts.
7. `gg portable init` must create a runnable target layout and `.mcp.json` wiring.

## 6. Non-Functional Requirements

1. Node.js >= 20.
2. No hard dependency on active MCP session for CLI execution.
3. Deterministic exit codes for CI integration.
4. Human-readable output suitable for shell logs.

## 7. Architecture

- `gg-core`: file-system catalog loader + search + path resolver.
- `gg-cli`: command orchestration + wrapper execution + portability bootstrap.
- Existing scripts remain source-of-truth for specialized behavior.

### Interface split

- MCP: agent-native, schema-driven tool calls.
- CLI: deterministic shell/CI automation.
- Shared logic (`gg-core`) prevents behavior drift.

## 8. Acceptance Criteria

1. `npm run gg:build` succeeds.
2. `gg doctor` reports valid local harness wiring.
3. `gg skills find <query>` returns matching skills.
4. `gg workflow list` returns workflow inventory.
5. `gg workflow run symphony-lite <task> --validate <mode>` returns terminal outcome.
6. `gg portable init` creates target harness files and notes.
7. README and governance docs are updated with command and policy guidance.

## 9. Rollout Plan

### Phase 1 (This Scaffold)

- Build core packages and initial commands.
- Wire root scripts.
- Publish docs and governance.

### Phase 2

- Add advanced workflow execution adapters.
- Add CI profile and JSON output mode.
- Add optional package publishing and installer wrappers.

## 10. Risks and Mitigations

1. Drift between MCP and CLI behavior:
- Mitigation: keep discovery logic in `gg-core`.
2. Over-automation of destructive flows:
- Mitigation: scaffold-only workflow execution by default.
3. Portability path mismatch on different machines:
- Mitigation: generated `.mcp.json` uses target absolute paths.

## 11. Success Metrics

1. New project harness setup under 10 minutes.
2. 100% deterministic command coverage for common operator actions.
3. Reduction in manual setup incidents and config drift.
