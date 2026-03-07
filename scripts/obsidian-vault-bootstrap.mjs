#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const vaultPath = process.env.OBSIDIAN_VAULT_PATH || path.join(repoRoot, 'docs');

const dirs = [
  '00-Inbox',
  '01-Daily',
  '02-Projects',
  '03-Decisions',
  '04-Runbooks',
  '05-Model-Runs/codex',
  '05-Model-Runs/claude',
  '05-Model-Runs/kimi',
  '05-Model-Runs/gemini',
  '90-Templates',
  '99-Archive'
];

for (const rel of dirs) {
  fs.mkdirSync(path.join(vaultPath, rel), { recursive: true });
}

const templates = [
  {
    rel: '90-Templates/model-session.md',
    content: `---
model: {{model}}
runtime: {{runtime}}
created: {{created_iso}}
topic: {{topic}}
---

## Context

## Decisions

## Actions

## Follow-ups
`
  },
  {
    rel: '90-Templates/decision.md',
    content: `---
type: decision
date: {{date}}
owner: {{owner}}
status: proposed
---

## Problem

## Decision

## Consequences
`
  },
  {
    rel: '90-Templates/daily.md',
    content: `# {{date}}

## Top Priorities

## Work Log

## Blockers

## Next
`
  },
  {
    rel: '00-Inbox/README.md',
    content: `# Inbox

Drop fast notes here. Triage into Projects/Decisions/Runbooks during review.\n`
  }
];

for (const tpl of templates) {
  const filePath = path.join(vaultPath, tpl.rel);
  if (!fs.existsSync(filePath)) {
    fs.writeFileSync(filePath, tpl.content, 'utf8');
  }
}

const indexPath = path.join(vaultPath, 'OBSIDIAN_HOME.md');
if (!fs.existsSync(indexPath)) {
  fs.writeFileSync(
    indexPath,
    `# Obsidian Home\n\n- [[00-Inbox/README]]\n- [[01-Daily]]\n- [[02-Projects]]\n- [[03-Decisions]]\n- [[04-Runbooks]]\n- [[05-Model-Runs]]\n- [[90-Templates]]\n- [[99-Archive]]\n`,
    'utf8'
  );
}

console.log(`Vault bootstrap complete at ${vaultPath}`);
