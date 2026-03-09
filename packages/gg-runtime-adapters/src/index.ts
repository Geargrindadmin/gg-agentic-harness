import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

export type RuntimeId = 'codex' | 'claude' | 'kimi';
export type AdapterMode = 'host-activated' | 'contract-only' | 'provider-api';
export type LaunchTransport = 'contract-only' | 'background-terminal' | 'api-session' | 'cli-session';
export type PreflightCheckStatus = 'pass' | 'warn' | 'fail';

interface RuntimeRegistryFile {
  profiles?: Partial<Record<RuntimeId, RuntimeRegistryProfile>>;
}

interface RuntimeRegistryProfile {
  description?: string;
  mcpServers?: string[];
  disabled?: string[];
  optional?: string[];
  execution?: RuntimeExecutionProfile;
}

interface RuntimeExecutionProfile {
  adapterMode?: AdapterMode;
  defaultLaunchTransport?: LaunchTransport;
  provider?: string;
  apiBaseUrl?: string;
  chatCompletionsPath?: string;
  apiKeyEnv?: string[];
  model?: string;
  preflight?: RuntimePreflightConfig;
}

interface RuntimePreflightConfig {
  minCpuCores?: number;
  minTotalMemoryGb?: number;
  minFreeMemoryGb?: number;
}

export interface RuntimeLaunchEnvelope {
  runId: string;
  agentId: string;
  runtime: RuntimeId;
  taskSummary: string;
  worktree: string;
  toolBundle: string[];
  launchTransport: LaunchTransport;
  launchSpec: Record<string, unknown>;
}

export interface RuntimePreflightCheck {
  id: string;
  status: PreflightCheckStatus;
  detail: string;
}

export interface RuntimePreflightReport {
  status: 'passed' | 'failed';
  summary: string;
  checks: RuntimePreflightCheck[];
  host: {
    platform: NodeJS.Platform;
    arch: string;
    cpuCores: number;
    totalMemoryGb: number;
    freeMemoryGb: number;
    nodeVersion: string;
  };
}

export interface RuntimeExecutionResult {
  executionId: string;
  status: 'completed' | 'failed';
  dryRun: boolean;
  adapterMode: AdapterMode;
  launchTransport: LaunchTransport;
  summary: string;
  outputText: string;
  requestFile: string | null;
  responseFile: string | null;
  transcriptFile: string | null;
  error: string | null;
  responseStatus: number | null;
  startedAt: string;
  completedAt: string;
}

export interface RuntimeInteractiveLaunchPlan {
  executionId: string;
  adapterMode: AdapterMode;
  launchTransport: LaunchTransport;
  binary: string;
  args: string[];
  cwd: string;
  env: NodeJS.ProcessEnv;
  requestFile: string;
  responseFile: string;
  transcriptFile: string;
  summary: string;
}

export interface RuntimeCredentialSource {
  id: string;
  type: 'file' | 'env';
  location: string;
  status: 'present' | 'missing';
  detail: string;
}

export interface RuntimeCredentialDiscovery {
  runtime: RuntimeId;
  binaryPath: string | null;
  authenticated: boolean;
  localCliAuth: boolean;
  directApiAvailable: boolean;
  preferredTransport: LaunchTransport | null;
  summary: string;
  sources: RuntimeCredentialSource[];
}

export interface CoordinatorRuntimeSelection {
  requested: 'auto' | RuntimeId;
  selected: RuntimeId;
  reason: string;
  order: RuntimeId[];
  discoveries: RuntimeCredentialDiscovery[];
}

function nowIso(): string {
  return new Date().toISOString();
}

function readJson<T>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
}

function writeJson(filePath: string, value: unknown): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function loadRuntimeProfile(projectRoot: string, runtime: RuntimeId): RuntimeRegistryProfile {
  const registry =
    readJson<RuntimeRegistryFile>(path.join(projectRoot, '.agent', 'registry', 'mcp-runtime.json')) || {};
  return registry.profiles?.[runtime] || {};
}

function normalizeExecutionProfile(projectRoot: string, runtime: RuntimeId): Required<RuntimeExecutionProfile> {
  const profile = loadRuntimeProfile(projectRoot, runtime).execution || {};
  const defaults: Record<RuntimeId, Required<RuntimeExecutionProfile>> = {
    codex: {
      adapterMode: 'host-activated',
      defaultLaunchTransport: 'background-terminal',
      provider: 'local',
      apiBaseUrl: '',
      chatCompletionsPath: '/chat/completions',
      apiKeyEnv: [],
      model: 'codex',
      preflight: {}
    },
    claude: {
      adapterMode: 'contract-only',
      defaultLaunchTransport: 'contract-only',
      provider: 'contract',
      apiBaseUrl: '',
      chatCompletionsPath: '/chat/completions',
      apiKeyEnv: [],
      model: 'claude',
      preflight: {}
    },
    kimi: {
      adapterMode: 'provider-api',
      defaultLaunchTransport: 'api-session',
      provider: 'moonshot',
      apiBaseUrl: 'https://api.moonshot.ai/v1',
      chatCompletionsPath: '/chat/completions',
      apiKeyEnv: ['MOONSHOT_API_KEY', 'KIMI_API_KEY'],
      model: 'kimi-k2.5',
      preflight: {
        minCpuCores: 4,
        minTotalMemoryGb: 8
      }
    }
  };

  return {
    ...defaults[runtime],
    ...profile,
    apiKeyEnv: profile.apiKeyEnv && profile.apiKeyEnv.length ? [...profile.apiKeyEnv] : [...defaults[runtime].apiKeyEnv],
    preflight: {
      ...defaults[runtime].preflight,
      ...(profile.preflight || {})
    }
  };
}

function roundMemoryGb(bytes: number): number {
  return Math.round((bytes / 1024 / 1024 / 1024) * 10) / 10;
}

function buildHostSnapshot(): RuntimePreflightReport['host'] {
  return {
    platform: process.platform,
    arch: process.arch,
    cpuCores: os.cpus().length,
    totalMemoryGb: roundMemoryGb(os.totalmem()),
    freeMemoryGb: roundMemoryGb(os.freemem()),
    nodeVersion: process.version
  };
}

function envString(name: string): string | null {
  const value = process.env[name];
  return value && value.trim() ? value.trim() : null;
}

