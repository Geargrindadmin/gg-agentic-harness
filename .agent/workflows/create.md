---
description: Generate a headless application bundle from a prompt, PRD, or canonical product spec.
---

# /create - Create Application

$ARGUMENTS

---

## Task

This command starts a headless application bundle generation process.

### Steps:

1. **Normalize Intake**
   - Accept a prompt, PRD path, or canonical `.spec.json`
   - Resolve product lane, target stack, packs, and delivery target

2. **Generate Bundle**
   - Build a deterministic application skeleton for supported lanes
   - Emit source files, bundle manifest, and handoff-ready README

3. **Record Evidence**
   - Write run artifact and canonical spec artifact
   - Preserve preflight status and warnings in the artifact payload

4. **Handoff**
   - Return bundle directory, manifest path, and generated file inventory
   - Leave validation and downstream install to explicit follow-up workflows

---

## Usage Examples

```
/create marketing site for an AI automation platform
/create SaaS dashboard with RBAC, billing, and settings
/create docs/prd/headless-build.md
/create docs/prd/admin-panel.spec.json
```

---

## Before Starting

If the intake is underspecified, the executable surface should still normalize it and generate the closest supported lane.
If lane confidence is low or packs require human review, record that in the run artifact rather than dropping into an interactive loop.
