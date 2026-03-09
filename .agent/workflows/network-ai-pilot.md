---
name: network-ai-pilot
description: "Pilot workflow for evaluating Network-AI as an optional sidecar in shadow-first mode"
arguments:
  - name: objective
    description: "What sidecar behavior to evaluate (routing, budget guardrail, auth gating, or telemetry)"
    required: true
user_invocable: true
---

# /network-ai-pilot

Evaluate `Network-AI` as an addon sidecar without changing core harness ownership.

## Usage

```bash
/network-ai-pilot <objective>
```

## Contract

1. Core harness remains decision owner.
2. Pilot starts in `shadow` mode only.
3. Deterministic gates remain mandatory.
4. Every pilot run must emit run-artifact evidence.

## Flow

1. Define pilot objective:
- sidecar routing comparison
- budget/permission control telemetry
- MCP exposure validation

2. Run in shadow-first mode:
- no execution delegation in first pass
- log hypothetical routing/control decisions

3. Validate and compare:
- compare shadow decisions against current harness decisions
- capture mismatches and failure signatures

4. Produce pilot evidence:
- `docs/reports/*` summary
- `.agent/runs/*` telemetry with fallback paths

5. Governance checkpoint:
- escalate to board review before any `active` mode usage

## Guardrails

1. Do not bypass quality gates.
2. Do not enable `active` mode without explicit governance approval.
3. Keep pilot optional and fully reversible.
