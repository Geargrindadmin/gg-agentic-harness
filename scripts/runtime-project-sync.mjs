#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_CODEX_HOME = path.join(os.homedir(), '.codex');
const SUPPORTED_RUNTIMES = ['codex', 'claude', 'kimi'];
const DEFAULT_FILESYSTEM_ALWAYS_ALLOW = [
  'read_file',
  'read_text_file',
  'read_media_file',
  'read_multiple_files',
  'write_file',
  'edit_file',
  'create_directory',
  'list_directory',
  'list_directory_with_sizes',
  'directory_tree',
  'move_file',
  'search_files',
  'get_file_info',
  'list_allowed_directories'
];

function exists(filePath) {
  return fs.existsSync(filePath);
}

function ensureArray(value) {
  return Array.isArray(value) ? value : [];
}

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function readJson(filePath, fallback) {
  if (!exists(filePath)) return fallback;
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function backupFile(filePath) {
  if (!exists(filePath)) return null;
  const backupPath = `${filePath}.bak.${timestamp()}`;
  fs.copyFileSync(filePath, backupPath);
  return backupPath;
}

function normalizeToml(content) {
  if (!content) return '';
  return content.endsWith('\n') ? content : `${content}\n`;
}

function upsertTomlSection(content, header, bodyLines) {
  const lines = normalizeToml(content).split('\n');
  const sectionHeader = `[${header}]`;
  const start = lines.findIndex((line) => line.trim() === sectionHeader);

  if (start >= 0) {
    let end = lines.length;
    for (let index = start + 1; index < lines.length; index += 1) {
      const trimmed = lines[index].trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        end = index;
        break;
      }
    }
    lines.splice(start, end - start, sectionHeader, ...bodyLines, '');
  } else {
    if (lines.length > 0 && lines[lines.length - 1] !== '') {
      lines.push('');
    }
    lines.push(sectionHeader, ...bodyLines, '');
  }

  return `${lines.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd()}\n`;
}

function normalizeRuntime(runtime) {
  const normalized = (runtime || 'codex').toLowerCase();
  if (!SUPPORTED_RUNTIMES.includes(normalized)) {
    throw new Error(`Unsupported runtime: ${runtime}. Expected one of: ${SUPPORTED_RUNTIMES.join(', ')}`);
  }
  return normalized;
}

function readRuntimeRegistry(targetRoot) {
  const registryPath = path.join(targetRoot, '.agent', 'registry', 'mcp-runtime.json');
  const registry = readJson(registryPath, null);
  return { registryPath, registry };
}

function buildRuntimeContractChecks(targetRoot, runtime) {
  const { registryPath, registry } = readRuntimeRegistry(targetRoot);
  const runtimeProfile = registry?.profiles?.[runtime];
  const hasProfile = Boolean(runtimeProfile);
  const optional = ensureArray(runtimeProfile?.optional);
  const hasMemParity = optional.includes('claude-mem');

  const checks = [
    {
      id: 'runtime_registry_exists',
      ok: Boolean(registry),
      detail: registryPath
    },
    {
      id: 'runtime_profile_exists',
      ok: hasProfile,
      detail: `${runtime} profile`
    },
    {
      id: 'runtime_mem_parity',
      ok: hasMemParity,
      detail: `${runtime} optional includes claude-mem`
    }
  ];

  return {
    checks,
    active: checks.every((check) => check.ok)
  };
}

function getCodexExpectedPaths(targetRoot, codexHome = DEFAULT_CODEX_HOME) {
  return {
    codexHome,
    configTomlPath: path.join(codexHome, 'config.toml'),
    mcpJsonPath: path.join(codexHome, 'mcp.json'),
    ggSkillsScript: path.join(targetRoot, 'mcp-servers', 'gg-skills', 'dist', 'index.js'),
    skillsDir: path.join(targetRoot, '.agent', 'skills'),
    workflowsDir: path.join(targetRoot, '.agent', 'workflows'),
    filesystemRoot: targetRoot
  };
}

function validateCodexTargetRoot(targetRoot, codexHome) {
  const expected = getCodexExpectedPaths(targetRoot, codexHome);
  const required = [
    expected.ggSkillsScript,
    expected.skillsDir,
    expected.workflowsDir,
    path.join(targetRoot, '.mcp.json')
  ];
  const missing = required.filter((filePath) => !exists(filePath));
  if (missing.length > 0) {
    throw new Error(`Target repo is missing required harness files: ${missing.join(', ')}`);
  }
  return expected;
}

