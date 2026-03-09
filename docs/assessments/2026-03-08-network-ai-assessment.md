# Network-AI Assessment (Addon Candidate)

Date: 2026-03-08  
Repository: `https://github.com/jovanSAPFIONEER/Network-AI`  
Assessed commit: `c289164` (main)

## Executive Summary

`Network-AI` is a credible orchestration/control-plane addon candidate for `gg-agentic-harness`, but should be integrated as a **pilot sidecar** rather than as a core replacement.

Recommendation: **Integrate as optional pilot in `shadow` mode first**, then evaluate whether it complements or replaces parts of planned Hydra sidecar behavior.

## What It Offers (Relevant to Harness)

1. Shared state coordination with lock-based propose/validate/commit semantics.
2. Budget and permission controls (`FederatedBudget`, `AuthGuardian`) that align with guardrail goals.
3. MCP server mode (`network-ai-server`) and CLI for control-plane operations.
4. Multi-framework adapter model that could help mixed-agent environments.

## Fit Against Current Priority Wave

| Priority stream | Impact from Network-AI | Fit |
| --- | --- | --- |
| CodeGraphContext pilot | No direct overlap | Neutral |
| visual-explainer upgrade | Could provide richer event telemetry for explainers | Positive |
| prompt-improver workflow | No direct overlap | Neutral |
| Hydra sidecar | Significant overlap in sidecar/control-plane concerns | High (potential complement or conflict) |

## Risks and Constraints

1. Scope overlap with Hydra may duplicate orchestration paths unless boundaries are explicit.
2. MCP server defaults to broad host binding (`0.0.0.0`) and must be locked down in production usage.
3. Adds operational surface area (Node + optional Python tooling paths).
4. Smaller maintainer/community footprint than major ecosystem projects; evaluate bus factor before hard dependency.

## Suggested Integration Contract (Pilot)

1. Keep `Network-AI` out of core harness path initially.
2. Add feature flag:
- `HARNESS_NETWORK_AI_MODE=off|shadow|active`
3. `off`: no integration.
4. `shadow`: collect comparative routing/control data only.
5. `active`: only after shadow metrics pass and governance sign-off.
6. Preserve deterministic harness gate ownership in all modes.

## Pilot Success Criteria

1. No regression in runtime parity checks.
2. Shadow telemetry improves visibility without increasing failure rate.
3. No conflict with Hydra sidecar role boundaries.
4. Run artifacts capture sidecar events and fallback paths consistently.

## Decision

Status: **Approved for pilot integration planning** (not approved for core replacement).
