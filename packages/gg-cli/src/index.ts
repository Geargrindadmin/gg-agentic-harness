#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  getHarnessPaths,
  loadSkills,
  loadWorkflows,
  readCatalogEntryContent,
  readJsonFile,
  resolveProjectRoot,
  searchCatalog,
  type CatalogEntry
} from '../../gg-core/dist/index.js';

type FlagValue = string | boolean | string[];

interface ParsedArgs {
  flags: Record<string, FlagValue>;
  positionals: string[];
}

interface CommandResult {
  code: number;
  payload?: unknown;
}

interface ExecOutcome {
  code: number;
  stdout: string;
  stderr: string;
  command: string;
  args: string[];
}

function usage(): never {
  console.log(`
GG CLI

Usage:
  gg [--json] [--project-root <path>] doctor
  gg [--json] [--project-root <path>] skills list [--category <name>] [--limit <n>]
  gg [--json] [--project-root <path>] skills find <query> [--limit <n>]
  gg [--json] [--project-root <path>] skills show <slug>
  gg [--json] [--project-root <path>] workflow list [--limit <n>]
  gg [--json] [--project-root <path>] workflow find <query> [--limit <n>]
  gg [--json] [--project-root <path>] workflow show <slug>
  gg [--json] [--project-root <path>] workflow run <slug> [args...] [--validate none|tsc|lint|test|all] [--evidence <path[,path]>]
  gg [--json] [--project-root <path>] run <init|gate|mcp|complete> [--key value]
  gg [--json] [--project-root <path>] context <check|refresh>
  gg [--json] [--project-root <path>] validate <tsc|lint|test|all>
  gg [--json] [--project-root <path>] obsidian <doctor|bootstrap|model-log>
  gg [--json] [--project-root <path>] portable init <targetDir> [--mode symlink|copy]
`.trim());
  process.exit(2);
}

function parseArgs(argv: string[]): ParsedArgs {
  const flags: Record<string, FlagValue> = {};
  const positionals: string[] = [];

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      positionals.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[i + 1];
    const value: FlagValue = !next || next.startsWith('--') ? true : next;

    if (value !== true) {
      i += 1;
    }

    const existing = flags[key];
    if (existing === undefined) {
      flags[key] = value;
      continue;
    }

    if (Array.isArray(existing)) {
      existing.push(String(value));
      flags[key] = existing;
      continue;
    }

    flags[key] = [String(existing), String(value)];
  }

  return { flags, positionals };
}

function flagString(flags: Record<string, FlagValue>, key: string): string | undefined {
  const value = flags[key];
  if (value === undefined || typeof value === 'boolean') return undefined;
  if (Array.isArray(value)) return value[0];
  return value;
}

function flagStringArray(flags: Record<string, FlagValue>, key: string): string[] {
  const value = flags[key];
  if (value === undefined || typeof value === 'boolean') return [];
  const list = Array.isArray(value) ? value : [value];
  return list
    .flatMap((item) => item.split(','))
    .map((item) => item.trim())
    .filter(Boolean);
}

function intFlag(flags: Record<string, FlagValue>, name: string, fallback: number): number {
  const value = flagString(flags, name);
  if (value === undefined) {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`Invalid --${name} value: ${value}`);
  }
  return parsed;
}

function executeCommand(command: string, args: string[], cwd: string, capture: boolean): ExecOutcome {
  const res = spawnSync(command, args, {
    cwd,
    stdio: capture ? 'pipe' : 'inherit',
    encoding: 'utf8',
    shell: false
  });

  return {
    code: res.status ?? 1,
    stdout: typeof res.stdout === 'string' ? res.stdout : '',
    stderr: typeof res.stderr === 'string' ? res.stderr : '',
    command,
    args
  };
}

function printCatalog(entries: CatalogEntry[], withCategory = false): void {
  for (const entry of entries) {
    const description = entry.description || '(no description)';
    if (withCategory) {
      console.log(`${entry.slug}\t${entry.category || '-'}\t${description}`);
    } else {
      console.log(`${entry.slug}\t${description}`);
    }
  }
}

function isoNow(): string {
  return new Date().toISOString();
}

function dateStamp(): string {
  return isoNow().slice(0, 10);
}