function configureCodexToml(content, targetRoot, expected) {
  let next = normalizeToml(content);
  next = upsertTomlSection(next, `projects.${JSON.stringify(targetRoot)}`, ['trust_level = "trusted"']);
  next = upsertTomlSection(next, 'mcp_servers.gg-skills', [
    'command = "node"',
    `args = [${JSON.stringify(expected.ggSkillsScript)}]`
  ]);
  next = upsertTomlSection(next, 'mcp_servers.gg-skills.env', [
    `SKILLS_DIR = ${JSON.stringify(expected.skillsDir)}`,
    `WORKFLOWS_DIR = ${JSON.stringify(expected.workflowsDir)}`
  ]);
  next = upsertTomlSection(next, 'mcp_servers.filesystem', [
    'command = "npx"',
    `args = ["-y", "@modelcontextprotocol/server-filesystem", ${JSON.stringify(expected.filesystemRoot)}]`
  ]);
  return next;
}

function configureCodexMcpJson(current, expected) {
  const next = current && typeof current === 'object' ? { ...current } : {};
  next.mcpServers = next.mcpServers && typeof next.mcpServers === 'object' ? { ...next.mcpServers } : {};

  const existingFilesystem = next.mcpServers.filesystem && typeof next.mcpServers.filesystem === 'object'
    ? next.mcpServers.filesystem
    : {};

  next.mcpServers['gg-skills'] = {
    command: 'node',
    args: [expected.ggSkillsScript],
    env: {
      SKILLS_DIR: expected.skillsDir,
      WORKFLOWS_DIR: expected.workflowsDir
    }
  };

  next.mcpServers.filesystem = {
    ...existingFilesystem,
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-filesystem', expected.filesystemRoot],
    alwaysAllow: ensureArray(existingFilesystem.alwaysAllow).length > 0
      ? ensureArray(existingFilesystem.alwaysAllow)
      : DEFAULT_FILESYSTEM_ALWAYS_ALLOW
  };

  return next;
}

function buildCodexChecks(targetRoot, codexHome) {
  const expected = getCodexExpectedPaths(targetRoot, codexHome);
  const configTomlPath = expected.configTomlPath;
  const mcpJsonPath = expected.mcpJsonPath;
  const toml = exists(configTomlPath) ? fs.readFileSync(configTomlPath, 'utf8') : '';
  const mcpJson = readJson(mcpJsonPath, null);
  const ggSkillsJson = mcpJson?.mcpServers?.['gg-skills'];
  const filesystemJson = mcpJson?.mcpServers?.filesystem;

  const hostChecks = [
    {
      id: 'config_toml_exists',
      ok: Boolean(toml),
      detail: configTomlPath
    },
    {
      id: 'mcp_json_exists',
      ok: Boolean(mcpJson),
      detail: mcpJsonPath
    },
    {
      id: 'project_trusted',
      ok: toml.includes(`[projects.${JSON.stringify(targetRoot)}]`) && toml.includes('trust_level = "trusted"'),
      detail: targetRoot
    },
    {
      id: 'gg_skills_toml',
      ok:
        toml.includes('[mcp_servers.gg-skills]') &&
        toml.includes(expected.ggSkillsScript) &&
        toml.includes(`SKILLS_DIR = ${JSON.stringify(expected.skillsDir)}`) &&
        toml.includes(`WORKFLOWS_DIR = ${JSON.stringify(expected.workflowsDir)}`),
      detail: configTomlPath
    },
    {
      id: 'filesystem_toml',
      ok:
        toml.includes('[mcp_servers.filesystem]') &&
        toml.includes('@modelcontextprotocol/server-filesystem') &&
        toml.includes(JSON.stringify(expected.filesystemRoot)),
      detail: configTomlPath
    },
    {
      id: 'gg_skills_json',
      ok:
        ggSkillsJson?.command === 'node' &&
        ensureArray(ggSkillsJson?.args).includes(expected.ggSkillsScript) &&
        ggSkillsJson?.env?.SKILLS_DIR === expected.skillsDir &&
        ggSkillsJson?.env?.WORKFLOWS_DIR === expected.workflowsDir,
      detail: mcpJsonPath
    },
    {
      id: 'filesystem_json',
      ok:
        filesystemJson?.command === 'npx' &&
        ensureArray(filesystemJson?.args).includes(expected.filesystemRoot),
      detail: mcpJsonPath
    }
  ];

  const runtimeContract = buildRuntimeContractChecks(targetRoot, 'codex');
  const checks = [...hostChecks, ...runtimeContract.checks];

  return {
    targetRoot,
    runtime: 'codex',
    codexHome,
    expected,
    checks,
    activationType: 'host-config',
    active: checks.every((check) => check.ok)
  };
}

function getCodexProjectState(targetRoot, codexHome = DEFAULT_CODEX_HOME) {
  return buildCodexChecks(path.resolve(targetRoot), path.resolve(codexHome));
}

