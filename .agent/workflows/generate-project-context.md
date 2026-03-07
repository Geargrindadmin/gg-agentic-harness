---
name: generate-project-context
description: 'Generate or refresh docs/project-context.md from the current repository and enforce BMAD-style project-context discipline.'
user_invocable: true
---

# /generate-project-context

Generate a concise, actionable `docs/project-context.md` from the live codebase.

## Why

- Keeps AI implementation guidance aligned with current stack/tooling.
- Reduces drift between prompt rules and actual repository state.
- Provides a small, high-signal context file for all runtimes.

## Execution

1. Run:
```bash
npm run harness:project-context
```
2. Validate drift check:
```bash
npm run harness:project-context:check
```
3. If the context changed materially, note it in governance docs (`Task.md` / run artifact).

## Companion Rule

For review outputs and gate decisions, apply:

- `.agent/rules/adversarial-review.md`
