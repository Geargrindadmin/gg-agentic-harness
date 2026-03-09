---
name: visual-explainer
description: "Generate rich visual explainers (HTML/slide-style) for architecture, diffs, plans, audits, and handoffs"
arguments:
  - name: subject
    description: "What to explain (architecture, diff, plan, audit, recap)"
    required: true
user_invocable: true
---

# /visual-explainer

Produce a high-signal visual explainer artifact for technical communication.

## Usage

```bash
/visual-explainer <subject>
```

## Output Targets

- `docs/reports/<date>-<slug>.html` for browser-first explainers
- `docs/reports/<date>-<slug>.md` companion summary

## Flow

1. Determine explainer type:
- architecture map
- diff review
- implementation plan audit
- test/result recap

2. Gather evidence:
- changed files
- validation outputs
- risks and open decisions
- run artifacts
- explicit citations to local files or commands

3. Build visual artifact:
- use semantic sectioning
- support `architecture`, `diff-review`, and `audit-recap` modes
- add diagram/table components as needed
- ensure light/dark readability and print-safe typography

4. Publish summary:
- key decisions
- findings
- next actions
- citation block for every major claim

## Constraints

- Do not fabricate metrics or test results.
- Link all claims back to local files or command output.
- Keep artifact self-contained (no external runtime dependencies required to view).