function activateCodexProject(targetRoot, codexHome = DEFAULT_CODEX_HOME) {
  const resolvedRoot = path.resolve(targetRoot);
  const resolvedCodexHome = path.resolve(codexHome);
  const expected = validateCodexTargetRoot(resolvedRoot, resolvedCodexHome);
  fs.mkdirSync(resolvedCodexHome, { recursive: true });

  const configTomlPath = path.join(resolvedCodexHome, 'config.toml');
  const mcpJsonPath = path.join(resolvedCodexHome, 'mcp.json');

  const configTomlBackup = backupFile(configTomlPath);
  const mcpJsonBackup = backupFile(mcpJsonPath);

  const nextToml = configureCodexToml(exists(configTomlPath) ? fs.readFileSync(configTomlPath, 'utf8') : '', resolvedRoot, expected);
  fs.writeFileSync(configTomlPath, nextToml, 'utf8');

  const nextMcpJson = configureCodexMcpJson(readJson(mcpJsonPath, {}), expected);
  fs.writeFileSync(mcpJsonPath, `${JSON.stringify(nextMcpJson, null, 2)}\n`, 'utf8');

  return {
    ...getCodexProjectState(resolvedRoot, resolvedCodexHome),
    backups: {
      configToml: configTomlBackup,
      mcpJson: mcpJsonBackup
    },
    restartRequired: true
  };
}

function getContractRuntimeState(targetRoot, runtime) {
  const resolvedRoot = path.resolve(targetRoot);
  const runtimeContract = buildRuntimeContractChecks(resolvedRoot, runtime);
  return {
    targetRoot: resolvedRoot,
    runtime,
    activationType: 'contract-only',
    checks: runtimeContract.checks,
    active: runtimeContract.active,
    restartRequired: false
  };
}

function activateContractRuntime(targetRoot, runtime) {
  return {
    ...getContractRuntimeState(targetRoot, runtime),
    message: `${runtime} does not require host-level project activation in this harness`
  };
}

export function getRuntimeProjectState(targetRoot, runtime = 'codex', options = {}) {
  const normalizedRuntime = normalizeRuntime(runtime);
  if (normalizedRuntime === 'codex') {
    return getCodexProjectState(targetRoot, options.codexHome || DEFAULT_CODEX_HOME);
  }
  return getContractRuntimeState(targetRoot, normalizedRuntime);
}

export function activateRuntimeProject(targetRoot, runtime = 'codex', options = {}) {
  const normalizedRuntime = normalizeRuntime(runtime);
  if (normalizedRuntime === 'codex') {
    return activateCodexProject(targetRoot, options.codexHome || DEFAULT_CODEX_HOME);
  }
  return activateContractRuntime(targetRoot, normalizedRuntime);
}

function parseArgs(argv) {
  const parsed = {
    action: argv[0] || '',
    targetRoot: process.cwd(),
    runtime: 'codex',
    codexHome: DEFAULT_CODEX_HOME,
    json: false
  };

  for (let index = 1; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--json') parsed.json = true;
    else if (token === '--runtime') parsed.runtime = argv[++index] ?? parsed.runtime;
    else if (token === '--codex-home') parsed.codexHome = argv[++index] ?? parsed.codexHome;
    else if (!token.startsWith('--')) parsed.targetRoot = token;
  }

  return parsed;
}

function printState(result, action) {
  console.log(`Runtime ${action}: ${result.runtime} @ ${result.targetRoot}`);
  console.log(`Activation type: ${result.activationType}`);
  console.log(`Active: ${result.active ? 'yes' : 'no'}`);
  for (const check of result.checks) {
    console.log(`[${check.ok ? 'pass' : 'fail'}] ${check.id}: ${check.detail}`);
  }
  if (result.message) {
    console.log(result.message);
  }
  if (action === 'activate') {
    console.log(`Restart required: ${result.restartRequired ? 'yes' : 'no'}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!['activate', 'status'].includes(args.action)) {
    console.error('Usage: node scripts/runtime-project-sync.mjs <activate|status> [targetRoot] [--runtime <codex|claude|kimi>] [--codex-home <path>] [--json]');
    process.exit(2);
  }

  const result = args.action === 'activate'
    ? activateRuntimeProject(args.targetRoot, args.runtime, { codexHome: args.codexHome })
    : getRuntimeProjectState(args.targetRoot, args.runtime, { codexHome: args.codexHome });

  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printState(result, args.action);
  }
}

function isDirectExecution() {
  if (!process.argv[1]) return false;

  const modulePath = fs.realpathSync(fileURLToPath(import.meta.url));
  const entryPath = fs.realpathSync(path.resolve(process.argv[1]));
  return modulePath === entryPath;
}

if (isDirectExecution()) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