function resolveExecutable(command: string, envVar?: string): string | null {
  const envPath = envVar ? envString(envVar) : null;
  if (envPath) {
    return envPath;
  }

  const which = spawnSync('which', [command], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore']
  });

  if (which.status === 0 && which.stdout.trim()) {
    return which.stdout.trim();
  }

  return null;
}

function resolveKimiBinary(): string | null {
  return resolveExecutable('kimi', 'KIMI_BINARY');
}

function resolveClaudeBinary(): string | null {
  return resolveExecutable('claude', 'CLAUDE_BINARY');
}

function resolveCodexBinary(): string | null {
  return resolveExecutable('codex', 'CODEX_BINARY');
}

function resolveKimiCredentialsFile(): string {
  return envString('KIMI_CREDENTIALS_FILE') || path.join(os.homedir(), '.kimi', 'credentials', 'kimi-code.json');
}

function resolveKimiConfigFile(): string {
  return envString('KIMI_CONFIG_FILE') || path.join(os.homedir(), '.kimi', 'config.toml');
}

function resolveClaudeCredentialsFile(): string {
  return envString('CLAUDE_CREDENTIALS_FILE') || path.join(os.homedir(), '.claude', '.credentials.json');
}

function resolveOpenCodeAuthFile(): string {
  return envString('OPENCODE_AUTH_FILE') || path.join(os.homedir(), '.local', 'share', 'opencode', 'auth.json');
}

function resolveCodexAuthFile(): string {
  return envString('CODEX_AUTH_FILE') || path.join(os.homedir(), '.codex', 'auth.json');
}

function fileExists(filePath: string): boolean {
  try {
    return fs.existsSync(filePath);
  } catch {
    return false;
  }
}

function hasNonEmptyEnv(name: string): boolean {
  const value = process.env[name];
  return Boolean(value && value.trim());
}

function codexAuthFileHasCredentials(filePath: string): boolean {
  const parsed = readJson<Record<string, unknown>>(filePath);
  if (!parsed || typeof parsed !== 'object') {
    return false;
  }

  const tokens = parsed.tokens;
  if (tokens && typeof tokens === 'object') {
    const accessToken = (tokens as { access_token?: unknown }).access_token;
    if (typeof accessToken === 'string' && accessToken.trim()) {
      return true;
    }
  }

  const envApiKey = parsed.OPENAI_API_KEY;
  if (typeof envApiKey === 'string' && envApiKey.trim()) {
    return true;
  }

  const apiKey = parsed.api_key;
  return typeof apiKey === 'string' && apiKey.trim().length > 0;
}

function genericJsonAuthFileExists(filePath: string): boolean {
  if (!fileExists(filePath)) {
    return false;
  }

  try {
    const content = fs.readFileSync(filePath, 'utf8').trim();
    return content.length > 0;
  } catch {
    return false;
  }
}

function sourceFromFile(id: string, filePath: string, present: boolean, detail: string): RuntimeCredentialSource {
  return {
    id,
    type: 'file',
    location: filePath,
    status: present ? 'present' : 'missing',
    detail
  };
}

function sourceFromEnv(id: string, envName: string, present: boolean, detail: string): RuntimeCredentialSource {
  return {
    id,
    type: 'env',
    location: envName,
    status: present ? 'present' : 'missing',
    detail
  };
}

function normalizeRuntimePreference(value?: string | null): RuntimeId | null {
  const normalized = String(value || '')
    .trim()
    .toLowerCase();
  if (normalized === 'codex' || normalized === 'claude' || normalized === 'kimi') {
    return normalized;
  }
  return null;
}

export function discoverRuntimeCredentials(_projectRoot: string, runtime: RuntimeId): RuntimeCredentialDiscovery {
  if (runtime === 'kimi') {
    const binaryPath = resolveKimiBinary();
    const credentialsFile = resolveKimiCredentialsFile();
    const configFile = resolveKimiConfigFile();
    const credentialsPresent = genericJsonAuthFileExists(credentialsFile);
    const configPresent = genericJsonAuthFileExists(configFile);
    const apiKey = firstDefinedEnv(['MOONSHOT_API_KEY', 'KIMI_API_KEY']);
    const localCliAuth = Boolean(binaryPath) && (credentialsPresent || configPresent);
    const directApiAvailable = Boolean(apiKey);
    const preferredTransport = localCliAuth ? 'cli-session' : directApiAvailable ? 'api-session' : null;

    return {
      runtime,
      binaryPath,
      authenticated: localCliAuth || directApiAvailable,
      localCliAuth,
      directApiAvailable,
      preferredTransport,
      summary: localCliAuth
        ? `Using inherited Kimi CLI session from ${credentialsPresent ? credentialsFile : configFile}`
        : directApiAvailable
          ? `Using ${apiKey?.name} for direct Moonshot API access`
          : 'No Kimi CLI session or Moonshot API credentials were discovered',
      sources: [
        sourceFromFile('kimi_credentials', credentialsFile, credentialsPresent, 'Kimi CLI OAuth/session store'),
        sourceFromFile('kimi_config', configFile, configPresent, 'Kimi CLI config file'),
        sourceFromEnv('moonshot_api_key', apiKey?.name || 'MOONSHOT_API_KEY|KIMI_API_KEY', Boolean(apiKey), 'Moonshot direct API key')
      ]
    };
  }

  if (runtime === 'claude') {
    const binaryPath = resolveClaudeBinary();
    const credentialsFile = resolveClaudeCredentialsFile();
    const opencodeFile = resolveOpenCodeAuthFile();
    const claudeCredentialsPresent = genericJsonAuthFileExists(credentialsFile);
    const opencodeCredentialsPresent = genericJsonAuthFileExists(opencodeFile);
    const anthropicApiKeyPresent = hasNonEmptyEnv('ANTHROPIC_API_KEY');
    const localCliAuth = Boolean(binaryPath) && (claudeCredentialsPresent || opencodeCredentialsPresent || anthropicApiKeyPresent);
    const directApiAvailable = anthropicApiKeyPresent;

    return {
      runtime,
      binaryPath,
      authenticated: localCliAuth || directApiAvailable,
      localCliAuth,
      directApiAvailable,
      preferredTransport: localCliAuth ? 'background-terminal' : null,
      summary: localCliAuth
        ? claudeCredentialsPresent
          ? `Using inherited Claude CLI credentials from ${credentialsFile}`
          : opencodeCredentialsPresent
            ? `Using inherited OpenCode auth from ${opencodeFile} for Claude-compatible sessions`
            : 'Using ANTHROPIC_API_KEY with the local Claude CLI session'
        : directApiAvailable
          ? 'Direct Anthropic API credentials are available, but the harness currently uses the local Claude CLI for live workers'
          : 'No Claude CLI credentials or Anthropic API key were discovered',
      sources: [
        sourceFromFile('claude_credentials', credentialsFile, claudeCredentialsPresent, 'Claude Code local credentials'),
        sourceFromFile('opencode_auth', opencodeFile, opencodeCredentialsPresent, 'OpenCode auth store'),
        sourceFromEnv('anthropic_api_key', 'ANTHROPIC_API_KEY', anthropicApiKeyPresent, 'Anthropic API key')
      ]
    };
  }

  const binaryPath = resolveCodexBinary();
  const authFile = resolveCodexAuthFile();
  const authFilePresent = codexAuthFileHasCredentials(authFile);
  const openAiApiKeyPresent = hasNonEmptyEnv('OPENAI_API_KEY');
  const localCliAuth = Boolean(binaryPath) && (authFilePresent || openAiApiKeyPresent);
  const directApiAvailable = authFilePresent || openAiApiKeyPresent;
  return {
    runtime,
    binaryPath,
    authenticated: localCliAuth || directApiAvailable,
    localCliAuth,
    directApiAvailable,
    preferredTransport: localCliAuth ? 'background-terminal' : null,
    summary: localCliAuth
      ? authFilePresent
        ? `Using inherited Codex auth from ${authFile}`
        : 'Using OPENAI_API_KEY with the local Codex CLI session'
      : directApiAvailable
        ? 'OpenAI credentials are present, but the local Codex CLI binary is unavailable'
        : 'No Codex auth file or OpenAI API key were discovered',
    sources: [
      sourceFromFile('codex_auth', authFile, authFilePresent, 'Codex auth store'),
      sourceFromEnv('openai_api_key', 'OPENAI_API_KEY', openAiApiKeyPresent, 'OpenAI API key')
    ]
  };
}

