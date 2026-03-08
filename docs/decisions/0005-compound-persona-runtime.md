# ADR 0005: Deterministic Compound Persona Runtime

- Date: 2026-03-08
- Status: Accepted

## Context

Single-persona routing was not enough for repeatable multi-domain tasks such as auth hardening, payment reliability, incident recovery, and auction launch readiness. The harness needed a way to compose multiple specialists without letting the runtime invent unstable role mixes or permissions ad hoc.

## Decision

Introduce a second routing layer:

1. `.agent/registry/persona-registry.json` remains the canonical list of atomic personas.
2. `.agent/registry/persona-compounds.json` defines reusable, named compound personas.
3. `scripts/persona-registry-resolve.mjs` resolves atomic personas first, then:
   - selects a matching registry compound when confidence is high, or
   - derives a deterministic runtime compound when multiple specialists are required and no named compound exists.
4. Runtime compounds are auditable but non-authoritative. If they recur, they must be promoted into `.agent/registry/persona-compounds.json`.
5. Run artifacts must record `personaRouting`, including compound persona metadata when present.

## Consequences

Positive:

- Multi-specialist routing is deterministic instead of ad hoc.
- Codex, Claude, and Kimi can share the same compound dispatch contract.
- Recurring routing patterns can be promoted into installable harness defaults.

Trade-offs:

- Registry maintenance expands from personas to compounds.
- Prompt and workflow docs must explicitly treat `compoundPersona` as the effective dispatch contract.
- Portable harness installs must ship both registries and artifact support together.