function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9]+/gu, '-')
    .replace(/^-+|-+$/gu, '')
    .slice(0, 80);
}

function writeJson(filePath: string, payload: unknown): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
}

function commandDoctor(projectRoot: string, jsonMode: boolean): CommandResult {
  const paths = getHarnessPaths(projectRoot);

  const checks = [
    { name: 'projectRoot', ok: fs.existsSync(paths.projectRoot), detail: paths.projectRoot },
    { name: '.agent directory', ok: fs.existsSync(paths.agentDir), detail: paths.agentDir },
    { name: 'skills directory', ok: fs.existsSync(paths.skillsDir), detail: paths.skillsDir },
    { name: 'workflows directory', ok: fs.existsSync(paths.workflowsDir), detail: paths.workflowsDir },
    { name: '.mcp.json', ok: fs.existsSync(paths.mcpConfigPath), detail: paths.mcpConfigPath }
  ];

  const skills = loadSkills(projectRoot);
  const workflows = loadWorkflows(projectRoot);
  checks.push({ name: 'skills loaded', ok: skills.length > 0, detail: `${skills.length}` });
  checks.push({ name: 'workflows loaded', ok: workflows.length > 0, detail: `${workflows.length}` });

  const mcpConfig = readJsonFile<{ mcpServers?: Record<string, { args?: string[] }> }>(paths.mcpConfigPath);
  const ggSkillsPath = mcpConfig?.mcpServers?.['gg-skills']?.args?.[0] || 'missing';
  checks.push({
    name: 'gg-skills server path',
    ok: ggSkillsPath !== 'missing',
    detail: ggSkillsPath
  });

  const failures = checks.filter((item) => !item.ok).length;

  if (!jsonMode) {
    for (const check of checks) {
      const prefix = check.ok ? 'PASS' : 'FAIL';
      console.log(`${prefix} ${check.name}: ${check.detail}`);
    }
  }

  return {
    code: failures === 0 ? 0 : 1,
    payload: {
      checks,
      skillsCount: skills.length,
      workflowsCount: workflows.length
    }
  };
}

function commandSkills(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  const { flags, positionals } = parseArgs(argv);
  const skills = loadSkills(projectRoot);

  if (action === 'list') {
    const limit = intFlag(flags, 'limit', skills.length);
    const categoryFilter = (flagString(flags, 'category') || '').toLowerCase();
    const filtered = categoryFilter
      ? skills.filter((item) => (item.category || '').toLowerCase() === categoryFilter)
      : skills;
    const items = filtered.slice(0, limit);

    if (!jsonMode) {
      printCatalog(items, true);
    }

    return { code: 0, payload: { count: items.length, items } };
  }

  if (action === 'find') {
    const query = positionals.join(' ').trim();
    if (!query) {
      throw new Error('Usage: gg skills find <query> [--limit <n>]');
    }

    const limit = intFlag(flags, 'limit', 5);
    const hits = searchCatalog(skills, query, limit);

    if (!jsonMode) {
      printCatalog(hits, true);
    }

    return { code: 0, payload: { query, count: hits.length, items: hits } };
  }

  if (action === 'show') {
    const slug = positionals[0];
    if (!slug) {
      throw new Error('Usage: gg skills show <slug>');
    }

    const found = skills.find((item) => item.slug === slug);
    if (!found) {
      throw new Error(`Skill not found: ${slug}`);
    }

    const content = readCatalogEntryContent(found);
    if (!jsonMode) {
      console.log(content);
    }

    return { code: 0, payload: { slug, entry: found, content } };
  }

  throw new Error('Usage: gg skills <list|find|show> ...');
}

function buildValidationCommands(mode: string): Array<{ id: string; command: string; args: string[] }> {
  switch (mode) {
    case 'none':
      return [];
    case 'tsc':
      return [{ id: 'tsc', command: 'npm', args: ['run', 'type-check'] }];
    case 'lint':
      return [{ id: 'lint', command: 'npm', args: ['run', 'lint'] }];
    case 'test':
      return [{ id: 'test', command: 'npm', args: ['test'] }];
    case 'all':
      return [
        { id: 'tsc', command: 'npm', args: ['run', 'type-check'] },
        { id: 'lint', command: 'npm', args: ['run', 'lint'] },
        { id: 'test', command: 'npm', args: ['test'] }
      ];
    default:
      throw new Error('Invalid --validate mode. Use one of: none|tsc|lint|test|all');
  }
}