function coordinatorPreferenceOrder(): RuntimeId[] {
  const configured = String(process.env.GG_COORDINATOR_PREFERENCE || '')
    .split(',')
    .map((entry) => normalizeRuntimePreference(entry))
    .filter((entry): entry is RuntimeId => Boolean(entry));

  const order: RuntimeId[] = configured.length ? configured : ['codex', 'claude', 'kimi'];
  return [...new Set(order)];
}

export function selectCoordinatorRuntime(projectRoot: string, requested?: string | null): CoordinatorRuntimeSelection {
  const pinned = normalizeRuntimePreference(requested);
  if (pinned) {
    const discovery = discoverRuntimeCredentials(projectRoot, pinned);
    return {
      requested: pinned,
      selected: pinned,
      reason: `Coordinator pinned to ${pinned} by operator request`,
      order: [pinned],
      discoveries: [discovery]
    };
  }

  const envPinned = normalizeRuntimePreference(process.env.GG_COORDINATOR_RUNTIME || null);
  if (envPinned) {
    const discovery = discoverRuntimeCredentials(projectRoot, envPinned);
    return {
      requested: 'auto',
      selected: envPinned,
      reason: `Coordinator auto-selection overridden by GG_COORDINATOR_RUNTIME=${envPinned}`,
      order: [envPinned],
      discoveries: [discovery]
    };
  }

  const order = coordinatorPreferenceOrder();
  const discoveries = order.map((runtime) => discoverRuntimeCredentials(projectRoot, runtime));
  const localCli = discoveries.find((entry) => entry.localCliAuth);
  if (localCli) {
    return {
      requested: 'auto',
      selected: localCli.runtime,
      reason: `Auto-selected ${localCli.runtime} because a local authenticated CLI session is available`,
      order,
      discoveries
    };
  }

  const authenticated = discoveries.find((entry) => entry.authenticated);
  if (authenticated) {
    return {
      requested: 'auto',
      selected: authenticated.runtime,
      reason: `Auto-selected ${authenticated.runtime} because authenticated provider credentials are available`,
      order,
      discoveries
    };
  }

  const installed = discoveries.find((entry) => entry.binaryPath);
  if (installed) {
    return {
      requested: 'auto',
      selected: installed.runtime,
      reason: `Auto-selected ${installed.runtime} because its CLI is installed locally`,
      order,
      discoveries
    };
  }

  return {
    requested: 'auto',
    selected: order[0] || 'codex',
    reason: 'Auto-selection fell back to the first runtime in GG_COORDINATOR_PREFERENCE because no authenticated runtime was discovered',
    order,
    discoveries
  };
}

function hasKimiCliAuth(): boolean {
  return discoverRuntimeCredentials('', 'kimi').localCliAuth;
}

