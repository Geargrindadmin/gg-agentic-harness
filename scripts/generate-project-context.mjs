#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const outFile = path.join(root, 'docs', 'project-context.md');

const args = new Set(process.argv.slice(2));
const checkMode = args.has('--check');
const stdoutMode = args.has('--stdout');

function exists(filePath) {
  return fs.existsSync(filePath);
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function getWorkspacePackagePaths(workspaces) {
  const results = new Set();

  for (const rawPattern of workspaces || []) {
    if (typeof rawPattern !== 'string' || !rawPattern.trim()) continue;
    const pattern = rawPattern.trim();

    if (pattern.endsWith('/*')) {
      const baseDir = path.join(root, pattern.slice(0, -2));
      if (!exists(baseDir)) continue;
      const entries = fs.readdirSync(baseDir, { withFileTypes: true });
      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        const pkgPath = path.join(baseDir, entry.name, 'package.json');
        if (exists(pkgPath)) results.add(pkgPath);
      }
      continue;
    }

    const pkgPath = path.join(root, pattern, 'package.json');
    if (exists(pkgPath)) results.add(pkgPath);
  }

  return [...results].sort();
}

function flattenDeps(manifests) {
  const order = ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'];
  const map = new Map();

  for (const manifest of manifests) {
    for (const field of order) {
      const deps = manifest.pkg?.[field] || {};
      for (const [name, version] of Object.entries(deps)) {
        if (!map.has(name)) {
          map.set(name, { version: String(version), source: manifest.relPath, field });
        }
      }
    }
  }

  return map;
}

function findFirst(depMap, names) {
  for (const name of names) {
    if (depMap.has(name)) return { name, ...depMap.get(name) };
  }
  return null;
}

function formatDate(ts) {
  return new Date(ts).toISOString().slice(0, 10);
}