function runPaperclipExtracted(
  projectRoot: string,
  objective: string,
  jsonMode: boolean
): CommandResult {
  if (!objective.trim()) {
    throw new Error('paperclip-extracted requires an objective string');
  }

  const skills = loadSkills(projectRoot);
  const workflows = loadWorkflows(projectRoot);
  const matchedSkills = searchCatalog(skills, objective, 5);
  const matchedWorkflows = searchCatalog(workflows, objective, 5);
  const preferredOrder = [
    'go',
    'minion',
    'symphony-lite',
    'paperclip-extracted',
    'parallel-dispatcher',
    'loop-planner',
    'loop-executor'
  ];
  const preferred = matchedWorkflows.find((item) => preferredOrder.includes(item.slug));
  const primaryWorkflow = preferred?.slug || 'go';
  const validators = ['npx tsc --noEmit', 'npm run lint', 'npx jest --findRelatedTests <changed-files>'];

  const runId = `paperclip-${Date.now()}`;
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);

  const artifact = {
    schemaVersion: 1,
    runId,
    workflow: 'paperclip-extracted',
    objective,
    primaryWorkflow,
    matchedSkills: matchedSkills.map((item) => item.slug),
    matchedWorkflows: matchedWorkflows.map((item) => item.slug),
    gates: [
      { gate: 'A', name: 'plan-approved', status: 'planned' },
      { gate: 'B', name: 'implementation-complete', status: 'planned' },
      { gate: 'C', name: 'validation-pass', status: 'planned' },
      { gate: 'D', name: 'handoff-documented', status: 'planned' }
    ],
    validators,
    status: 'planned',
    createdAt: isoNow()
  };

  writeJson(runPath, artifact);

  const reportSlug = slugify(objective) || 'objective';
  const reportPath = path.join(projectRoot, 'docs', 'reports', `${dateStamp()}-paperclip-${reportSlug}.md`);
  const report = [
    '# Paperclip Extracted Run',
    '',
    `- Objective: ${objective}`,
    `- Primary workflow: ${primaryWorkflow}`,
    `- Run artifact: ${path.relative(projectRoot, runPath)}`,
    '',
    '## Matched Skills',
    ...matchedSkills.map((item) => `- ${item.slug}: ${item.description}`),
    '',
    '## Matched Workflows',
    ...matchedWorkflows.map((item) => `- ${item.slug}: ${item.description}`),
    '',
    '## Validation Plan',
    ...validators.map((item) => `- ${item}`),
    ''
  ].join('\n');

  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${report}\n`, 'utf8');

  if (!jsonMode) {
    console.log(`Paperclip extracted run planned: ${runId}`);
    console.log(`Primary workflow: ${primaryWorkflow}`);
    console.log(`Report: ${reportPath}`);
  }

  return {
    code: 0,
    payload: {
      runId,
      outcome: 'PLANNED',
      runArtifact: runPath,
      reportPath,
      primaryWorkflow,
      matchedSkills,
      matchedWorkflows,
      validators
    }
  };
}

function runSymphonyLite(
  projectRoot: string,
  task: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!task.trim()) {
    throw new Error('symphony-lite requires a task string');
  }

  const validateMode = flagString(flags, 'validate') || 'none';
  const worktreeMode = flagString(flags, 'worktree') || 'none';
  const validationPlan = buildValidationCommands(validateMode);
  const commandResults: Array<{ id: string; code: number; command: string; args: string[]; stdout?: string; stderr?: string }> = [];

  for (const item of validationPlan) {
    if (!jsonMode) {
      console.log(`Running validation [${item.id}]: ${item.command} ${item.args.join(' ')}`);
    }

    const result = executeCommand(item.command, item.args, projectRoot, jsonMode);
    commandResults.push({
      id: item.id,
      code: result.code,
      command: item.command,
      args: item.args,
      stdout: jsonMode ? result.stdout : undefined,
      stderr: jsonMode ? result.stderr : undefined
    });

    if (result.code !== 0) {
      break;
    }
  }

  const failed = commandResults.find((item) => item.code !== 0);
  const outcome = failed ? 'BLOCKED' : 'HANDOFF_READY';
  const runId = `symphony-${Date.now()}`;
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);

  const artifact = {
    schemaVersion: 1,
    runId,
    workflow: 'symphony-lite',
    task,
    worktreeMode,
    validateMode,
    validations: commandResults,
    status: outcome,
    createdAt: isoNow()
  };

  writeJson(runPath, artifact);

  if (!jsonMode) {
    console.log(`Symphony run completed with status: ${outcome}`);
    console.log(`Run artifact: ${runPath}`);
  }

  return {
    code: failed ? 1 : 0,
    payload: {
      runId,
      outcome,
      validateMode,
      worktreeMode,
      runArtifact: runPath,
      validations: commandResults
    }
  };
}

function runVisualExplainer(
  projectRoot: string,
  subject: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!subject.trim()) {
    throw new Error('visual-explainer requires a subject string');
  }

  const evidence = flagStringArray(flags, 'evidence');
  const reportSlug = slugify(subject) || 'report';
  const baseName = `${dateStamp()}-${reportSlug}`;
  const reportDir = path.join(projectRoot, 'docs', 'reports');
  fs.mkdirSync(reportDir, { recursive: true });

  const markdownPath = path.join(reportDir, `${baseName}.md`);
  const htmlPath = path.join(reportDir, `${baseName}.html`);

  const md = [
    `# Visual Explainer: ${subject}`,
    '',
    `- Generated: ${isoNow()}`,
    `- Project root: ${projectRoot}`,
    '',
    '## Summary',
    '',
    '- Explain the architecture, diff, plan, or audit for this subject.',
    '',
    '## Evidence',
    ...(evidence.length > 0 ? evidence.map((item) => `- ${item}`) : ['- No explicit evidence paths provided.']),
    '',
    '## Key Decisions',
    '',
    '- Document the major choices and trade-offs here.',
    '',
    '## Next Actions',
    '',
    '- Capture execution follow-ups and owners.',
    ''
  ].join('\n');

  const htmlEvidence = evidence.length > 0 ? evidence.map((item) => `<li>${item}</li>`).join('') : '<li>No explicit evidence paths provided.</li>';
  const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Visual Explainer: ${subject}</title>
    <style>
      :root { color-scheme: light dark; }
      body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; margin: 2rem auto; max-width: 900px; padding: 0 1rem; line-height: 1.5; }
      h1, h2 { line-height: 1.2; }
      code { background: rgba(127, 127, 127, 0.15); padding: 0.1rem 0.35rem; border-radius: 4px; }
      .meta { opacity: 0.8; }
    </style>
  </head>
  <body>
    <h1>Visual Explainer: ${subject}</h1>
    <p class="meta">Generated: ${isoNow()}</p>
    <h2>Summary</h2>
    <p>Explain the architecture, diff, plan, or audit for this subject.</p>
    <h2>Evidence</h2>
    <ul>${htmlEvidence}</ul>
    <h2>Key Decisions</h2>
    <p>Document the major choices and trade-offs here.</p>
    <h2>Next Actions</h2>
    <p>Capture execution follow-ups and owners.</p>
  </body>
