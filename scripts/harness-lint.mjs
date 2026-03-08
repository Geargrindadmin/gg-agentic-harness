#!/usr/bin/env node
import fs from 'node:fs';

const errors = [];

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function exists(file) {
  return fs.existsSync(file);
}

function fail(message) {
  errors.push(message);
}

function requireFile(file) {
  if (!exists(file)) fail(`Required file missing: ${file}`);
}

const promptFiles = ['CLAUDE.md', 'AGENTS.md', 'GEMINI.md'];
for (const file of promptFiles) requireFile(file);

if (promptFiles.every(exists)) {
  const base = read('CLAUDE.md');
  for (const file of ['AGENTS.md', 'GEMINI.md']) {
    if (read(file) !== base) {
      fail(`${file} must be byte-identical to CLAUDE.md.`);
    }
  }

  if (!base.includes('remote-task-tracking.md') || !base.includes('gws-task.mjs')) {
    fail('CLAUDE.md must reference remote task tracking.');
  }
  if (!base.includes('feedback-loop-governance.md') || !base.includes('feedback-loop-report.mjs')) {
    fail('CLAUDE.md must reference the feedback loop contract.');
  }
  if (!base.includes('persona-dispatch-governance.md') || !base.includes('persona-compounds.json')) {
    fail('CLAUDE.md must reference persona dispatch governance and the compound registry.');
  }
  if (!base.includes('agent-run-artifact.mjs persona') || !base.includes('harness:runtime-parity')) {
    fail('CLAUDE.md must reference persona routing artifact recording and runtime parity.');
  }
}

const requiredFiles = [
  'docs/agentic-harness.md',
  'docs/memory.md',
  'docs/runtime-profiles.md',
  'docs/project-context.md',
  '.agent/registry/mcp-runtime.json',
  '.agent/registry/persona-registry.json',
  '.agent/registry/persona-compounds.json',
  '.agent/schemas/run-artifact.schema.json',
  '.agent/rules/agent-roles.md',
  '.agent/rules/adversarial-review.md',
  '.agent/rules/dirty-worktree-policy.md',
  '.agent/rules/feedback-loop-governance.md',
  '.agent/rules/persona-dispatch-governance.md',
  '.agent/rules/remote-task-tracking.md',
  '.agent/policies/dirty-worktree-allowlist.txt',
  '.agent/policies/dirty-worktree-denylist.txt',
  '.agent/workflows/generate-project-context.md',
  '.agent/workflows/persona-dispatch.md',
  '.agent/workflows/runtime-parity-smoke.md',
  'scripts/agent-run-artifact.mjs',
  'scripts/runtime-project-sync.mjs',
  'scripts/codex-project-sync.mjs',
  'scripts/dirty-worktree-guard.sh',
  'scripts/feedback-loop-report.mjs',
  'scripts/generate-project-context.mjs',
  'scripts/gws-task.mjs',
  'scripts/persona-registry-audit.mjs',
  'scripts/persona-registry-lib.mjs',
  'scripts/persona-registry-benchmark.mjs',
  'scripts/persona-registry-resolve.mjs',
  'scripts/persona-registry-sync.mjs',
  'scripts/runtime-parity-smoke.mjs',
  'evals/persona-routing-corpus.json',
  'docs/decisions/0004-persona-registry-dispatch.md',
  'docs/decisions/0005-compound-persona-runtime.md',
  'docs/decisions/0007-runtime-activation-adapters.md'
];

for (const file of requiredFiles) requireFile(file);

if (exists('docs/agentic-harness.md')) {
  const text = read('docs/agentic-harness.md');
  if (!text.includes('persona-registry-resolve.mjs') || !text.includes('compoundPersona')) {
    fail('docs/agentic-harness.md must describe persona resolution and compound persona routing.');
  }
  if (!text.includes('agent-run-artifact.mjs persona')) {
    fail('docs/agentic-harness.md must include persona routing artifact recording.');
  }
  if (/\b\d+\s+MCPs\b/.test(text)) {
    fail('docs/agentic-harness.md must not use a static MCP count.');
  }
}

if (exists('.agent/registry/mcp-runtime.json')) {
  try {
    const registry = JSON.parse(read('.agent/registry/mcp-runtime.json'));
    if (!registry.profiles || typeof registry.profiles !== 'object') {
      fail('.agent/registry/mcp-runtime.json must define profiles.');
    }
  } catch (error) {
    fail(`Invalid JSON: .agent/registry/mcp-runtime.json (${String(error)})`);
  }
}

for (const file of [
  '.agent/registry/persona-registry.json',
  '.agent/registry/persona-compounds.json',
  '.agent/schemas/run-artifact.schema.json'
]) {
  if (!exists(file)) continue;
  try {
    JSON.parse(read(file));
  } catch (error) {
    fail(`Invalid JSON: ${file} (${String(error)})`);
  }
}

if (errors.length) {
  console.error('Harness lint failed:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log('Harness lint passed.');
