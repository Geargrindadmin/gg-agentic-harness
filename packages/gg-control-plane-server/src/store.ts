import fs from 'node:fs';
import path from 'node:path';

export interface ServerTaskRecord {
  runId: string;
  task: string;
  mode: string;
  source: string;
  coordinator?: string;
  model?: string;
  coordinatorProvider?: string;
  coordinatorModel?: string;
  workerBackend?: string;
  workerModel?: string;
  dispatchPath?: string;
  status: 'accepted' | 'running' | 'complete' | 'failed' | 'cancelled';
  prUrl?: string | null;
  startedAt: string;
  updatedAt?: string;
  completedAt?: string | null;
  durationMs?: number | null;
  log: string[];
}

export interface QualityToolFailure {
  tool: string;
  message: string;
}

export interface QualityJobRecord {
  id: string;
  status: 'running' | 'completed' | 'failed';
  tools: string[];
  profile: string;
  startedAt: string;
  completedAt: string | null;
  exitCode: number | null;
  output: string[];
  failures: QualityToolFailure[];
}

export interface IntegrationSettingsRecord {
  liteLLM: {
    enabled: boolean;
    baseUrl: string;
    apiKey: string;
    model: string;
    temperature: number;
    maxTokens: number;
    timeoutMs: number;
  };
  observability: {
    enabled: boolean;
    serviceName: string;
    environment: string;
    langfuse: {
      enabled: boolean;
      host: string;
      publicKey: string;
      secretKey: string;
    };
    openllmetry: {
      enabled: boolean;
      otlpEndpoint: string;
      headers: Record<string, string>;
    };
  };
  qualityTools: {
    defaultProjectRoot: string;
    tools: {
      promptfoo: boolean;
      semgrep: boolean;
      trivy: boolean;
      gitleaks: boolean;
    };
  };
  mcpCatalog: {
    catalogPath: string;
    kimiConfigPath: string;
    selectedServerIds: string[];
  };
}

export interface McpCatalogItem {
  id: string;
  name: string;
  mcpName: string;
  description: string;
  command: string;
  args?: string[];
  env?: Record<string, string>;
}

export interface McpCatalogRecord {
  servers: McpCatalogItem[];
  selectedServerIds: string[];
  kimiConfigPath: string;
}

export interface ServerPaths {
  root: string;
  tasksDir: string;
  settingsFile: string;
  qualityJobsFile: string;
  catalogFile: string;
}

function ensureDir(dirPath: string): void {
  fs.mkdirSync(dirPath, { recursive: true });
}

function readJson<T>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
}

