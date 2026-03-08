#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { getRuntimeProjectState } from './runtime-project-sync.mjs';

const repoRoot = process.cwd();
const args = new Set(process.argv.slice(2));
const wantsJson = args.has('--json');
const strict = !args.has('--allow-warn');

function readText(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function parseVersion(input) {
  return input
    .split('.')
    .map((part) => Number.parseInt(part, 10))
    .map((value) => (Number.isFinite(value) ? value : 0));
}

function compareVersions(a, b) {
  const left = parseVersion(a);
  const right = parseVersion(b);
  const length = Math.max(left.length, right.length);

  for (let index = 0; index < length; index += 1) {
    const l = left[index] || 0;
    const r = right[index] || 0;
    if (l > r) return -1;
    if (l < r) return 1;
  }

  return 0;
}

function findClaudeMemPluginRoot() {
  const cacheRoot = path.join(os.homedir(), '.claude', 'plugins', 'cache', 'thedotmack', 'claude-mem');
  if (!exists(cacheRoot)) return null;

  const versions = fs
    .readdirSync(cacheRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort(compareVersions);

  if (!versions.length) return null;
  return path.join(cacheRoot, versions[0]);
}

function getExpectedClaudeMemCommand() {
  const pluginRoot = findClaudeMemPluginRoot();
  if (!pluginRoot) return null;
  return {
    pluginRoot,
    scriptPath: path.join(pluginRoot, 'scripts', 'mcp-server.cjs')
  };
}

function runProjectContextCheck() {
  const result = spawnSync(process.execPath, ['scripts/generate-project-context.mjs', '--check'], {
    cwd: repoRoot,
    encoding: 'utf8'
  });

  return {
    ok: result.status === 0,
    detail: (result.stdout || result.stderr || '').trim()
  };
}

function loadJson(filePath) {
  return JSON.parse(readText(filePath));
}

function loadCodexToml() {
  const filePath = path.join(os.homedir(), '.codex', 'config.toml');
  if (!exists(filePath)) return null;
  return readText(filePath);
}

function checkCodexJsonConfig(expected) {
  const filePath = path.join(os.homedir(), '.codex', 'mcp.json');
  if (!exists(filePath)) {
    return {
      status: 'fail',
      id: 'codex_mcp_json',
      summary: 'Codex JSON MCP config missing',
      detail: filePath
    };
  }

  const config = loadJson(filePath);
  const server = config?.mcpServers?.['claude-mem'];
  if (!server) {
    return {
      status: 'fail',
      id: 'codex_mcp_json',
      summary: 'Codex JSON MCP config has no claude-mem server',
      detail: filePath
    };
  }

  const argsList = Array.isArray(server.args) ? server.args : [];
  const hasExpectedPath = expected ? argsList.includes(expected.scriptPath) : false;
  return {
    status: hasExpectedPath ? 'pass' : 'warn',
    id: 'codex_mcp_json',
    summary: hasExpectedPath
      ? 'Codex JSON MCP config includes claude-mem'
      : 'Codex JSON MCP config includes claude-mem but not the expected script path',
    detail: filePath
  };
}

function checkCodexTomlConfig(expected) {
  const filePath = path.join(os.homedir(), '.codex', 'config.toml');
  const content = loadCodexToml();
  if (!content) {
    return {
      status: 'fail',
      id: 'codex_mcp_toml',
      summary: 'Codex TOML MCP config missing',
      detail: filePath
    };
  }

  const hasSection = /\[mcp_servers\.claude-mem\]/.test(content);
  const hasExpectedPath = expected
    ? content.includes(expected.scriptPath)
    : false;

  if (!hasSection) {
    return {
      status: 'fail',
      id: 'codex_mcp_toml',
      summary: 'Codex TOML MCP config has no claude-mem section',
      detail: filePath
    };
  }

  return {
    status: hasExpectedPath ? 'pass' : 'warn',
    id: 'codex_mcp_toml',
    summary: hasExpectedPath
      ? 'Codex TOML MCP config includes claude-mem'
      : 'Codex TOML MCP config includes claude-mem but not the expected script path',
    detail: filePath
  };
}

function checkRuntimeProjectScopedConfig(runtime) {
  const state = getRuntimeProjectState(repoRoot, runtime);
  const checks = Object.fromEntries(state.checks.map((check) => [check.id, check]));
  const remediation = `Run: node scripts/runtime-project-sync.mjs activate ${repoRoot} --runtime ${runtime}`;

  if (runtime !== 'codex') {
    return [
      {
        status: state.active ? 'pass' : 'warn',
        id: `runtime_activation_${runtime}`,
        summary: state.active
          ? `${runtime} runtime contract is active for this repo`
          : `${runtime} runtime contract is not fully active for this repo`,
        detail: remediation
      }
    ];
  }

  return [
    {
      status: checks.gg_skills_toml?.ok && checks.gg_skills_json?.ok ? 'pass' : 'warn',
      id: 'runtime_activation_codex_gg_skills',
      summary: checks.gg_skills_toml?.ok && checks.gg_skills_json?.ok
        ? 'Codex gg-skills paths point at this repo'
        : 'Codex gg-skills paths are not activated for this repo',
      detail: remediation
    },
    {
      status: checks.filesystem_toml?.ok && checks.filesystem_json?.ok ? 'pass' : 'warn',
      id: 'runtime_activation_codex_filesystem',
      summary: checks.filesystem_toml?.ok && checks.filesystem_json?.ok
        ? 'Codex filesystem scope points at this repo'
        : 'Codex filesystem scope is not activated for this repo',
      detail: remediation
    },
    {
      status: checks.project_trusted?.ok ? 'pass' : 'warn',
      id: 'runtime_activation_codex_project_trust',
      summary: checks.project_trusted?.ok
        ? 'Codex project trust is configured for this repo'
        : 'Codex project trust is not configured for this repo',
      detail: remediation
    }
  ];
}

async function checkWorkerHealth() {
  const candidates = ['http://127.0.0.1:37777/health', 'http://127.0.0.1:37777/api/health'];
  const failures = [];

  for (const url of candidates) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        return {
          status: 'pass',
          id: 'claude_mem_worker',
          summary: 'claude-mem worker is reachable',
          detail: url
        };
      }
      failures.push(`${url} -> HTTP ${response.status}`);
    } catch (error) {
      failures.push(`${url} -> ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  return {
    status: 'fail',
    id: 'claude_mem_worker',
    summary: 'claude-mem worker is not reachable',
    detail: failures.join(' | ')
  };
}

function checkPromptParity() {
  const claude = path.join(repoRoot, 'CLAUDE.md');
  const agents = path.join(repoRoot, 'AGENTS.md');
  const gemini = path.join(repoRoot, 'GEMINI.md');

  const checks = [];
  if (!exists(claude) || !exists(agents) || !exists(gemini)) {
    return {
      status: 'fail',
      id: 'prompt_mirror',
      summary: 'One or more prompt files are missing',
      detail: `${claude}, ${agents}, ${gemini}`
    };
  }

  const base = readText(claude);
  checks.push(base === readText(agents));
  checks.push(base === readText(gemini));

  return {
    status: checks.every(Boolean) ? 'pass' : 'fail',
    id: 'prompt_mirror',
    summary: checks.every(Boolean)
      ? 'Prompt mirrors are aligned'
      : 'Prompt mirrors are out of sync',
    detail: 'CLAUDE.md, AGENTS.md, GEMINI.md'
  };
}

function checkRuntimeRegistry() {
  const filePath = path.join(repoRoot, '.agent', 'registry', 'mcp-runtime.json');
  if (!exists(filePath)) {
    return {
      status: 'fail',
      id: 'runtime_registry',
      summary: 'Runtime registry missing',
      detail: filePath
    };
  }

  const registry = loadJson(filePath);
  const required = ['codex', 'claude', 'kimi'];
  const missing = required.filter((profile) => {
    const optional = registry?.profiles?.[profile]?.optional || [];
    return !optional.includes('claude-mem');
  });

  return {
    status: missing.length ? 'fail' : 'pass',
    id: 'runtime_registry',
    summary: missing.length
      ? `Runtime registry missing claude-mem optional on: ${missing.join(', ')}`
      : 'Runtime registry exposes claude-mem parity for codex/claude/kimi',
    detail: filePath
  };
}

function checkClaudePlugin(expected) {
  const settingsPath = path.join(os.homedir(), '.claude', 'settings.json');
  if (!expected) {
    return {
      status: 'fail',
      id: 'claude_plugin',
      summary: 'claude-mem plugin cache not found',
      detail: settingsPath
    };
  }

  const hasSettings = exists(settingsPath);
  const hasScript = exists(expected.scriptPath);
  const hasMcpConfig = exists(path.join(expected.pluginRoot, '.mcp.json'));

  return {
    status: hasSettings && hasScript && hasMcpConfig ? 'pass' : 'fail',
    id: 'claude_plugin',
    summary: hasSettings && hasScript && hasMcpConfig
      ? 'Claude plugin cache for claude-mem is present'
      : 'Claude plugin cache for claude-mem is incomplete',
    detail: expected.pluginRoot
  };
}

function checkProjectContext() {
  const result = runProjectContextCheck();
  return {
    status: result.ok ? 'pass' : 'fail',
    id: 'project_context',
    summary: result.ok ? 'Project context is current' : 'Project context is stale',
    detail: result.detail
  };
}

function checkKimiContract(expected) {
  return {
    status: expected ? 'pass' : 'warn',
    id: 'kimi_contract',
    summary: expected
      ? 'Kimi can use the same claude-mem worker/server contract through the active runtime'
      : 'Kimi contract is fallback-only because claude-mem server path is unavailable',
    detail: 'Kimi currently relies on runtime contract + worker path, not a dedicated local client config'
  };
}

async function main() {
  const expected = getExpectedClaudeMemCommand();
  const results = [
    checkPromptParity(),
    checkRuntimeRegistry(),
    checkProjectContext(),
    checkClaudePlugin(expected),
    checkCodexJsonConfig(expected),
    checkCodexTomlConfig(expected),
    ...checkRuntimeProjectScopedConfig('codex'),
    ...checkRuntimeProjectScopedConfig('claude'),
    ...checkRuntimeProjectScopedConfig('kimi'),
    checkKimiContract(expected),
    await checkWorkerHealth()
  ];

  const hasFail = results.some((result) => result.status === 'fail');
  const hasWarn = results.some((result) => result.status === 'warn');
  const ok = !hasFail && (!strict || !hasWarn);

  const summary = {
    ok,
    strict,
    results
  };

  if (wantsJson) {
    process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  } else {
    console.log(`runtime-parity-smoke: ${ok ? 'PASS' : 'FAIL'}`);
    for (const result of results) {
      console.log(`- [${result.status}] ${result.id}: ${result.summary}`);
    }
  }

  process.exit(ok ? 0 : 1);
}

main().catch((error) => {
  console.error(`runtime-parity-smoke crashed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