function resolveKimiMcpConfig(projectRoot: string, worktree: string): string | null {
  const candidates = [path.join(worktree, '.mcp.kimi.json'), path.join(projectRoot, '.mcp.kimi.json')];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

function prepareKimiShareDir(projectRoot: string, envelope: RuntimeLaunchEnvelope, executionId: string): string {
  const shareDir = path.join(executionsDir(projectRoot, envelope.runId, envelope.agentId), `${executionId}.kimi-share`);
  const sourceConfig = resolveKimiConfigFile();
  const sourceCredentials = resolveKimiCredentialsFile();
  const sourceDeviceId = path.join(path.dirname(sourceConfig), 'device_id');
  const projectMcpConfig = resolveKimiMcpConfig(projectRoot, envelope.worktree);

  fs.mkdirSync(path.join(shareDir, 'credentials'), { recursive: true });
  fs.mkdirSync(path.join(shareDir, 'logs'), { recursive: true });
  fs.mkdirSync(path.join(shareDir, 'sessions'), { recursive: true });
  fs.mkdirSync(path.join(shareDir, 'user-history'), { recursive: true });

  if (fs.existsSync(sourceConfig)) {
    fs.copyFileSync(sourceConfig, path.join(shareDir, 'config.toml'));
  }

  if (fs.existsSync(sourceCredentials)) {
    fs.copyFileSync(sourceCredentials, path.join(shareDir, 'credentials', path.basename(sourceCredentials)));
  }

  if (fs.existsSync(sourceDeviceId)) {
    fs.copyFileSync(sourceDeviceId, path.join(shareDir, 'device_id'));
  }

  if (projectMcpConfig && fs.existsSync(projectMcpConfig)) {
    fs.copyFileSync(projectMcpConfig, path.join(shareDir, 'mcp.json'));
  } else {
    fs.writeFileSync(path.join(shareDir, 'mcp.json'), '{"mcpServers":{}}\n', 'utf8');
  }

  return shareDir;
}

export function resolveLaunchAdapterMode(projectRoot: string, runtime: RuntimeId, launchTransport: LaunchTransport): AdapterMode {
  if ((runtime === 'codex' || runtime === 'claude') && launchTransport === 'background-terminal') {
    return 'host-activated';
  }
  if (runtime === 'kimi') {
    if (launchTransport === 'cli-session') {
      return 'host-activated';
    }
    if (launchTransport === 'api-session') {
      return 'provider-api';
    }
  }
  return normalizeExecutionProfile(projectRoot, runtime).adapterMode;
}

function firstDefinedEnv(names: string[]): { name: string; value: string } | null {
  for (const name of names) {
    const value = process.env[name];
    if (value && value.trim()) {
      return { name, value };
    }
  }
  return null;
}

function executionsDir(projectRoot: string, runId: string, agentId: string): string {
  return path.join(projectRoot, '.agent', 'control-plane', 'executions', runId, agentId);
}

function nextExecutionId(): string {
  return `exec-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function buildRequestFilePath(projectRoot: string, runId: string, agentId: string, executionId: string): string {
  return path.join(executionsDir(projectRoot, runId, agentId), `${executionId}.request.json`);
}

function buildResponseFilePath(projectRoot: string, runId: string, agentId: string, executionId: string): string {
  return path.join(executionsDir(projectRoot, runId, agentId), `${executionId}.response.json`);
}

function buildTranscriptFilePath(projectRoot: string, runId: string, agentId: string, executionId: string): string {
  return path.join(executionsDir(projectRoot, runId, agentId), `${executionId}.transcript.md`);
}

export function defaultAdapterMode(projectRoot: string, runtime: RuntimeId): AdapterMode {
  return resolveLaunchAdapterMode(projectRoot, runtime, defaultLaunchTransport(projectRoot, runtime));
}

export function defaultLaunchTransport(projectRoot: string, runtime: RuntimeId): LaunchTransport {
  const configured = normalizeExecutionProfile(projectRoot, runtime).defaultLaunchTransport;
  if (runtime === 'claude') {
    const override = envString('GG_CLAUDE_TRANSPORT');
    if (override === 'background-terminal' || override === 'contract-only') {
      return override;
    }

    if (discoverRuntimeCredentials(projectRoot, 'claude').localCliAuth) {
      return 'background-terminal';
    }

    return configured;
  }

  if (runtime === 'codex') {
    const override = envString('GG_CODEX_TRANSPORT');
    if (override === 'background-terminal' || override === 'contract-only') {
      return override;
    }
    if (discoverRuntimeCredentials(projectRoot, 'codex').localCliAuth) {
      return 'background-terminal';
    }
    return configured;
  }

  if (runtime !== 'kimi') {
    return configured;
  }

  const override = envString('GG_KIMI_TRANSPORT');
  if (override === 'api-session' || override === 'cli-session') {
    return override;
  }

  if (hasKimiCliAuth()) {
    return 'cli-session';
  }

  return configured === 'cli-session' ? 'api-session' : configured;
}

export function evaluateRuntimeLaunchPreflight(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope
): RuntimePreflightReport {
  const executionProfile = normalizeExecutionProfile(projectRoot, envelope.runtime);
  const host = buildHostSnapshot();
  const checks: RuntimePreflightCheck[] = [];

  if (!fs.existsSync(envelope.worktree)) {
    checks.push({
      id: 'worktree_exists',
      status: 'fail',
      detail: `Worktree does not exist: ${envelope.worktree}`
    });
  } else {
    checks.push({
      id: 'worktree_exists',
      status: 'pass',
      detail: `Worktree exists: ${envelope.worktree}`
    });
  }

  if (envelope.runtime !== 'kimi') {
    if (envelope.launchTransport === 'background-terminal') {
      const credentials = discoverRuntimeCredentials(projectRoot, envelope.runtime);
      checks.push({
        id: 'launch_transport',
        status: 'pass',
        detail: `Runtime ${envelope.runtime} will use a background terminal session`
      });
      checks.push({
        id: `${envelope.runtime}_binary`,
        status: credentials.binaryPath ? 'pass' : 'fail',
        detail: credentials.binaryPath
          ? `Using ${envelope.runtime} CLI binary at ${credentials.binaryPath}`
          : `${envelope.runtime} CLI binary not found on PATH; install it or set ${
              envelope.runtime === 'codex' ? 'CODEX_BINARY' : 'CLAUDE_BINARY'
            }`
      });
      checks.push({
        id: `${envelope.runtime}_auth`,
        status: credentials.localCliAuth ? 'pass' : 'fail',
        detail: credentials.summary
      });
    } else {
      checks.push({
        id: 'runtime_execution',
        status: envelope.launchTransport === 'contract-only' ? 'pass' : 'fail',
        detail:
          envelope.launchTransport === 'contract-only'
            ? `Runtime ${envelope.runtime} remains contract-only in this harness slice`
            : `Runtime ${envelope.runtime} does not yet support launch transport ${envelope.launchTransport}`
      });
    }
    return {
      status: checks.some((entry) => entry.status === 'fail') ? 'failed' : 'passed',
      summary:
        checks.some((entry) => entry.status === 'fail')
          ? `Preflight failed for ${envelope.runtime}`
          : `Preflight passed for ${envelope.runtime}`,
      checks,
      host
    };
  }

  if (envelope.launchTransport === 'cli-session') {
    const credentials = discoverRuntimeCredentials(projectRoot, 'kimi');
    checks.push({
      id: 'launch_transport',
      status: 'pass',
      detail: 'Kimi runtime will use the local CLI session transport'
    });
    checks.push({
      id: 'kimi_binary',
      status: credentials.binaryPath ? 'pass' : 'fail',
      detail: credentials.binaryPath
        ? `Using Kimi CLI binary at ${credentials.binaryPath}`
        : 'Kimi CLI binary not found on PATH; install or set KIMI_BINARY'
    });
    checks.push({
      id: 'kimi_auth_store',
      status: credentials.localCliAuth ? 'pass' : 'fail',
      detail: credentials.summary
    });

    const mcpConfig = resolveKimiMcpConfig(projectRoot, envelope.worktree);
    checks.push({
      id: 'kimi_mcp_config',
      status: mcpConfig ? 'pass' : 'warn',
      detail: mcpConfig
        ? `Using Kimi MCP config ${mcpConfig}`
        : 'No .mcp.kimi.json found; Kimi worker will rely on native file/shell tools only'
    });
  } else if (envelope.launchTransport !== 'api-session') {
    checks.push({
      id: 'launch_transport',
      status: 'fail',
      detail: `Kimi adapter currently supports only api-session, received ${envelope.launchTransport}`
    });
  } else {
    checks.push({
      id: 'launch_transport',
      status: 'pass',
      detail: 'Kimi runtime will use the Moonshot API session adapter'
    });
  }

  if (envelope.launchTransport === 'api-session') {
    const credentials = firstDefinedEnv(executionProfile.apiKeyEnv);
    if (!credentials) {
      checks.push({
        id: 'api_key',
        status: 'fail',
        detail: `Set one of ${executionProfile.apiKeyEnv.join(', ')} before launching a Kimi worker`
      });
    } else {
      checks.push({
        id: 'api_key',
        status: 'pass',
        detail: `Using ${credentials.name} for Moonshot API authentication`
      });
    }
  }

  const minCpuCores = executionProfile.preflight.minCpuCores;
  if (typeof minCpuCores === 'number') {
    checks.push({
      id: 'cpu_cores',
      status: host.cpuCores >= minCpuCores ? 'pass' : 'fail',
      detail: `Detected ${host.cpuCores} CPU cores; required minimum is ${minCpuCores}`
    });
  }

  const minTotalMemoryGb = executionProfile.preflight.minTotalMemoryGb;
  if (typeof minTotalMemoryGb === 'number') {
    checks.push({
      id: 'total_memory',
      status: host.totalMemoryGb >= minTotalMemoryGb ? 'pass' : 'fail',
      detail: `Detected ${host.totalMemoryGb} GB RAM; required minimum is ${minTotalMemoryGb} GB`
    });
  }

  const minFreeMemoryGb = executionProfile.preflight.minFreeMemoryGb;
  if (typeof minFreeMemoryGb === 'number') {
    checks.push({
      id: 'free_memory',
      status: host.freeMemoryGb >= minFreeMemoryGb ? 'pass' : 'fail',
      detail: `Detected ${host.freeMemoryGb} GB free RAM; required minimum is ${minFreeMemoryGb} GB`
    });
  }

  const failures = checks.filter((entry) => entry.status === 'fail');
  return {
    status: failures.length ? 'failed' : 'passed',
    summary: failures.length
      ? `Preflight failed for ${envelope.runtime} worker ${envelope.agentId}`
      : `Preflight passed for ${envelope.runtime} worker ${envelope.agentId}`,
    checks,
    host
  };
}

function extractRoleContent(messages: unknown, role: 'system' | 'user'): string {
  if (!Array.isArray(messages)) {
    return '';
  }
  const entry = messages.find(
    (candidate) =>
      candidate &&
      typeof candidate === 'object' &&
      (candidate as { role?: unknown }).role === role &&
      'content' in (candidate as Record<string, unknown>)
  ) as { content?: unknown } | undefined;
  return normalizeAssistantContent(entry?.content);
}

function defaultKimiCliTools(toolBundle: string[]): string[] {
  const tools = [
    'kimi_cli.tools.todo:SetTodoList',
    'kimi_cli.tools.shell:Shell',
    'kimi_cli.tools.file:ReadFile',
    'kimi_cli.tools.file:ReadMediaFile',
    'kimi_cli.tools.file:Glob',
    'kimi_cli.tools.file:Grep',
    'kimi_cli.tools.file:WriteFile',
    'kimi_cli.tools.file:StrReplaceFile'
  ];

  const wantsWeb = toolBundle.some((entry) =>
    ['exa', 'browser-use', 'browserbase', 'chrome-devtools', 'google-maps-platform-code-assist'].includes(entry)
  );
  if (wantsWeb) {
    tools.push('kimi_cli.tools.web:SearchWeb', 'kimi_cli.tools.web:FetchURL');
  }

  return tools;
}

function kimiCliSpecPaths(projectRoot: string, envelope: RuntimeLaunchEnvelope, executionId: string): {
  agentFile: string;
  systemPromptFile: string;
  promptFile: string;
  shareDir: string;
} {
  const baseDir = executionsDir(projectRoot, envelope.runId, envelope.agentId);
  return {
    agentFile: path.join(baseDir, `${executionId}.agent.yaml`),
    systemPromptFile: path.join(baseDir, `${executionId}.system.md`),
    promptFile: path.join(baseDir, `${executionId}.prompt.md`),
    shareDir: prepareKimiShareDir(projectRoot, envelope, executionId)
  };
}

function buildKimiCliInvocation(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope,
  executionId: string
): {
  binary: string;
  args: string[];
  cwd: string;
  agentFile: string;
  systemPromptFile: string;
  promptFile: string;
  shareDir: string;
} {
  const binary = resolveKimiBinary();
  if (!binary) {
    throw new Error('Kimi CLI binary not found on PATH; install it or set KIMI_BINARY');
  }

  const requestBody =
    envelope.launchSpec &&
    typeof envelope.launchSpec === 'object' &&
    envelope.launchSpec.requestBody &&
    typeof envelope.launchSpec.requestBody === 'object'
      ? (envelope.launchSpec.requestBody as Record<string, unknown>)
      : {};

  const messages = requestBody.messages;
  const systemPrompt = extractRoleContent(messages, 'system') || 'You are operating inside the GG Agentic Harness.';
  const userPrompt =
    extractRoleContent(messages, 'user') ||
    [`Run ID: ${envelope.runId}`, `Agent ID: ${envelope.agentId}`, `Task: ${envelope.taskSummary}`, `Worktree: ${envelope.worktree}`].join(
      '\n'
    );
  const paths = kimiCliSpecPaths(projectRoot, envelope, executionId);
  const relativeSystemPrompt = `./${path.basename(paths.systemPromptFile)}`;
  const toolList = defaultKimiCliTools(envelope.toolBundle || []);
  const agentYaml = [
    'version: 1',
    'agent:',
    `  name: "GG Harness Kimi Worker ${envelope.agentId}"`,
    `  system_prompt_path: ${relativeSystemPrompt}`,
    '  tools:',
    ...toolList.map((entry) => `    - "${entry}"`)
  ].join('\n');

  fs.mkdirSync(path.dirname(paths.agentFile), { recursive: true });
  fs.writeFileSync(paths.systemPromptFile, `${systemPrompt.trim()}\n`, 'utf8');
  fs.writeFileSync(paths.promptFile, `${userPrompt.trim()}\n`, 'utf8');
  fs.writeFileSync(paths.agentFile, `${agentYaml}\n`, 'utf8');

  const args = [
    '--print',
    '--output-format',
    'text',
    '--final-message-only',
    '--yolo',
    '--no-thinking',
    '--work-dir',
    envelope.worktree,
    '--agent-file',
    paths.agentFile
  ];
  args.push('--prompt', userPrompt);

  return {
    binary,
    args,
    cwd: envelope.worktree,
    agentFile: paths.agentFile,
    systemPromptFile: paths.systemPromptFile,
    promptFile: paths.promptFile,
    shareDir: paths.shareDir
  };
}

function extractInitialPrompt(envelope: RuntimeLaunchEnvelope): string {
  if (envelope.runtime === 'kimi') {
    const requestBody =
      envelope.launchSpec &&
      typeof envelope.launchSpec === 'object' &&
      envelope.launchSpec.requestBody &&
      typeof envelope.launchSpec.requestBody === 'object'
        ? (envelope.launchSpec.requestBody as Record<string, unknown>)
        : {};
    const messages = requestBody.messages;
    const systemPrompt = extractRoleContent(messages, 'system');
    const userPrompt = extractRoleContent(messages, 'user');
    return [systemPrompt, userPrompt].filter(Boolean).join('\n\n').trim();
  }

  const launchSpec = envelope.launchSpec && typeof envelope.launchSpec === 'object' ? envelope.launchSpec : {};
  const contract = typeof launchSpec.prompt === 'string' ? launchSpec.prompt : '';
  const taskSummary = typeof launchSpec.taskSummary === 'string' ? launchSpec.taskSummary : envelope.taskSummary;
  const toolBundle = Array.isArray(launchSpec.toolBundle)
    ? (launchSpec.toolBundle as unknown[]).filter((entry): entry is string => typeof entry === 'string')
    : envelope.toolBundle;

  return [
    contract.trim(),
    `Run ID: ${envelope.runId}`,
    `Agent ID: ${envelope.agentId}`,
    `Runtime: ${envelope.runtime}`,
    `Task: ${taskSummary}`,
    `Worktree: ${envelope.worktree}`,
    `Allowed tool bundle: ${toolBundle.length ? toolBundle.join(', ') : 'none declared'}`
  ]
    .filter(Boolean)
    .join('\n')
    .trim();
}

function buildClaudeInteractiveInvocation(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope,
  executionId: string
): RuntimeInteractiveLaunchPlan {
  const binary = resolveClaudeBinary();
  if (!binary) {
    throw new Error('Claude CLI binary not found on PATH; install it or set CLAUDE_BINARY');
  }

  const initialPrompt = extractInitialPrompt(envelope);
  const requestFile = buildRequestFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const responseFile = buildResponseFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const transcriptFile = buildTranscriptFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const credentials = discoverRuntimeCredentials(projectRoot, envelope.runtime);
  const args = [
    '--dangerously-skip-permissions',
    '--add-dir',
    envelope.worktree,
    initialPrompt
  ];

  writeJson(requestFile, {
    executionId,
    adapterMode: resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport),
    launchTransport: envelope.launchTransport,
    binary,
    args,
    cwd: envelope.worktree,
    credentialDiscovery: credentials,
    envelope
  });

  return {
    executionId,
    adapterMode: resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport),
    launchTransport: envelope.launchTransport,
    binary,
    args,
    cwd: envelope.worktree,
    env: { ...process.env },
    requestFile,
    responseFile,
    transcriptFile,
    summary: `Claude background worker ${envelope.agentId}`
  };
}

function buildCodexInteractiveInvocation(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope,
  executionId: string
): RuntimeInteractiveLaunchPlan {
  const binary = resolveCodexBinary();
  if (!binary) {
    throw new Error('Codex CLI binary not found on PATH; install it or set CODEX_BINARY');
  }

  const initialPrompt = extractInitialPrompt(envelope);
  const requestFile = buildRequestFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const responseFile = buildResponseFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const transcriptFile = buildTranscriptFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const credentials = discoverRuntimeCredentials(projectRoot, envelope.runtime);
  const args = [
    '--dangerously-bypass-approvals-and-sandbox',
    '--no-alt-screen',
    '--cd',
    envelope.worktree,
    initialPrompt
  ];

  writeJson(requestFile, {
    executionId,
    adapterMode: resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport),
    launchTransport: envelope.launchTransport,
    binary,
    args,
    cwd: envelope.worktree,
    credentialDiscovery: credentials,
    envelope
  });

  return {
    executionId,
    adapterMode: resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport),
    launchTransport: envelope.launchTransport,
    binary,
    args,
    cwd: envelope.worktree,
    env: { ...process.env },
    requestFile,
    responseFile,
    transcriptFile,
    summary: `Codex background worker ${envelope.agentId}`
  };
}

function buildKimiInteractiveInvocation(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope,
  executionId: string
): RuntimeInteractiveLaunchPlan {
  const invocation = buildKimiCliInvocation(projectRoot, envelope, executionId);
  const requestFile = buildRequestFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const responseFile = buildResponseFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const transcriptFile = buildTranscriptFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const args = invocation.args.filter((entry) => entry !== '--print' && entry !== '--output-format' && entry !== 'text' && entry !== '--final-message-only');
  const credentials = discoverRuntimeCredentials(projectRoot, envelope.runtime);

  writeJson(requestFile, {
    executionId,
    adapterMode: resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport),
    launchTransport: envelope.launchTransport,
    binary: invocation.binary,
    args,
    cwd: invocation.cwd,
    agentFile: invocation.agentFile,
    systemPromptFile: invocation.systemPromptFile,
    promptFile: invocation.promptFile,
    shareDir: invocation.shareDir,
    credentialDiscovery: credentials,
    envelope
  });

  return {
    executionId,
    adapterMode: resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport),
    launchTransport: envelope.launchTransport,
    binary: invocation.binary,
    args,
    cwd: invocation.cwd,
    env: {
      ...process.env,
      KIMI_SHARE_DIR: invocation.shareDir
    },
    requestFile,
    responseFile,
    transcriptFile,
    summary: `Kimi live worker ${envelope.agentId}`
  };
}

export function supportsInteractiveRuntimeLaunch(projectRoot: string, envelope: RuntimeLaunchEnvelope): boolean {
  const transport = envelope.launchTransport || defaultLaunchTransport(projectRoot, envelope.runtime);
  if (envelope.runtime === 'kimi') {
    return transport === 'cli-session';
  }
  return transport === 'background-terminal';
}

export function buildInteractiveRuntimeLaunchPlan(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope
): RuntimeInteractiveLaunchPlan {
  const executionId = nextExecutionId();

  if (envelope.runtime === 'kimi' && envelope.launchTransport === 'cli-session') {
    return buildKimiInteractiveInvocation(projectRoot, envelope, executionId);
  }

  if (envelope.runtime === 'claude' && envelope.launchTransport === 'background-terminal') {
    return buildClaudeInteractiveInvocation(projectRoot, envelope, executionId);
  }

  if (envelope.runtime === 'codex' && envelope.launchTransport === 'background-terminal') {
    return buildCodexInteractiveInvocation(projectRoot, envelope, executionId);
  }

  throw new Error(`Interactive runtime launch is not supported for ${envelope.runtime} over ${envelope.launchTransport}`);
}

async function runProcess(
  command: string,
  args: string[],
  options: { cwd: string; signal?: AbortSignal; env?: NodeJS.ProcessEnv }
): Promise<{ code: number; signal: NodeJS.Signals | null; stdout: string; stderr: string }> {
  return await new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';
    let settled = false;

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', (error) => {
      if (!settled) {
        settled = true;
        reject(error);
      }
    });
    child.on('close', (code, signal) => {
      if (!settled) {
        settled = true;
        resolve({ code: code ?? -1, signal, stdout, stderr });
      }
    });

    if (options.signal) {
      const abort = () => {
        child.kill('SIGTERM');
      };
      if (options.signal.aborted) {
        abort();
      } else {
        options.signal.addEventListener('abort', abort, { once: true });
      }
    }
  });
}

function normalizeAssistantContent(content: unknown): string {
  if (typeof content === 'string') {
    return content;
  }
  if (!Array.isArray(content)) {
    return '';
  }

  return content
    .map((entry) => {
      if (typeof entry === 'string') {
        return entry;
      }
      if (entry && typeof entry === 'object') {
        const maybeText = (entry as { text?: unknown }).text;
        if (typeof maybeText === 'string') {
          return maybeText;
        }
      }
      return JSON.stringify(entry);
    })
    .filter(Boolean)
    .join('\n');
}

function extractAssistantText(responseBody: unknown): string {
  if (!responseBody || typeof responseBody !== 'object') {
    return '';
  }
  const choices = (responseBody as { choices?: Array<{ message?: { content?: unknown } }> }).choices;
  if (!Array.isArray(choices) || choices.length === 0) {
    return '';
  }
  return normalizeAssistantContent(choices[0]?.message?.content);
}

function writeTranscript(filePath: string, envelope: RuntimeLaunchEnvelope, outputText: string): void {
  const transcript = [
    `# Worker Transcript — ${envelope.agentId}`,
    '',
    `- Runtime: ${envelope.runtime}`,
    `- Run ID: ${envelope.runId}`,
    `- Task: ${envelope.taskSummary}`,
    '',
    '## Assistant Output',
    '',
    outputText.trim() || '_No assistant text returned._',
    ''
  ].join('\n');
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, transcript, 'utf8');
}

