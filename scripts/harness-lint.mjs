#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const errors = [];
const warnings = [];

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function exists(file) {
  return fs.existsSync(file);
}

function fail(msg) {
  errors.push(msg);
}

function warn(msg) {
  warnings.push(msg);
}

const canonicalPrompt = 'CLAUDE.md';
const mirrorPrompt = 'AGENTS.md';

if (!exists(canonicalPrompt) || !exists(mirrorPrompt)) {
  fail('Missing CLAUDE.md or AGENTS.md');
} else if (read(canonicalPrompt) !== read(mirrorPrompt)) {
  fail('AGENTS.md must be byte-identical to CLAUDE.md (canonical source drift).');
}

if (exists(canonicalPrompt)) {
  const prompt = read(canonicalPrompt);
  if (!prompt.includes('remote-task-tracking.md') || !prompt.includes('gws-task.mjs')) {
    fail('CLAUDE.md must include remote task tracking references (remote-task-tracking.md and gws-task.mjs).');
  }
  if (!prompt.includes('adversarial-review.md') || !prompt.includes('harness:project-context')) {
    fail('CLAUDE.md must include BMAD cherry-pick references (adversarial-review.md and harness:project-context).');
  }
}

const requiredFiles = [
  'docs/agentic-harness.md',
  'docs/memory.md',
  'docs/runtime-profiles.md',
  '.agent/registry/mcp-runtime.json',
  '.agent/schemas/run-artifact.schema.json',
  '.agent/rules/dirty-worktree-policy.md',
  '.agent/policies/dirty-worktree-allowlist.txt',
  '.agent/policies/dirty-worktree-denylist.txt',
  'scripts/dirty-worktree-guard.sh',
  'scripts/agent-run-artifact.mjs',
  'scripts/generate-project-context.mjs',
  'scripts/gws-task.mjs',
  '.agent/rules/remote-task-tracking.md',
  '.agent/rules/adversarial-review.md',
  '.agent/workflows/generate-project-context.md',
  'docs/project-context.md'
];

for (const f of requiredFiles) {
  if (!exists(f)) fail(`Required file missing: ${f}`);
}

const localSkills = new Set();
if (exists('.agent/skills')) {
  for (const entry of fs.readdirSync('.agent/skills', { withFileTypes: true })) {
    if (entry.isDirectory() && !entry.name.startsWith('_')) localSkills.add(entry.name);
  }
}

const skillFiles = [
  'CLAUDE.md',
  'AGENTS.md',
  'docs/agentic-harness.md',
  '.agent/workflows/go.md',
  '.agent/workflows/minion.md'
].filter(exists);

const skillToken = /`([a-z][a-z0-9]*(?:-[a-z0-9]+)+)`/g;
const nonSkillAllow = new Set([
  'gg-skills',
  'no-emit',
  'find-related-tests',
  'test-quality-gate',
  'pre-launch-gate',
  'ctx-zone',
  'feature-branch',
  'release-hotfix',
  'nodejs-best-practices'
]);

for (const file of skillFiles) {
  const text = read(file);
  const lines = text.split('\n');
  lines.forEach((line, idx) => {
    if (!/(skill|skills|chain|primary|domain|use_skill)/i.test(line)) return;
    const matches = [...line.matchAll(skillToken)].map(m => m[1]);
    for (const token of matches) {
      if (localSkills.has(token)) continue;
      if (nonSkillAllow.has(token)) continue;
      if (/^(main|release|hotfix)$/.test(token)) continue;
      if (/^agent-/.test(token)) continue;
      fail(`${file}:${idx + 1} references unknown skill token: ${token}`);
    }
  });
}

const mcpRegistryPath = '.agent/registry/mcp-runtime.json';
if (exists(mcpRegistryPath)) {
  const registry = JSON.parse(read(mcpRegistryPath));
  const names = new Set();
  for (const profile of Object.values(registry.profiles || {})) {
    for (const n of profile.mcpServers || []) names.add(String(n).toLowerCase());
    for (const n of profile.optional || []) names.add(String(n).toLowerCase());
  }

  const harnessPath = 'docs/agentic-harness.md';
  if (exists(harnessPath)) {
    const text = read(harnessPath);

    if (/\b\d+\s+MCPs\b/.test(text)) {
      fail('docs/agentic-harness.md uses static MCP count; use runtime registry reference instead.');
    }

    if (/gg-agent-bridge/i.test(text)) {
      fail('docs/agentic-harness.md still references gg-agent-bridge, which is removed from runtime profile.');
    }

    if (/\b(a2a|gg-a2a-server)\b/i.test(text)) {
      fail('docs/agentic-harness.md still references A2A services, which are removed from active harness.');
    }

    const section = text.split('### MCP Servers')[1]?.split('---')[0] || '';
    const rows = section.split('\n').filter(l => l.trim().startsWith('|'));
    for (const row of rows) {
      if (row.includes('Server') || row.includes('---')) continue;
      const cells = row.split('|').map(c => c.trim()).filter(Boolean);
      const name = cells[0]?.replace(/`/g, '') || '';
      if (!name) continue;
      if (!names.has(name.toLowerCase())) {
        fail(`docs/agentic-harness.md MCP table references unknown server: ${name}`);
      }
    }
  }
}

const workflow = exists('.agent/workflows/minion.md') ? read('.agent/workflows/minion.md') : '';
if (workflow.includes('no human interjection mid-run') && workflow.includes('Escalate to human')) {
  fail('minion workflow contradiction: claims no interjection but also has escalation path.');
}

if (/\b(spawn_kimi|get_kimi|dispatch_to_a2a|gg-agent-bridge|gg-a2a-server)\b/i.test(workflow)) {
  fail('minion workflow still references removed Kimi/A2A bridge tools.');
}

const scriptRefRegex = /\.agent\/skills\/[a-z0-9_-]+\/scripts\/[a-zA-Z0-9_.-]+/g;
for (const file of ['.agent/workflows/minion.md', '.agent/rules/GEMINI.md']) {
  if (!exists(file)) continue;
  const refs = read(file).match(scriptRefRegex) || [];
  for (const ref of refs) {
    if (!exists(ref)) {
      fail(`${file} references missing script: ${ref}`);
    }
  }
}

if (warnings.length) {
  console.log('Warnings:');
  for (const w of warnings) console.log(`- ${w}`);
}

if (errors.length) {
  console.error('Harness lint failed:');
  for (const e of errors) console.error(`- ${e}`);
  process.exit(1);
}

console.log('Harness lint passed.');
