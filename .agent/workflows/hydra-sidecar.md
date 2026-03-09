---
name: hydra-sidecar
description: "Feature-flagged Hydra-inspired sidecar routing advisory with mandatory dual-research evidence gates."
arguments:
  - name: objective
    description: "Objective to evaluate for sidecar routing."
    required: true
user_invocable: true
---

# /hydra-sidecar

Evaluate whether Hydra sidecar routing should advise or delegate the next harness workflow.

## Usage

```bash
/hydra-sidecar <objective>
```

## Mode Flag

Use `HARNESS_HYDRA_MODE=off|shadow|active`.

- `off`: native harness only
- `shadow`: advisory route recorded, no delegation
- `active`: delegated workflow may be returned when policy allows

## Dual-Research Gate

Hydra sidecar must fail closed unless both evidence sets exist:

1. codebase evidence:
   - repo paths
   - symbol or pattern findings
   - graph-context output when available
2. internet evidence:
   - dated external citations
   - standards, advisories, or vendor docs relevant to the decision

If either evidence set is missing, sidecar status is `blocked` and routing stays native.

## Guardrails

1. Deterministic validation remains harness-owned.
2. High-risk domains still require board review.
3. `shadow` must ship before `active`.
4. Every sidecar run must emit run-artifact evidence.
