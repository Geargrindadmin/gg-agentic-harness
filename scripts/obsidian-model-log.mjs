#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const vaultPath = process.env.OBSIDIAN_VAULT_PATH || path.join(repoRoot, 'docs');

const allowedModels = new Set(['codex', 'claude', 'kimi', 'gemini']);

function parseArgs(argv) {
  const out = { model: '', title: '', body: '' };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--model') out.model = String(argv[++i] || '').toLowerCase();
    else if (a === '--title') out.title = String(argv[++i] || '');
    else if (a === '--body') out.body = String(argv[++i] || '');
    else if (a === '--body-file') out.body = fs.readFileSync(String(argv[++i] || ''), 'utf8');
  }
  return out;
}

function slugify(input) {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 80) || 'note';
}

const args = parseArgs(process.argv.slice(2));
if (!args.model || !allowedModels.has(args.model)) {
  console.error('Usage: node scripts/obsidian-model-log.mjs --model <codex|claude|kimi|gemini> --title "..." [--body "..."] [--body-file <path>]');
  process.exit(1);
}
if (!args.title) {
  console.error('Missing required --title');
  process.exit(1);
}

const now = new Date();
const yyyy = String(now.getFullYear());
const mm = String(now.getMonth() + 1).padStart(2, '0');
const dd = String(now.getDate()).padStart(2, '0');
const hh = String(now.getHours()).padStart(2, '0');
const min = String(now.getMinutes()).padStart(2, '0');
const ss = String(now.getSeconds()).padStart(2, '0');

const day = `${yyyy}-${mm}-${dd}`;
const fileName = `${hh}${min}${ss}-${slugify(args.title)}.md`;
const relDir = path.join('05-Model-Runs', args.model, day);
const absDir = path.join(vaultPath, relDir);
const absFile = path.join(absDir, fileName);
const relFile = path.join(relDir, fileName);

fs.mkdirSync(absDir, { recursive: true });

const content = `---
model: ${args.model}
created: ${now.toISOString()}
title: ${args.title.replace(/\n/g, ' ')}
---

# ${args.title}

${args.body || '_No body provided._'}
`;

fs.writeFileSync(absFile, content, 'utf8');
console.log(relFile);
