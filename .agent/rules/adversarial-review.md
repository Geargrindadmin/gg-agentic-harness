# Adversarial Review Rule

Purpose: force deep review quality and prevent low-signal "looks good" approvals.

## Required Trigger

Apply this rule whenever the task asks for a review, audit, readiness check, or quality gate verdict.

## Protocol

1. Assume issues exist until disproven.
2. List findings first, ordered by severity (`Critical`, `High`, `Medium`, `Low`).
3. Each finding must include concrete evidence:
   - file path
   - line reference when available
   - impact
   - corrective action
4. If no findings are confirmed, explicitly state `No material findings` and include:
   - residual risks
   - testing gaps
   - confidence level
5. Separate real defects from probable false positives.

## Hard Stops

- Do not return review output that only contains praise or generic statements.
- Do not hide uncertainty; mark assumptions clearly.
- Do not approve high-risk auth/payments/security changes without explicit evidence checks.

## Evidence Sources

- local tests/lint/typecheck results
- static scans where available
- runtime traces/logs where available
- direct file inspection

## Output Shape

1. Findings (primary section)
2. Open questions/assumptions
3. Optional short summary