function buildRequestBody(projectRoot: string, envelope: RuntimeLaunchEnvelope): {
  requestBody: Record<string, unknown>;
  endpoint: string;
  apiKeyName: string;
  apiKeyValue: string;
  model: string;
} {
  const executionProfile = normalizeExecutionProfile(projectRoot, envelope.runtime);
  const apiKey = firstDefinedEnv(executionProfile.apiKeyEnv);
  if (!apiKey) {
    throw new Error(`Missing API key for ${envelope.runtime}; expected one of ${executionProfile.apiKeyEnv.join(', ')}`);
  }
  const baseUrl = (process.env.KIMI_API_BASE_URL || process.env.MOONSHOT_API_BASE_URL || executionProfile.apiBaseUrl).replace(/\/$/, '');
  const endpoint = `${baseUrl}${executionProfile.chatCompletionsPath}`;
  const specBody =
    envelope.launchSpec &&
    typeof envelope.launchSpec === 'object' &&
    envelope.launchSpec.requestBody &&
    typeof envelope.launchSpec.requestBody === 'object'
      ? ({ ...(envelope.launchSpec.requestBody as Record<string, unknown>) } as Record<string, unknown>)
      : {};

  if (!specBody.model) {
    specBody.model = executionProfile.model;
  }

  return {
    requestBody: specBody,
    endpoint,
    apiKeyName: apiKey.name,
    apiKeyValue: apiKey.value,
    model: executionProfile.model
  };
}