function generate() {
  const rootPkgPath = path.join(root, 'package.json');
  const rootPkg = readJson(rootPkgPath);
  if (!rootPkg) {
    throw new Error(`Missing or invalid package.json at ${rootPkgPath}`);
  }

  const workspacePkgPaths = getWorkspacePackagePaths(rootPkg.workspaces);
  const manifests = [{ relPath: 'package.json', pkg: rootPkg }];
  for (const absPath of workspacePkgPaths) {
    const pkg = readJson(absPath);
    if (!pkg) continue;
    manifests.push({
      relPath: path.relative(root, absPath),
      pkg
    });
  }

  const depMap = flattenDeps(manifests);
  const generatedAt = formatDate(Date.now());
  const nodeEngine = rootPkg.engines?.node ? String(rootPkg.engines.node) : 'unspecified';

  const lines = [];
  lines.push('---');
  lines.push(`generated_at: "${generatedAt}"`);
  lines.push('generator: "scripts/generate-project-context.mjs"');
  lines.push('source_files:');
  lines.push('  - "package.json"');
  for (const m of manifests.slice(1)) lines.push(`  - "${m.relPath}"`);
  lines.push('---');
  lines.push('');
  lines.push('# Project Context for AI Agents');
  lines.push('');
  lines.push('_Selective BMAD adoption: project-context generation + adversarial review discipline._');
  lines.push('');
  lines.push('---');
  lines.push('');
  lines.push('## Technology Stack & Versions');
  lines.push('');
  lines.push(`- **Node.js Engine**: \`${nodeEngine}\` (from \`package.json\`)`);
  lines.push(`- **TypeScript**: \`${findFirst(depMap, ['typescript'])?.version || 'not declared'}\``);
  lines.push(`- **React**: \`${findFirst(depMap, ['react'])?.version || 'not declared'}\``);
  lines.push(`- **MongoDB Driver**: \`${findFirst(depMap, ['mongodb'])?.version || 'not declared'}\``);
  lines.push(`- **Playwright Test**: \`${findFirst(depMap, ['@playwright/test'])?.version || 'not declared'}\``);
  lines.push(`- **Playwright CLI**: \`${findFirst(depMap, ['@playwright/cli'])?.version || 'not declared'}\``);
  lines.push(`- **Jest / ts-jest**: \`${findFirst(depMap, ['jest'])?.version || 'not declared'}\` / \`${findFirst(depMap, ['ts-jest'])?.version || 'not declared'}\``);
  lines.push(`- **ESLint / Prettier**: \`${findFirst(depMap, ['eslint'])?.version || 'not declared'}\` / \`${findFirst(depMap, ['prettier'])?.version || 'not declared'}\``);
  lines.push(`- **Payments/Comms SDKs**: Stripe \`${findFirst(depMap, ['stripe'])?.version || 'not declared'}\`, SendGrid \`${findFirst(depMap, ['@sendgrid/mail'])?.version || 'not declared'}\`, Twilio \`${findFirst(depMap, ['twilio'])?.version || 'not declared'}\``);
  lines.push('');
  lines.push('## Critical Implementation Rules');
  lines.push('');
  lines.push('### Governance');
  lines.push('- `docs/PRD.md` is the product source of truth; `Task.md` is execution checklist.');
  lines.push('- For `TASK|TASK_LITE|DECISION`, mirror run state with `node scripts/gws-task.mjs ...`.');
  lines.push('- Architectural changes require ADRs in `docs/decisions/ADR-NNN.md`.');
  lines.push('');
  lines.push('### Build and Validation Gates');
  lines.push('- Minimum completion gate: `npx tsc --noEmit`, `npm run lint`, relevant tests.');
  lines.push('- Before completion claims, apply `verification-before-completion` discipline with command evidence.');
  lines.push('- For UI flows, enforce screenshot-backed checks via Playwright tooling.');
  lines.push('');
  lines.push('### Security and Reliability');
  lines.push('- Follow `.agent/rules/anti-mocking.md`; allowlist-only mocks.');
  lines.push('- Apply adversarial review protocol from `.agent/rules/adversarial-review.md` for review tasks.');
  lines.push('- Never commit secrets; use env indirection for sensitive tokens and credentials.');
  lines.push('');
  lines.push('### Agentic Operating Rules');
  lines.push('- Runtime selection and MCP set are profile-driven via `docs/runtime-profiles.md` and `.agent/registry/mcp-runtime.json`.');
  lines.push('- `CLAUDE.md` is canonical prompt contract; `AGENTS.md` mirrors it exactly.');
  lines.push('- For agent handoffs, enforce file-claim and serialization from `docs/agentic-harness.md`.');
  lines.push('');
  lines.push('## BMAD Cherry Picks in GGV3');
  lines.push('');
  lines.push('- **Project context workflow**: generated by `scripts/generate-project-context.mjs`, surfaced through `.agent/workflows/generate-project-context.md`.');
  lines.push('- **Adversarial review**: explicit forced-findings review rule in `.agent/rules/adversarial-review.md`.');
  lines.push('');
  lines.push('## Usage');
  lines.push('');
  lines.push('- Regenerate after major architecture/tooling updates: `npm run harness:project-context`.');
  lines.push('- CI drift check: `npm run harness:project-context:check`.');
  lines.push('- Keep this file concise; link to source rule files for detail.');
  lines.push('');

  return `${lines.join('\n')}\n`;
}

function main() {
  const content = generate();
  if (stdoutMode) {
    process.stdout.write(content);
    return;
  }

  if (checkMode) {
    if (!exists(outFile)) {
      console.error(`Project context file missing: ${outFile}`);
      process.exit(1);
    }
    const current = fs.readFileSync(outFile, 'utf8');
    if (current === content) {
      console.log('Project context is up to date.');
      return;
    }
    console.error('Project context is stale. Run: node scripts/generate-project-context.mjs');
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, content, 'utf8');
  console.log(`Wrote ${path.relative(root, outFile)}`);
}

main();