function writeJson(filePath: string, value: unknown): void {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function taskFile(projectRoot: string, runId: string): string {
  return path.join(serverPaths(projectRoot).tasksDir, `${runId}.json`);
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function serverPaths(projectRoot: string): ServerPaths {
  const root = path.join(projectRoot, '.agent', 'control-plane', 'server');
  return {
    root,
    tasksDir: path.join(root, 'tasks'),
    settingsFile: path.join(root, 'integration-settings.json'),
    qualityJobsFile: path.join(root, 'quality-jobs.json'),
    catalogFile: path.join(root, 'mcp-catalog.json')
  };
}

export function ensureServerStore(projectRoot: string): void {
  const paths = serverPaths(projectRoot);
  ensureDir(paths.root);
  ensureDir(paths.tasksDir);
}

export function listTaskRecords(projectRoot: string): ServerTaskRecord[] {
  const paths = serverPaths(projectRoot);
  ensureDir(paths.tasksDir);
  return fs
    .readdirSync(paths.tasksDir)
    .filter((entry) => entry.endsWith('.json'))
    .map((entry) => readJson<ServerTaskRecord>(path.join(paths.tasksDir, entry)))
    .filter((entry): entry is ServerTaskRecord => Boolean(entry))
    .sort((left, right) => (right.updatedAt || right.startedAt).localeCompare(left.updatedAt || left.startedAt));
}

export function readTaskRecord(projectRoot: string, runId: string): ServerTaskRecord | null {
  return readJson<ServerTaskRecord>(taskFile(projectRoot, runId));
}

export function writeTaskRecord(projectRoot: string, task: ServerTaskRecord): ServerTaskRecord {
  ensureServerStore(projectRoot);
  const record = {
    ...task,
    updatedAt: nowIso(),
    log: [...task.log]
  };
  writeJson(taskFile(projectRoot, record.runId), record);
  return record;
}

export function appendTaskLog(projectRoot: string, runId: string, line: string): ServerTaskRecord | null {
  const task = readTaskRecord(projectRoot, runId);
  if (!task) {
    return null;
  }
  task.log.push(line);
  task.updatedAt = nowIso();
  return writeTaskRecord(projectRoot, task);
}

export function deleteTaskRecord(projectRoot: string, runId: string): void {
  const filePath = taskFile(projectRoot, runId);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
}

export function defaultIntegrationSettings(projectRoot: string): IntegrationSettingsRecord {
  return {
    liteLLM: {
      enabled: false,
      baseUrl: 'http://localhost:4000',
      apiKey: '',
      model: 'kimi-k2.5',
      temperature: 0.2,
      maxTokens: 4096,
      timeoutMs: 60000
    },
    observability: {
      enabled: false,
      serviceName: 'gg-agentic-harness',
      environment: 'local',
      langfuse: {
        enabled: false,
        host: '',
        publicKey: '',
        secretKey: ''
      },
      openllmetry: {
        enabled: false,
        otlpEndpoint: '',
        headers: {}
      }
    },
    qualityTools: {
      defaultProjectRoot: projectRoot,
      tools: {
        promptfoo: false,
        semgrep: false,
        trivy: false,
        gitleaks: false
      }
    },
    mcpCatalog: {
      catalogPath: serverPaths(projectRoot).catalogFile,
      kimiConfigPath: path.join(projectRoot, '.mcp.json'),
      selectedServerIds: ['gg-skills', 'filesystem-project']
    }
  };
}

export function readIntegrationSettings(projectRoot: string): IntegrationSettingsRecord {
  const existing = readJson<IntegrationSettingsRecord>(serverPaths(projectRoot).settingsFile);
  if (existing) {
    return existing;
  }
  const defaults = defaultIntegrationSettings(projectRoot);
  writeJson(serverPaths(projectRoot).settingsFile, defaults);
  return defaults;
}

export function writeIntegrationSettings(
  projectRoot: string,
  settings: IntegrationSettingsRecord
): IntegrationSettingsRecord {
  writeJson(serverPaths(projectRoot).settingsFile, settings);
  return settings;
}

export function listQualityJobs(projectRoot: string): QualityJobRecord[] {
  return readJson<QualityJobRecord[]>(serverPaths(projectRoot).qualityJobsFile) || [];
}

export function readQualityJob(projectRoot: string, id: string): QualityJobRecord | null {
  return listQualityJobs(projectRoot).find((entry) => entry.id === id) || null;
}

export function writeQualityJob(projectRoot: string, job: QualityJobRecord): QualityJobRecord {
  const jobs = listQualityJobs(projectRoot);
  const nextJobs = jobs.filter((entry) => entry.id !== job.id);
  nextJobs.unshift(job);
  writeJson(serverPaths(projectRoot).qualityJobsFile, nextJobs);
  return job;
}

export function builtInCatalog(projectRoot: string): McpCatalogRecord {
  return {
    servers: [
      {
        id: 'gg-skills',
        name: 'GG Skills',
        mcpName: 'gg-skills',
        description: 'Harness skills, workflows, and dynamic tools.',
        command: 'node',
        args: [path.join(projectRoot, 'mcp-servers', 'gg-skills', 'dist', 'index.js')]
      },
      {
        id: 'filesystem-project',
        name: 'Filesystem (Project)',
        mcpName: 'filesystem',
        description: 'Scoped filesystem access to the active project and temp directory.',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem', projectRoot, '/tmp']
      },
      {
        id: 'github-official',
        name: 'GitHub MCP',
        mcpName: 'github',
        description: 'GitHub repository, PR, and issue operations.',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-github'],
        env: {
          GITHUB_PERSONAL_ACCESS_TOKEN: '${GITHUB_TOKEN}'
        }
      },
      {
        id: 'context7',
        name: 'Context7 Docs',
        mcpName: 'context7',
        description: 'Live technical documentation lookup for libraries and frameworks.',
        command: 'npx',
        args: ['-y', '@upstash/context7-mcp']
      },
      {
        id: 'sequential-thinking',
        name: 'Sequential Thinking',
        mcpName: 'sequential-thinking',
        description: 'Structured step-by-step reasoning helper.',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-sequential-thinking']
      }
    ],
    selectedServerIds: readIntegrationSettings(projectRoot).mcpCatalog.selectedServerIds,
    kimiConfigPath: path.join(projectRoot, '.mcp.json')
  };
}

export function readMcpCatalog(projectRoot: string): McpCatalogRecord {
  const existing = readJson<McpCatalogRecord>(serverPaths(projectRoot).catalogFile);
  if (existing) {
    return {
      ...existing,
      selectedServerIds: readIntegrationSettings(projectRoot).mcpCatalog.selectedServerIds,
      kimiConfigPath: path.join(projectRoot, '.mcp.json')
    };
  }
  const defaults = builtInCatalog(projectRoot);
  writeJson(serverPaths(projectRoot).catalogFile, defaults);
  return defaults;
}
