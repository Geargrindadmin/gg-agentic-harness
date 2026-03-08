# ADR 0007: Runtime Activation Adapters

- Date: 2026-03-08
- Status: Accepted

## Context

The harness core is model-agnostic, but activation requirements differ by runtime client. The previous command surface (`codex activate`) exposed only one adapter and made the public contract look Codex-specific.

## Decision

Introduce runtime adapter activation as the public contract:

1. New canonical script: `scripts/runtime-project-sync.mjs`.
2. New canonical CLI command: `gg runtime <activate|status> ... --runtime <codex|claude|kimi>`.
3. Codex remains a concrete adapter with host-level config mutation (`~/.codex/config.toml`, `~/.codex/mcp.json`).
4. Claude and Kimi currently use contract-only adapters (validation without host mutation).
5. `scripts/codex-project-sync.mjs` remains as a compatibility shim to avoid breaking existing automation.
6. Runtime parity checks and portable verification now key on runtime activation semantics, not Codex-only naming.

## Consequences

Positive:

- Public harness contract is runtime-oriented instead of vendor/client-oriented.
- New adapters can be added without changing workflow semantics.
- Codex/Claude/Kimi parity remains enforced with different transport/activation mechanisms.

Trade-offs:

- Two command paths exist temporarily (`runtime` canonical, `codex` compatibility alias).
- Documentation and CI checks must maintain adapter vocabulary consistently.
