#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { loadRegistry, REPO_ROOT } from './persona-registry-lib.mjs';

const registry = loadRegistry();
const START = '<!-- persona-registry:start -->';
const END = '<!-- persona-registry:end -->';

function makeGeneratedBlock(persona, includeMemory) {
  const lines = [
    START,
    '## Agent Constraints',
    `- Role: ${persona.role}`,
    `- Allowed: ${persona.allowed.join('; ')}`,
    `- Blocked: ${persona.blocked.join('; ')}`,
    '',
    '## Persona Dispatch Signals',
    `- Primary domains: ${persona.domains.join(', ')}`,
    `- Auto-select when: ${persona.selectionTriggers.join(', ')}`,
    `- Default partners: ${persona.defaultPartners.join(', ') || 'none'}`,
    `- Memory query: ${persona.memoryQuery}`,
    `- Escalate to coordinator when: ${persona.requiresBoardFor.join(', ') || 'board review not normally required'}, file-claim conflicts, or low-confidence routing`,
    ''
  ];

  if (includeMemory) {
    lines.push(
      '## Memory Context',
      '**Activate on load — run before domain research:**',
      '',
      `1. \`search(query="${persona.memoryQuery}", limit=8)\` — prime context`,
      '2. `timeline(id=<top result>)` — get chronological context',
      '3. `get_observations(ids=[<top 3 IDs>])` — fetch full details for relevant observations',
      '',
      'Use retrieved observations to avoid repeating prior work and to surface recent decisions before editing code.',
      ''
    );
  }

  lines.push(END);
  return lines.join('\n');
}

function upsertBlock(text, block) {
  const pattern = new RegExp(`${START}[\\s\\S]*?${END}\\n?`, 'm');
  if (pattern.test(text)) {
    return text.replace(pattern, `${block}\n`);
  }
  const trimmed = text.replace(/\s*$/, '');
  return `${trimmed}\n\n${block}\n`;
}

for (const persona of registry.personas) {
  const file = path.join(REPO_ROOT, persona.file);
  const text = fs.readFileSync(file, 'utf8');
  const includeMemory = !text.includes('## Memory Context');
  const updated = upsertBlock(text, makeGeneratedBlock(persona, includeMemory));
  if (updated !== text) {
    fs.writeFileSync(file, updated);
    console.log(`synced ${persona.id}`);
  }
}
