# ADR 0004: Deterministic Persona Registry Dispatch

- Date: 2026-03-08
- Status: Accepted

## Context

The portable harness needed a machine-readable routing contract for specialist personas. Without that contract, Codex, Claude, and Kimi would drift toward prompt-prose routing and inconsistent sub-agent selection.

## Decision

Adopt a canonical persona registry:

1. `.agent/registry/persona-registry.json` defines atomic personas.
2. `.agent/agents/*.md` mirror the registry metadata and role constraints.
3. `scripts/persona-registry-resolve.mjs` resolves the effective primary persona and collaborator set for a task.
4. `scripts/persona-registry-audit.mjs` validates the registry and persona files before dispatch.

## Consequences

Positive:

- Specialist routing becomes deterministic and auditable.
- Portable installs can ship the same persona contract across projects.
- Role ownership in `.agent/rules/agent-roles.md` becomes enforceable.

Trade-offs:

- New personas require registry maintenance.
- Resolver heuristics still need periodic refinement and benchmarking.