export async function executeRuntimeLaunch(
  projectRoot: string,
  envelope: RuntimeLaunchEnvelope,
  options?: { dryRun?: boolean; signal?: AbortSignal }
): Promise<RuntimeExecutionResult> {
  const startedAt = nowIso();
  const executionId = nextExecutionId();
  const requestFile = buildRequestFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const responseFile = buildResponseFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const transcriptFile = buildTranscriptFilePath(projectRoot, envelope.runId, envelope.agentId, executionId);
  const preflight = evaluateRuntimeLaunchPreflight(projectRoot, envelope);
  const adapterMode = resolveLaunchAdapterMode(projectRoot, envelope.runtime, envelope.launchTransport);

  writeJson(requestFile, {
    executionId,
    adapterMode,
    launchTransport: envelope.launchTransport,
    dryRun: Boolean(options?.dryRun),
    preflight,
    envelope
  });

  if (preflight.status !== 'passed') {
    return {
      executionId,
      status: 'failed',
      dryRun: Boolean(options?.dryRun),
      adapterMode,
      launchTransport: envelope.launchTransport,
      summary: preflight.summary,
      outputText: '',
      requestFile,
      responseFile: null,
      transcriptFile: null,
      error: preflight.checks.filter((entry) => entry.status === 'fail').map((entry) => entry.detail).join(' | '),
      responseStatus: null,
      startedAt,
      completedAt: nowIso()
    };
  }

  if (options?.dryRun) {
    return {
      executionId,
      status: 'completed',
      dryRun: true,
      adapterMode,
      launchTransport: envelope.launchTransport,
      summary: `Dry run complete for ${envelope.runtime} worker ${envelope.agentId}`,
      outputText: '',
      requestFile,
      responseFile: null,
      transcriptFile: null,
      error: null,
      responseStatus: null,
      startedAt,
      completedAt: nowIso()
    };
  }

  if (envelope.runtime !== 'kimi') {
    return {
      executionId,
      status: 'failed',
      dryRun: false,
      adapterMode,
      launchTransport: envelope.launchTransport,
      summary: `Unsupported execution path for ${envelope.runtime}`,
      outputText: '',
      requestFile,
      responseFile: null,
      transcriptFile: null,
      error: `Runtime ${envelope.runtime} does not support ${envelope.launchTransport} execution in this harness slice`,
      responseStatus: null,
      startedAt,
      completedAt: nowIso()
    };
  }

  if (envelope.launchTransport === 'cli-session') {
    const invocation = buildKimiCliInvocation(projectRoot, envelope, executionId);
    writeJson(requestFile, {
      executionId,
      adapterMode,
      launchTransport: envelope.launchTransport,
      binary: invocation.binary,
      args: invocation.args,
      cwd: invocation.cwd,
      agentFile: invocation.agentFile,
      systemPromptFile: invocation.systemPromptFile,
      promptFile: invocation.promptFile,
      shareDir: invocation.shareDir,
      envelope
    });

    const completed = await runProcess(invocation.binary, invocation.args, {
      cwd: invocation.cwd,
      signal: options?.signal,
      env: {
        ...process.env,
        KIMI_SHARE_DIR: invocation.shareDir
      }
    });

    writeJson(responseFile, {
      executionId,
      status: completed.code,
      signal: completed.signal,
      stdout: completed.stdout,
      stderr: completed.stderr
    });

    if (completed.code !== 0) {
      return {
        executionId,
        status: 'failed',
        dryRun: false,
        adapterMode,
        launchTransport: envelope.launchTransport,
        summary: `Kimi CLI exited with code ${completed.code}`,
        outputText: '',
        requestFile,
        responseFile,
        transcriptFile: null,
        error: completed.stderr.trim() || completed.stdout.trim() || `Exit code ${completed.code}`,
        responseStatus: completed.code,
        startedAt,
        completedAt: nowIso()
      };
    }

    const outputText = completed.stdout.trim() || completed.stderr.trim();
    writeTranscript(transcriptFile, envelope, outputText);

    return {
      executionId,
      status: 'completed',
      dryRun: false,
      adapterMode,
      launchTransport: envelope.launchTransport,
      summary: outputText.trim()
        ? outputText.trim().split('\n')[0].slice(0, 180)
        : `Kimi worker ${envelope.agentId} completed without assistant text`,
      outputText,
      requestFile,
      responseFile,
      transcriptFile,
      error: null,
      responseStatus: completed.code,
      startedAt,
      completedAt: nowIso()
    };
  }

  if (envelope.launchTransport !== 'api-session') {
    return {
      executionId,
      status: 'failed',
      dryRun: false,
      adapterMode,
      launchTransport: envelope.launchTransport,
      summary: `Unsupported Kimi launch transport ${envelope.launchTransport}`,
      outputText: '',
      requestFile,
      responseFile: null,
      transcriptFile: null,
      error: `Kimi does not support ${envelope.launchTransport} execution in this harness slice`,
      responseStatus: null,
      startedAt,
      completedAt: nowIso()
    };
  }

  const request = buildRequestBody(projectRoot, envelope);
  writeJson(requestFile, {
    executionId,
    adapterMode,
    launchTransport: envelope.launchTransport,
    endpoint: request.endpoint,
    apiKeyName: request.apiKeyName,
    requestBody: request.requestBody,
    envelope
  });

  const response = await fetch(request.endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${request.apiKeyValue}`
    },
    body: JSON.stringify(request.requestBody),
    signal: options?.signal
  });

  const rawText = await response.text();
  let parsedBody: unknown = null;
  try {
    parsedBody = rawText ? JSON.parse(rawText) : null;
  } catch {
    parsedBody = { rawText };
  }

  writeJson(responseFile, {
    executionId,
    status: response.status,
    ok: response.ok,
    body: parsedBody
  });

  if (!response.ok) {
    return {
      executionId,
      status: 'failed',
      dryRun: false,
      adapterMode,
      launchTransport: envelope.launchTransport,
      summary: `Kimi request failed with HTTP ${response.status}`,
      outputText: '',
      requestFile,
      responseFile,
      transcriptFile: null,
      error: typeof rawText === 'string' && rawText.trim() ? rawText.trim() : `HTTP ${response.status}`,
      responseStatus: response.status,
      startedAt,
      completedAt: nowIso()
    };
  }

  const outputText = extractAssistantText(parsedBody);
  writeTranscript(transcriptFile, envelope, outputText);

  return {
    executionId,
    status: 'completed',
    dryRun: false,
    adapterMode,
    launchTransport: envelope.launchTransport,
    summary: outputText.trim()
      ? outputText.trim().split('\n')[0].slice(0, 180)
      : `Kimi worker ${envelope.agentId} completed without assistant text`,
    outputText,
    requestFile,
    responseFile,
    transcriptFile,
    error: null,
    responseStatus: response.status,
    startedAt,
    completedAt: nowIso()
  };
}
