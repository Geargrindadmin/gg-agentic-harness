# Agentic CLI and Portability Governance

**Version:** 1.0  
**Effective Date:** 2026-03-07  
**Owner:** Platform Engineering  
**Review Cycle:** Quarterly  
**Risk Level:** High

## 1. Policy

`gg` is the approved deterministic CLI for local/CI harness operations. Agent-facing MCP tools remain mandatory for model-native programmatic tool usage.

## 2. Scope

### In Scope

- `packages/gg-core` shared harness logic.
- `packages/gg-cli` command interface.
- Portable bootstrap flow (`gg portable init`).
- Documentation and governance references for CLI/harness setup.

### Out of Scope

- Bypassing quality gates through custom scripts.
- Running destructive automation without explicit approvals.

## 3. Control Requirements

1. Shared logic must live in `gg-core`; avoid duplicating logic in CLI/MCP adapters.
2. New `gg` commands must return deterministic exit codes.
3. High-risk operations must remain explicit and auditable.
4. Portable setup output must generate machine-readable config (`.mcp.json`) and human setup notes.
5. All command groups must support `--json` output for CI/automation use.
6. Workflow adapters must emit explicit terminal status and persistent run evidence.
7. Portable installs must ship persona routing files (`.agent/agents`, `.agent/registry/persona-registry.json`, `.agent/registry/persona-compounds.json`) together with artifact support.

## 4. Change Management

1. Any new command group requires:
- PRD update.
- README command documentation.
- Governance impact note.
2. Breaking CLI behavior changes require a migration note.
3. Portability behavior changes require validation in both `symlink` and `copy` modes.

## 5. Quality Gates

1. `npm run gg:build` passes.
2. `gg doctor` passes in source repo.
3. `gg portable init` smoke test passes in temp directory.
4. Harness lint and skills audit pass after CLI changes.
5. Persona audit and runtime parity smoke pass in a freshly initialized target project.

## 6. Security Requirements

1. CLI cannot silently write secrets.
2. Config generation must only use explicit target paths.
3. Commands that execute scripts must surface full command intent.

## 7. Auditability

- Runs and gates must continue to use `.agent/runs/*.json` evidence where applicable.
- CLI-generated portability actions must leave a `PORTABLE_AGENTIC_SETUP.md` trail in target repos.
- Persona routing must remain auditable through `personaRouting` entries in run artifacts when portable installs dispatch specialists.

## 8. References

- [PRD-GG-CLI-PORTABLE-HARNESS](../prd/PRD-GG-CLI-PORTABLE-HARNESS.md)
- [Agentic Harness](../agentic-harness.md)
- [README](../../README.md)