</html>
`;

  fs.writeFileSync(markdownPath, `${md}\n`, 'utf8');
  fs.writeFileSync(htmlPath, html, 'utf8');

  if (!jsonMode) {
    console.log(`Visual explainer created:`);
    console.log(`- ${markdownPath}`);
    console.log(`- ${htmlPath}`);
  }

  return {
    code: 0,
    payload: {
      subject,
      markdownPath,
      htmlPath,
      evidence
    }
  };
}

function commandWorkflow(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  const { flags, positionals } = parseArgs(argv);
  const workflows = loadWorkflows(projectRoot);

  if (action === 'list') {
    const limit = intFlag(flags, 'limit', workflows.length);
    const items = workflows.slice(0, limit);
    if (!jsonMode) {
      printCatalog(items);
    }
    return { code: 0, payload: { count: items.length, items } };
  }

  if (action === 'find') {
    const query = positionals.join(' ').trim();
    if (!query) {
      throw new Error('Usage: gg workflow find <query> [--limit <n>]');
    }

    const limit = intFlag(flags, 'limit', 5);
    const hits = searchCatalog(workflows, query, limit);
    if (!jsonMode) {
      printCatalog(hits);
    }
    return { code: 0, payload: { query, count: hits.length, items: hits } };
  }

  if (action === 'show') {
    const slug = positionals[0];
    if (!slug) {
      throw new Error('Usage: gg workflow show <slug>');
    }

    const found = workflows.find((item) => item.slug === slug);
    if (!found) {
      throw new Error(`Workflow not found: ${slug}`);
    }

    const content = readCatalogEntryContent(found);
    if (!jsonMode) {
      console.log(content);
    }

    return { code: 0, payload: { slug, entry: found, content } };
  }

  if (action === 'run') {
    const slug = positionals[0];
    const runtimeInput = positionals.slice(1).join(' ').trim();

    if (!slug) {
      throw new Error('Usage: gg workflow run <slug> [args...]');
    }

    const found = workflows.find((item) => item.slug === slug);
    if (!found) {
      throw new Error(`Workflow not found: ${slug}`);
    }

    if (slug === 'paperclip-extracted') {
      return runPaperclipExtracted(projectRoot, runtimeInput, jsonMode);
    }

    if (slug === 'symphony-lite') {
      return runSymphonyLite(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'visual-explainer') {
      return runVisualExplainer(projectRoot, runtimeInput, flags, jsonMode);
    }

    const paths = getHarnessPaths(projectRoot);
    const runId = `workflow-${slug}-${Date.now()}`;
    const runPath = path.join(paths.runArtifactDir, `${runId}.json`);
    const payload = {
      schemaVersion: 1,
      runId,
      type: 'workflow',
      slug,
      input: runtimeInput,
      args: positionals.slice(1),
      status: 'planned',
      createdAt: isoNow(),
      mode: 'scaffold-only'
    };

    writeJson(runPath, payload);

    if (!jsonMode) {
      console.log(`Planned workflow run: ${runId}`);
      console.log(`Workflow file: ${found.filePath}`);
      console.log(`Run artifact: ${runPath}`);
      console.log('No executable adapter for this slug yet; use workflow contract manually.');
    }

    return {
      code: 0,
      payload: {
        runId,
        mode: 'scaffold-only',
        workflowFile: found.filePath,
        runArtifact: runPath
      }
    };
  }

  throw new Error('Usage: gg workflow <list|find|show|run> ...');
}

function commandRun(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  if (!action || !['init', 'gate', 'mcp', 'complete'].includes(action)) {
    throw new Error('Usage: gg run <init|gate|mcp|complete> [--key value]');
  }

  const scriptPath = path.join(projectRoot, 'scripts', 'agent-run-artifact.mjs');
  const result = executeCommand('node', [scriptPath, action, ...argv], projectRoot, jsonMode);

  if (!jsonMode) {
    return { code: result.code };
  }

  return {
    code: result.code,
    payload: {
      command: result.command,
      args: result.args,
      stdout: result.stdout,
      stderr: result.stderr
    }
  };
}

function commandContext(projectRoot: string, action: string | undefined, jsonMode: boolean): CommandResult {
  const scriptPath = path.join(projectRoot, 'scripts', 'generate-project-context.mjs');

  let result: ExecOutcome;
  if (action === 'check') {
    result = executeCommand('node', [scriptPath, '--check'], projectRoot, jsonMode);
  } else if (action === 'refresh') {
    result = executeCommand('node', [scriptPath], projectRoot, jsonMode);
  } else {
    throw new Error('Usage: gg context <check|refresh>');
  }

  if (!jsonMode) {
    return { code: result.code };
  }

  return {
    code: result.code,
    payload: {
      action,
      stdout: result.stdout,
      stderr: result.stderr
    }
  };
}

function commandValidate(projectRoot: string, action: string | undefined, jsonMode: boolean): CommandResult {
  const plan = (() => {
    switch (action) {
      case 'tsc':
        return [{ id: 'tsc', command: 'npm', args: ['run', 'type-check'] }];
      case 'lint':
        return [{ id: 'lint', command: 'npm', args: ['run', 'lint'] }];
      case 'test':
        return [{ id: 'test', command: 'npm', args: ['test'] }];
      case 'all':
        return [
          { id: 'tsc', command: 'npm', args: ['run', 'type-check'] },
          { id: 'lint', command: 'npm', args: ['run', 'lint'] },
          { id: 'test', command: 'npm', args: ['test'] }
        ];
      default:
        throw new Error('Usage: gg validate <tsc|lint|test|all>');
    }
  })();

  const executions: Array<{ id: string; code: number; command: string; args: string[]; stdout?: string; stderr?: string }> = [];

  for (const item of plan) {
    const result = executeCommand(item.command, item.args, projectRoot, jsonMode);
    executions.push({
      id: item.id,
      code: result.code,
      command: result.command,
      args: result.args,
      stdout: jsonMode ? result.stdout : undefined,
      stderr: jsonMode ? result.stderr : undefined
    });
    if (result.code !== 0) {
      break;
    }
  }

  const failed = executions.find((item) => item.code !== 0);

  return {
    code: failed ? 1 : 0,
    payload: {
      action,
      checks: executions,
      status: failed ? 'failed' : 'passed'
    }
  };
}

function commandObsidian(projectRoot: string, action: string | undefined, jsonMode: boolean): CommandResult {
  let result: ExecOutcome;

  switch (action) {
    case 'doctor':
      result = executeCommand('npm', ['run', 'obsidian:doctor'], projectRoot, jsonMode);
      break;
    case 'bootstrap':
      result = executeCommand('npm', ['run', 'obsidian:vault:init'], projectRoot, jsonMode);
      break;
    case 'model-log':
      result = executeCommand('npm', ['run', 'obsidian:model-log'], projectRoot, jsonMode);
      break;
    default:
      throw new Error('Usage: gg obsidian <doctor|bootstrap|model-log>');
  }

  if (!jsonMode) {
    return { code: result.code };
  }

  return {
    code: result.code,
    payload: {
      action,
      stdout: result.stdout,
      stderr: result.stderr
    }
  };
}

function ensureSymlinkOrCopy(source: string, destination: string, mode: 'symlink' | 'copy'): void {
  if (fs.existsSync(destination)) {
    return;
  }

  if (mode === 'symlink') {
    fs.symlinkSync(source, destination, 'junction');
    return;
  }

  fs.cpSync(source, destination, { recursive: true });
}

function renderMcpConfig(targetRoot: string): string {
  return JSON.stringify(
    {
      mcpServers: {
        'gg-skills': {
          command: 'node',
          args: [path.join(targetRoot, 'mcp-servers', 'gg-skills', 'dist', 'index.js')],
          env: {
            SKILLS_DIR: path.join(targetRoot, '.agent', 'skills'),
            WORKFLOWS_DIR: path.join(targetRoot, '.agent', 'workflows')
          }
        }
      }
    },
    null,
    2
  );
}

function commandPortable(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  if (action !== 'init') {
    throw new Error('Usage: gg portable init <targetDir> [--mode symlink|copy]');
  }

  const { flags, positionals } = parseArgs(argv);
  const targetDir = positionals[0];
  if (!targetDir) {
    throw new Error('Usage: gg portable init <targetDir> [--mode symlink|copy]');
  }

  const mode = (flagString(flags, 'mode') === 'copy' ? 'copy' : 'symlink') as 'symlink' | 'copy';
  const targetRoot = path.resolve(targetDir);

  fs.mkdirSync(targetRoot, { recursive: true });
  fs.mkdirSync(path.join(targetRoot, 'mcp-servers'), { recursive: true });

  const targetPackagePath = path.join(targetRoot, 'package.json');
  if (!fs.existsSync(targetPackagePath)) {
    const packageName = slugify(path.basename(targetRoot) || 'agentic-target') || 'agentic-target';
    writeJson(targetPackagePath, {
      name: packageName,
      private: true,
      version: '0.0.0',
      type: 'module'
    });
  }

  ensureSymlinkOrCopy(path.join(projectRoot, '.agent'), path.join(targetRoot, '.agent'), mode);
  ensureSymlinkOrCopy(
    path.join(projectRoot, 'mcp-servers', 'gg-skills'),
    path.join(targetRoot, 'mcp-servers', 'gg-skills'),
    mode
  );

  const sourcePrompt = path.join(projectRoot, 'CLAUDE.md');
  const targetPrompt = path.join(targetRoot, 'CLAUDE.md');
  if (!fs.existsSync(targetPrompt)) {
    fs.copyFileSync(sourcePrompt, targetPrompt);
  }

  const agentsAlias = path.join(targetRoot, 'AGENTS.md');
  if (!fs.existsSync(agentsAlias)) {
    fs.symlinkSync('CLAUDE.md', agentsAlias);
  }

  const mcpPath = path.join(targetRoot, '.mcp.json');
  if (!fs.existsSync(mcpPath)) {
    fs.writeFileSync(mcpPath, `${renderMcpConfig(targetRoot)}\n`, 'utf8');
  }

  const installNotesPath = path.join(targetRoot, 'PORTABLE_AGENTIC_SETUP.md');
  if (!fs.existsSync(installNotesPath)) {
    const notes = [
      '# Portable Agentic Harness Setup',
      '',
      `- Mode: ${mode}`,
      `- Source: ${projectRoot}`,
      `- Target: ${targetRoot}`,
      '',
      '## Next Steps',
      '',
      '1. Install and build gg-skills in target:',
      '```bash',
      `npm --prefix ${path.join(targetRoot, 'mcp-servers', 'gg-skills')} install`,
      `npm --prefix ${path.join(targetRoot, 'mcp-servers', 'gg-skills')} run build`,
      '```',
      '2. Open your IDE in target root and verify MCP loads `.mcp.json`.',
      '3. Run `gg doctor` from target (after linking gg-cli).',
      ''
    ].join('\n');
    fs.writeFileSync(installNotesPath, notes, 'utf8');
  }

  if (!jsonMode) {
    console.log(`Portable harness initialized at: ${targetRoot}`);
    console.log(`Mode: ${mode}`);
    console.log(`MCP config: ${mcpPath}`);
    console.log(`Setup notes: ${installNotesPath}`);
  }

  return {
    code: 0,
    payload: {
      targetRoot,
      mode,
      mcpConfig: mcpPath,
      setupNotes: installNotesPath
    }
  };
}

function main(): void {
  const rawArgs = process.argv.slice(2);
  let jsonMode = false;
  let explicitProjectRoot: string | undefined;
  const args: string[] = [];

  for (let i = 0; i < rawArgs.length; i += 1) {
    const token = rawArgs[i];
    if (token === '--json') {
      jsonMode = true;
      continue;
    }
    if (token === '--project-root') {
      explicitProjectRoot = rawArgs[i + 1];
      i += 1;
      continue;
    }
    args.push(token);
  }

  const [command, maybeAction, ...rest] = args;
  if (!command) usage();

  const projectRoot = explicitProjectRoot ? path.resolve(explicitProjectRoot) : resolveProjectRoot();

  try {
    let result: CommandResult;

    switch (command) {
      case 'doctor':
        result = commandDoctor(projectRoot, jsonMode);
        break;
      case 'skills':
        result = commandSkills(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'workflow':
        result = commandWorkflow(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'run':
        result = commandRun(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'context':
        result = commandContext(projectRoot, maybeAction, jsonMode);
        break;
      case 'validate':
        result = commandValidate(projectRoot, maybeAction, jsonMode);
        break;
      case 'obsidian':
        result = commandObsidian(projectRoot, maybeAction, jsonMode);
        break;
      case 'portable':
        result = commandPortable(projectRoot, maybeAction, rest, jsonMode);
        break;
      default:
        usage();
    }

    if (jsonMode) {
      console.log(
        JSON.stringify(
          {
            ok: result.code === 0,
            command,
            action: maybeAction || null,
            data: result.payload ?? null
          },
          null,
          2
        )
      );
    }

    process.exit(result.code);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (jsonMode) {
      console.log(
        JSON.stringify(
          {
            ok: false,
            command,
            action: maybeAction || null,
            error: message
          },
          null,
          2
        )
      );
    } else {
      console.error(`ERROR: ${message}`);
    }

    process.exit(1);
  }
}

main();
