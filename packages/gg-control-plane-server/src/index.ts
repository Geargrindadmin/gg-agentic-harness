#!/usr/bin/env node
import fs from 'node:fs';
import http, { type IncomingMessage, type ServerResponse } from 'node:http';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { URL, fileURLToPath } from 'node:url';
import {
  buildPersonaPacket,
  createRunState,
  delegateTask,
  executeWorker,
  fetchInbox,
  listRunMessages,
  listRunStates,
  postMessage,
  readRunState,
  setWorkerStatus,
  spawnWorker,
  terminateWorker,
  updateWorkerTask,
  writeRunState,
  type Classification,
  type MessageType,
  type PersonaPacket,
  type RunState,
  type RuntimeId,
  type WorkerRole,
  type WorkerStatus
} from '../../gg-orchestrator/dist/index.js';
import {
  buildInteractiveRuntimeLaunchPlan,
  discoverRuntimeCredentials,
  defaultLaunchTransport,
  selectCoordinatorRuntime,
  evaluateRuntimeLaunchPreflight,
  supportsInteractiveRuntimeLaunch,
  type RuntimeLaunchEnvelope
} from '../../gg-runtime-adapters/dist/index.js';
import { HarnessResourceGovernor } from './governor.js';
import {
  appendTaskLog,
  builtInCatalog,
  deleteTaskRecord,
  ensureServerStore,
  listQualityJobs,
  listTaskRecords,
  nowIso,
  readIntegrationSettings,
  readMcpCatalog,
  readQualityJob,
  readTaskRecord,
  serverPaths,
  writeIntegrationSettings,
  writeQualityJob,
  writeTaskRecord,
  type IntegrationSettingsRecord,
  type QualityJobRecord,
  type ServerTaskRecord
} from './store.js';
import {
  createPlannerNote,
  createPlannerTask,
  deletePlannerNote,
  deletePlannerTask,
  readPlannerSnapshot,
  updatePlannerNote,
  updatePlannerTask,
  type PlannerNoteInput,
  type PlannerNotePatch,
  type PlannerTaskInput,
  type PlannerTaskPatch
} from './planner.js';
import { collectUsageSnapshot } from './usage.js';
import { WorkerSessionManager, type StructuredHarnessMessage, type StructuredHarnessState } from './sessions.js';
import { listReplaySources, listReplaySessions, renderReplay } from './replays.js';
import { collectLMStudioCandidates, collectModelFitSnapshot } from './model-fit.js';
import { collectFreeModelProviders, collectFreeModelsCatalog } from './free-models.js';

type DispatchMode = 'minion' | 'go';

interface TaskPayload {
  task: string;
  source?: string;
  mode?: string;
  coordinator?: string;
  model?: string;
  coordinatorProvider?: string;
  coordinatorModel?: string;
  workerBackend?: string;
  workerModel?: string;
  dispatchPath?: string;
  bridgeContext?: string;
  bridgeWorktree?: string;
  bridgeAgents?: number;
  bridgeStrategy?: 'parallel' | 'sequential' | 'hierarchical';
  bridgeRoles?: string[];
  bridgeTimeoutSeconds?: number;
}

interface SteeringPayload {
  message?: string;
  summary?: string;
  taskSummary?: string;
  reason?: string;
  dryRun?: boolean;
}

interface PlannerTaskRequestBody {
  projectId?: string | null;
  title?: string;
  description?: string | null;
  status?: string;
  priority?: number;
  source?: string;
  sourceSession?: string | null;
  labels?: string[];
  attachments?: string[];
  isGlobal?: boolean;
  runId?: string | null;
  runtime?: string | null;
  linkedRunStatus?: string | null;
  assignedAgentId?: string | null;
  worktreePath?: string | null;
}

interface PlannerNoteRequestBody {
  title?: string;
  content?: string;
  pinned?: boolean;
  taskId?: string | null;
  projectId?: string | null;
  source?: string;
}

interface ControlPlaneMetadata {
  service: string;
  version: string;
  protocolVersion: number;
  apiBasePath: string;
  capabilities: string[];
  generatedAt: string;
}

interface QueueItem {
  runId: string;
  agentId: string;
  reason: string;
  dryRun: boolean;
}

interface RunEventMessage {
  type: 'run_created' | 'run_started' | 'run_completed' | 'run_failed' | 'run_cancelled' | 'snapshot';
  runId?: string;
  status?: string;
  coordinator?: string;
  model?: string;
  coordinatorProvider?: string;
  coordinatorModel?: string;
  workerBackend?: string;
  workerModel?: string;
  dispatchPath?: string;
  task?: string;
  runs?: ServerTaskRecord[];
  ts: string;
}

const DEFAULT_PORT = Number(process.env.HARNESS_CONTROL_PLANE_PORT || 7891);
const PROJECT_ROOT = path.resolve(process.env.PROJECT_ROOT || process.cwd());
const governor = new HarnessResourceGovernor();
const CONTROL_PLANE_PROTOCOL_VERSION = 1;
const CONTROL_PLANE_CAPABILITIES = [
  'runs',
  'planner',
  'usage',
  'governor',
  'worker-steering',
  'sse-events',
  'bus-status',
  'worktrees',
  'worker-streams',
  'live-bus-stream',
  'live-log-stream',
  'agent-analytics',
  'swarm-telemetry',
  'replays',
  'model-fit',
  'free-models'
] as const;
const CONTROL_PLANE_VERSION = loadControlPlaneVersion();
const queue: QueueItem[] = [];
const runningControllers = new Map<string, AbortController>();
const taskLogSubscribers = new Map<string, Set<ServerResponse>>();
const liveLogSubscribers = new Set<ServerResponse>();
const busSubscribers = new Map<string, Set<ServerResponse>>();
const workerStreamSubscribers = new Map<string, Set<ServerResponse>>();
const eventSubscribers = new Set<ServerResponse>();
const sessionManager = new WorkerSessionManager();

function loadControlPlaneVersion(): string {
  try {
    const currentDir = path.dirname(fileURLToPath(import.meta.url));
    const packageFile = path.resolve(currentDir, '../package.json');
    const parsed = JSON.parse(fs.readFileSync(packageFile, 'utf8')) as { version?: string };
    return parsed.version || '0.0.0';
  } catch {
    return '0.0.0';
  }
}

function controlPlaneMeta(): ControlPlaneMetadata {
  return {
    service: 'gg-control-plane-server',
    version: CONTROL_PLANE_VERSION,
    protocolVersion: CONTROL_PLANE_PROTOCOL_VERSION,
    apiBasePath: '/api',
    capabilities: [...CONTROL_PLANE_CAPABILITIES],
    generatedAt: nowIso()
  };
}

interface RuntimeDiscoverySnapshot {
  runtime: string;
  label?: string;
  binaryPath: string | null;
  authenticated: boolean;
  localCliAuth: boolean;
  directApiAvailable: boolean;
  preferredTransport: string | null;
  summary: string;
  sources: Array<{
    id: string;
    type: 'file' | 'env';
    location: string;
    status: 'present' | 'missing';
    detail: string;
  }>;
}

function readJsonFile<T>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
  } catch {
    return null;
  }
}

function fileSource(id: string, filePath: string, present: boolean, detail: string): RuntimeDiscoverySnapshot['sources'][number] {
  return {
    id,
    type: 'file',
    location: filePath,
    status: present ? 'present' : 'missing',
    detail
  };
}

function buildAntigravityProviderDiscoveries(): RuntimeDiscoverySnapshot[] {
  const antigravityProxyPath = path.join(process.env.HOME || PROJECT_ROOT, '.config', 'antigravity-proxy', 'accounts.json');
  const antigravityOpenCodePath = path.join(process.env.HOME || PROJECT_ROOT, '.config', 'opencode', 'antigravity-accounts.json');
  const geminiAccountsPath = path.join(process.env.HOME || PROJECT_ROOT, '.gemini', 'google_accounts.json');

  const antigravityProxy = readJsonFile<{
    accounts?: Array<{ enabled?: boolean; isInvalid?: boolean; modelRateLimits?: Record<string, unknown> }>;
  }>(antigravityProxyPath);
  const antigravityOpenCode = readJsonFile<{
    activeIndexByFamily?: Record<string, number>;
    accounts?: Array<{ enabled?: boolean; rateLimitResetTimes?: Record<string, unknown> }>;
  }>(antigravityOpenCodePath);
  const geminiAccounts = readJsonFile<{ active?: unknown; old?: unknown[] }>(geminiAccountsPath);

  const modelHints = new Set<string>();
  for (const account of antigravityProxy?.accounts || []) {
    if (account.enabled === false || account.isInvalid) {
      continue;
    }
    for (const key of Object.keys(account.modelRateLimits || {})) {
      modelHints.add(key.toLowerCase());
    }
  }
  for (const account of antigravityOpenCode?.accounts || []) {
    if (account.enabled === false) {
      continue;
    }
    for (const key of Object.keys(account.rateLimitResetTimes || {})) {
      modelHints.add(key.toLowerCase());
    }
  }

  const families = antigravityOpenCode?.activeIndexByFamily || {};
  const sources = [
    fileSource('antigravity_proxy', antigravityProxyPath, Boolean(antigravityProxy), 'Antigravity account registry'),
    fileSource('antigravity_opencode', antigravityOpenCodePath, Boolean(antigravityOpenCode), 'OpenCode Antigravity family map'),
    fileSource('gemini_accounts', geminiAccountsPath, Boolean(geminiAccounts), 'Google/Gemini local account registry')
  ];

  const hasClaude = typeof families.claude === 'number' || Array.from(modelHints).some((entry) => entry.includes('claude'));
  const hasGemini =
    typeof families.gemini === 'number'
    || Array.from(modelHints).some((entry) => entry.includes('gemini'))
    || geminiAccounts?.active != null
    || Boolean(geminiAccounts?.old?.length);
  const hasGptFamily =
    typeof families.openai === 'number'
    || typeof families.gpt === 'number'
    || Array.from(modelHints).some((entry) => entry.includes('gpt') || entry.includes('openai') || entry.includes('gpt-oss'));

  const discoveries: RuntimeDiscoverySnapshot[] = [];

  if (hasClaude) {
    discoveries.push({
      runtime: 'claude-antigravity',
      label: 'Claude via Antigravity',
      binaryPath: null,
      authenticated: true,
      localCliAuth: true,
      directApiAvailable: false,
      preferredTransport: null,
      summary: 'Inherited Claude OAuth/session is available from Antigravity account state',
      sources
    });
  }

  if (hasGemini) {
    discoveries.push({
      runtime: 'gemini-antigravity',
      label: 'Gemini via Antigravity',
      binaryPath: null,
      authenticated: true,
      localCliAuth: true,
      directApiAvailable: false,
      preferredTransport: null,
      summary: 'Inherited Gemini OAuth/session is available from Antigravity and local Gemini account state',
      sources
    });
  }

  if (hasGptFamily) {
    discoveries.push({
      runtime: 'gpt-antigravity',
      label: 'GPT-family via Antigravity',
      binaryPath: null,
      authenticated: true,
      localCliAuth: true,
      directApiAvailable: false,
      preferredTransport: null,
      summary: 'Antigravity indicates a GPT/OpenAI-family route is configured locally',
      sources
    });
  }

  return discoveries;
}

function json(res: ServerResponse, statusCode: number, payload: unknown): void {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(`${JSON.stringify(payload, null, 2)}\n`);
}

function text(res: ServerResponse, statusCode: number, payload: string): void {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.end(payload);
}

function noContent(res: ServerResponse): void {
  res.statusCode = 204;
  res.end();
}

function routeKey(runId: string, agentId: string): string {
  return `${runId}:${agentId}`;
}

function nextId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function normalizeDispatchMode(mode?: string): DispatchMode {
  const normalized = String(mode || 'minion').trim().toLowerCase();
  return normalized === 'go' || normalized === 'execute' ? 'go' : 'minion';
}

function normalizeCoordinator(value?: string): string {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) {
    return 'auto';
  }
  if (['auto', 'claude', 'custom', 'kimi', 'codex', 'lm-studio'].includes(normalized)) {
    return normalized;
  }
  return 'custom';
}

function classificationFromMode(mode: DispatchMode): Classification {
  return mode === 'go' ? 'TASK' : 'TASK_LITE';
}

function coordinatorRuntimeHint(body: TaskPayload): RuntimeId | null {
  const coordinator = normalizeCoordinator(body.coordinator);
  if (coordinator === 'claude' || coordinator === 'codex' || coordinator === 'kimi') {
    return coordinator;
  }

  const fields = [
    body.model,
    body.coordinatorProvider,
    body.coordinatorModel,
    body.workerBackend,
    body.workerModel,
    body.dispatchPath
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();

  if (fields.includes('claude')) {
    return 'claude';
  }
  if (fields.includes('codex')) {
    return 'codex';
  }
  return null;
}

function inferRuntime(body: TaskPayload): RuntimeId {
  return selectCoordinatorRuntime(PROJECT_ROOT, coordinatorRuntimeHint(body)).selected;
}

function defaultPersonaIdForRole(role: WorkerRole): string {
  switch (role) {
    case 'coordinator':
      return 'orchestrator';
    case 'planner':
      return 'project-planner';
    case 'reviewer':
      return 'test-engineer';
    case 'scout':
      return 'explorer-agent';
    case 'builder':
      return 'backend-specialist';
    default:
      return 'backend-specialist';
  }
}

function buildRolePlan(body: TaskPayload): WorkerRole[] {
  const requested = (body.bridgeRoles || [])
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean)
    .map((entry) => {
      if (['coordinator', 'planner', 'builder', 'reviewer', 'scout', 'assembler', 'specialist'].includes(entry)) {
        return entry as WorkerRole;
      }
      return null;
    })
    .filter((entry): entry is WorkerRole => Boolean(entry));

  if (requested.length) {
    return requested;
  }

  const count = Math.max(1, Math.min(6, Number(body.bridgeAgents || 3)));
  const defaults: WorkerRole[] = ['scout', 'builder', 'reviewer', 'planner', 'builder', 'specialist'];
  return defaults.slice(0, count);
}

function worktreesRoot(projectRoot: string, runId: string): string {
  return path.join(projectRoot, '.agent', 'control-plane', 'worktrees', runId);
}

function ensureWorkerWorktree(projectRoot: string, runId: string, agentId: string): string {
  const target = path.join(worktreesRoot(projectRoot, runId), agentId);
  fs.mkdirSync(path.dirname(target), { recursive: true });

  if (fs.existsSync(path.join(target, '.git'))) {
    return target;
  }

  if (fs.existsSync(target) && fs.readdirSync(target).length > 0) {
    throw new Error(`Worktree target already exists and is not empty: ${target}`);
  }

  const result = spawnSync('git', ['-C', projectRoot, 'worktree', 'add', '--force', '--detach', target, 'HEAD'], {
    cwd: projectRoot,
    encoding: 'utf8'
  });

  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `git worktree add failed for ${target}`).trim());
  }

  return target;
}

function toBusWorkerStatus(status: WorkerStatus): string {
  switch (status) {
    case 'handoff_ready':
    case 'completed':
      return 'complete';
    case 'failed':
    case 'blocked':
    case 'terminated':
      return 'failed';
    case 'queued':
      return 'queued';
    default:
      return 'running';
  }
}

function progressForStatus(status: WorkerStatus): number {
  switch (status) {
    case 'queued':
      return 5;
    case 'spawn_requested':
      return 10;
    case 'running':
      return 55;
    case 'handoff_ready':
    case 'completed':
      return 100;
    case 'blocked':
    case 'failed':
    case 'terminated':
      return 100;
    default:
      return 0;
  }
}

function deriveTaskStatus(run: RunState): ServerTaskRecord['status'] {
  if (!run.workers.length) {
    return 'accepted';
  }

  if (run.workers.some((worker) => ['spawn_requested', 'queued', 'running', 'planned'].includes(worker.status))) {
    return 'running';
  }

  if (run.workers.every((worker) => worker.status === 'terminated')) {
    return 'cancelled';
  }

  if (run.workers.some((worker) => ['failed', 'blocked'].includes(worker.status))) {
    return 'failed';
  }

  if (run.workers.every((worker) => ['handoff_ready', 'completed', 'terminated'].includes(worker.status))) {
    return 'complete';
  }

  return 'running';
}

function activeWorkerCount(): number {
  return runningControllers.size + sessionManager.count();
}

function activeWorkerCountByRuntime(runtime: RuntimeId): number {
  const activeStatuses = new Set(['spawn_requested', 'planned', 'queued', 'running']);
  return listRunStates(PROJECT_ROOT).reduce((total, run) => {
    return (
      total +
      run.workers.filter((worker) => worker.runtime === runtime && activeStatuses.has(worker.status)).length
    );
  }, 0);
}

function governorSnapshot() {
  return governor.snapshot(activeWorkerCount(), queue.length);
}

function classifyLogLevel(line: string): 'info' | 'warn' | 'error' | 'debug' {
  const normalized = line.toUpperCase();
  if (normalized.includes('AGENT_FAILED') || normalized.includes('SPAWN_FAILED') || normalized.includes('ERROR')) {
    return 'error';
  }
  if (normalized.includes('BLOCKED') || normalized.includes('WARN')) {
    return 'warn';
  }
  if (normalized.includes('DEBUG')) {
    return 'debug';
  }
  return 'info';
}

function summarizeCounts(values: string[]): Array<{ key: string; label: string; count: number }> {
  const counts = new Map<string, number>();
  for (const value of values.filter(Boolean)) {
    counts.set(value, (counts.get(value) || 0) + 1);
  }
  return Array.from(counts.entries())
    .map(([key, count]) => ({
      key,
      label: key
        .split(/[-_]/g)
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(' '),
      count
    }))
    .sort((left, right) => right.count - left.count || left.label.localeCompare(right.label));
}

function humanizeKey(value: string): string {
  return value
    .split(/[-_]/g)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function taskLogEnvelope(runId: string, line: string, ts = nowIso(), seed?: string) {
  return {
    id: seed || `${runId}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
    ts,
    level: classifyLogLevel(line),
    msg: line,
    runId
  };
}

function recentTaskLogEnvelopes(limit = 200): ReturnType<typeof taskLogEnvelope>[] {
  const records = listTaskRecords(PROJECT_ROOT).slice(0, 12).reverse();
  const lines = records.flatMap((record) =>
    record.log.map((line, index) =>
      taskLogEnvelope(record.runId, line, record.updatedAt || record.startedAt, `${record.runId}-${index}`)
    )
  );
  return lines.slice(-limit);
}

function emitTaskLog(runId: string, line: string): void {
  const record = appendTaskLog(PROJECT_ROOT, runId, line);
  if (!record) {
    return;
  }

  const envelope = taskLogEnvelope(
    runId,
    line,
    record.updatedAt || nowIso(),
    `${runId}-${Math.max(0, record.log.length - 1)}`
  );
  const subscribers = taskLogSubscribers.get(runId);
  if (subscribers) {
    const payload = `data: ${JSON.stringify({ line, logLine: envelope })}\n\n`;
    for (const res of subscribers) {
      try {
        res.write(payload);
      } catch {
        subscribers.delete(res);
      }
    }
  }

  const livePayload = `data: ${JSON.stringify({ line: envelope })}\n\n`;
  for (const res of liveLogSubscribers) {
    try {
      res.write(livePayload);
    } catch {
      liveLogSubscribers.delete(res);
    }
  }
}

function emitRunEvent(event: Omit<RunEventMessage, 'ts'>): void {
  const payload: RunEventMessage = { ...event, ts: nowIso() };
  const line = `data: ${JSON.stringify(payload)}\n\n`;
  for (const res of eventSubscribers) {
    try {
      res.write(line);
    } catch {
      eventSubscribers.delete(res);
    }
  }
}

function launchEnvelopeFromRun(runId: string, agentId: string): { run: RunState; worker: RunState['workers'][number]; envelope: RuntimeLaunchEnvelope } {
  const run = readRunState(PROJECT_ROOT, runId);
  const worker = run.workers.find((entry) => entry.agentId === agentId);
  if (!worker) {
    throw new Error(`Worker not found in run ${runId}: ${agentId}`);
  }

  return {
    run,
    worker,
    envelope: {
      runId,
      agentId,
      runtime: worker.runtime,
      taskSummary: worker.taskSummary,
      worktree: worker.worktree,
      toolBundle: worker.toolBundle,
      launchTransport: worker.launchTransport || defaultLaunchTransport(PROJECT_ROOT, worker.runtime),
      launchSpec: worker.launchSpec
    }
  };
}

function busSubscriberSet(runId: string): Set<ServerResponse> {
  let subscribers = busSubscribers.get(runId);
  if (!subscribers) {
    subscribers = new Set();
    busSubscribers.set(runId, subscribers);
  }
  return subscribers;
}

function workerSubscriberSet(runId: string, agentId: string): Set<ServerResponse> {
  const key = routeKey(runId, agentId);
  let subscribers = workerStreamSubscribers.get(key);
  if (!subscribers) {
    subscribers = new Set();
    workerStreamSubscribers.set(key, subscribers);
  }
  return subscribers;
}

function emitBusMessage(runId: string, message: ReturnType<typeof listRunMessages>[number]): void {
  const subscribers = busSubscribers.get(runId);
  if (!subscribers || subscribers.size === 0) {
    return;
  }

  const payload = `data: ${JSON.stringify({ event: 'bus_message', message: busMessageEnvelope(message), runId })}\n\n`;
  for (const res of subscribers) {
    try {
      res.write(payload);
    } catch {
      subscribers.delete(res);
    }
  }
}

function emitWorkerStream(runId: string, agentId: string, line: string): void {
  const subscribers = workerStreamSubscribers.get(routeKey(runId, agentId));
  if (!subscribers || subscribers.size === 0) {
    return;
  }

  const payload = `data: ${JSON.stringify({ runId, agentId, line })}\n\n`;
  for (const res of subscribers) {
    try {
      res.write(payload);
    } catch {
      subscribers.delete(res);
    }
  }
}

function postBusMessageAndNotify(
  input: Parameters<typeof postMessage>[1]
): ReturnType<typeof postMessage> {
  const response = postMessage(PROJECT_ROOT, input);
  emitBusMessage(input.runId, response.message);
  return response;
}

function formatOperatorGuidance(message: string): string {
  return [
    '',
    '[HARNESS_GUIDANCE]',
    message.trim(),
    'If you are blocked, emit @@GG_MSG {"type":"BLOCKED","body":"<reason>","requiresAck":true}.',
    'If you have progress, emit @@GG_MSG {"type":"PROGRESS","body":"<summary>"}.',
    'When complete, emit @@GG_STATE {"status":"handoff_ready","summary":"<summary>"}.',
    ''
  ].join('\n');
}

function recoverStructuredMarker<T extends StructuredHarnessMessage | StructuredHarnessState>(
  output: string,
  marker: '@@GG_MSG' | '@@GG_STATE'
): T | null {
  const start = output.lastIndexOf(marker);
  if (start === -1) {
    return null;
  }

  const braceStart = output.indexOf('{', start);
  if (braceStart === -1) {
    return null;
  }

  let depth = 0;
  let end = -1;
  for (let index = braceStart; index < output.length; index += 1) {
    const char = output[index];
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        end = index;
        break;
      }
    }
  }

  if (end === -1) {
    return null;
  }

  const candidate = output
    .slice(braceStart, end + 1)
    .replace(/[\r\n]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  try {
    return JSON.parse(candidate) as T;
  } catch {
    return null;
  }
}

function recordLiveExecutionStart(
  runId: string,
  agentId: string,
  executionId: string,
  summary: string,
  preflight: ReturnType<typeof evaluateRuntimeLaunchPreflight>,
  requestFile: string,
  responseFile: string,
  transcriptFile: string,
  dryRun: boolean
): void {
  const run = readRunState(PROJECT_ROOT, runId);
  const worker = run.workers.find((entry) => entry.agentId === agentId);
  if (!worker) {
    throw new Error(`Worker not found in run ${runId}: ${agentId}`);
  }

  worker.execution.status = 'running';
  worker.execution.attempts += 1;
  worker.execution.lastExecutionId = executionId;
  worker.execution.requestFile = requestFile;
  worker.execution.responseFile = responseFile;
  worker.execution.transcriptFile = transcriptFile;
  worker.execution.lastPreflight = preflight;
  worker.execution.lastStartedAt = nowIso();
  worker.execution.lastCompletedAt = null;
  worker.execution.lastSummary = summary;
  worker.execution.lastError = '';
  worker.execution.dryRun = dryRun;
  worker.status = 'running';
  worker.updatedAt = nowIso();
  writeRunState(PROJECT_ROOT, run);
}

function finalizeLiveWorker(
  runId: string,
  agentId: string,
  input: {
    status: WorkerStatus;
    executionStatus: 'completed' | 'failed';
    summary: string;
    error?: string;
  }
): void {
  const run = readRunState(PROJECT_ROOT, runId);
  const worker = run.workers.find((entry) => entry.agentId === agentId);
  if (!worker) {
    throw new Error(`Worker not found in run ${runId}: ${agentId}`);
  }

  worker.status = input.status;
  worker.execution.status = input.executionStatus;
  worker.execution.lastSummary = input.summary;
  worker.execution.lastError = input.error || '';
  worker.execution.lastCompletedAt = nowIso();
  worker.updatedAt = nowIso();
  writeRunState(PROJECT_ROOT, run);
}

function syncTaskFromRun(runId: string): ServerTaskRecord | null {
  const task = readTaskRecord(PROJECT_ROOT, runId);
  let run: RunState;
  try {
    run = readRunState(PROJECT_ROOT, runId);
  } catch {
    return task;
  }
  const derivedStatus = deriveTaskStatus(run);
  const previousStatus = task?.status;
  const updatedAt = nowIso();

  const record: ServerTaskRecord = {
    runId,
    task: task?.task || run.summary,
    mode: task?.mode || 'minion',
    source: task?.source || 'control-plane',
    coordinator: task?.coordinator,
    model: task?.model,
    coordinatorProvider: task?.coordinatorProvider,
    coordinatorModel: task?.coordinatorModel,
    workerBackend: task?.workerBackend,
    workerModel: task?.workerModel,
    dispatchPath: task?.dispatchPath,
    status: derivedStatus,
    prUrl: task?.prUrl || null,
    startedAt: task?.startedAt || run.createdAt,
    updatedAt,
    completedAt: ['complete', 'failed', 'cancelled'].includes(derivedStatus)
      ? task?.completedAt || updatedAt
      : null,
    durationMs:
      ['complete', 'failed', 'cancelled'].includes(derivedStatus)
        ? Math.max(0, Date.parse(updatedAt) - Date.parse(task?.startedAt || run.createdAt))
        : null,
    log: task?.log || []
  };

  writeTaskRecord(PROJECT_ROOT, record);

  if (previousStatus !== derivedStatus) {
    const eventType =
      derivedStatus === 'running'
        ? 'run_started'
        : derivedStatus === 'complete'
          ? 'run_completed'
          : derivedStatus === 'failed'
            ? 'run_failed'
            : derivedStatus === 'cancelled'
              ? 'run_cancelled'
              : 'run_created';

    emitRunEvent({
      type: eventType,
      runId,
      status: derivedStatus,
      coordinator: record.coordinator,
      model: record.model,
      coordinatorProvider: record.coordinatorProvider,
      coordinatorModel: record.coordinatorModel,
      workerBackend: record.workerBackend,
      workerModel: record.workerModel,
      dispatchPath: record.dispatchPath,
      task: record.task
    });
  }

  return record;
}

function inferChildRuntime(body: TaskPayload): RuntimeId {
  const worker = `${body.workerBackend || ''} ${body.workerModel || ''}`.toLowerCase();
  if (worker.includes('claude')) {
    return 'claude';
  }
  if (worker.includes('codex')) {
    return 'codex';
  }
  return 'kimi';
}

function scheduleWorkerLaunch(runId: string, agentId: string, reason: string, dryRun = false): void {
  const snapshot = governorSnapshot();
  if (!snapshot.canSpawnNow) {
    queue.push({ runId, agentId, reason, dryRun });
    setWorkerStatus(PROJECT_ROOT, {
      runId,
      agentId,
      status: 'queued',
      summary: `Queued by harness governor: ${snapshot.reason}`,
      executionStatus: 'pending'
    });
    emitTaskLog(runId, `QUEUE_WORKER: ${agentId} — ${snapshot.reason}`);
    syncTaskFromRun(runId);
    return;
  }

  void launchWorkerNow(runId, agentId, dryRun, reason);
}

function handleStructuredWorkerMessage(runId: string, agentId: string, message: StructuredHarnessMessage): void {
  const { worker } = launchEnvelopeFromRun(runId, agentId);
  const parentId = worker.parentAgentId || 'operator';
  const messageType = (message.type || 'PROGRESS').toUpperCase();
  const allowedTypes = new Set(['TASK_SPEC', 'PROGRESS', 'BLOCKED', 'DELEGATE_REQUEST', 'HANDOFF_READY', 'SYSTEM']);
  const type = allowedTypes.has(messageType) ? (messageType as MessageType) : 'PROGRESS';
  postBusMessageAndNotify({
    runId,
    fromAgentId: agentId,
    toAgentId: message.to || parentId,
    type,
    payload: {
      ...(message.payload || {}),
      body: message.body || '',
      toId: message.to || parentId
    },
    requiresAck: Boolean(message.requiresAck)
  });

  emitTaskLog(runId, `AGENT_MSG: ${agentId} → ${message.to || parentId} — ${message.body || type}`);
}

function handleStructuredWorkerState(runId: string, agentId: string, state: StructuredHarnessState): void {
  const normalized = String(state.status || '').trim().toLowerCase();
  if (!normalized) {
    return;
  }

  if (normalized === 'handoff_ready') {
    finalizeLiveWorker(runId, agentId, {
      status: 'handoff_ready',
      executionStatus: 'completed',
      summary: state.summary || 'Worker reported HANDOFF_READY'
    });
    const { worker } = launchEnvelopeFromRun(runId, agentId);
    if (worker.parentAgentId) {
      postBusMessageAndNotify({
        runId,
        fromAgentId: agentId,
        toAgentId: worker.parentAgentId,
        type: 'HANDOFF_READY',
        payload: {
          summary: state.summary || 'Worker reported HANDOFF_READY',
          executionId: worker.execution.lastExecutionId,
          transcriptFile: worker.execution.transcriptFile,
          responseFile: worker.execution.responseFile
        },
        requiresAck: true
      });
    }
    emitTaskLog(runId, `HANDOFF_READY: ${agentId} — ${state.summary || 'Worker reported HANDOFF_READY'}`);
    return;
  }

  if (normalized === 'blocked') {
    finalizeLiveWorker(runId, agentId, {
      status: 'blocked',
      executionStatus: 'failed',
      summary: state.reason || state.summary || 'Worker reported BLOCKED',
      error: state.reason || state.summary || 'Worker reported BLOCKED'
    });
    const { worker } = launchEnvelopeFromRun(runId, agentId);
    if (worker.parentAgentId) {
      postBusMessageAndNotify({
        runId,
        fromAgentId: agentId,
        toAgentId: worker.parentAgentId,
        type: 'BLOCKED',
        payload: {
          reason: state.reason || state.summary || 'Worker reported BLOCKED',
          executionId: worker.execution.lastExecutionId
        },
        requiresAck: true
      });
    }
    emitTaskLog(runId, `BLOCKED: ${agentId} — ${state.reason || state.summary || 'Worker reported BLOCKED'}`);
  }
}

async function launchWorkerSessionNow(runId: string, agentId: string, dryRun: boolean, reason: string): Promise<void> {
  const key = routeKey(runId, agentId);
  if (runningControllers.has(key) || sessionManager.has(runId, agentId)) {
    return;
  }

  const { worker, envelope } = launchEnvelopeFromRun(runId, agentId);
  const preflight = evaluateRuntimeLaunchPreflight(PROJECT_ROOT, envelope);
  if (preflight.status !== 'passed') {
    const failedRun = readRunState(PROJECT_ROOT, runId);
    const failedWorker = failedRun.workers.find((entry) => entry.agentId === agentId);
    if (failedWorker) {
      failedWorker.execution.attempts += 1;
      failedWorker.execution.lastPreflight = preflight;
      failedWorker.execution.lastStartedAt = nowIso();
      failedWorker.execution.lastCompletedAt = nowIso();
      writeRunState(PROJECT_ROOT, failedRun);
    }
    finalizeLiveWorker(runId, agentId, {
      status: 'failed',
      executionStatus: 'failed',
      summary: preflight.summary,
      error: preflight.checks.filter((entry) => entry.status === 'fail').map((entry) => entry.detail).join(' | ')
    });
    if (worker.parentAgentId) {
      postBusMessageAndNotify({
        runId,
        fromAgentId: agentId,
        toAgentId: worker.parentAgentId,
        type: 'BLOCKED',
        payload: {
          reason: preflight.summary,
          preflight
        },
        requiresAck: true
      });
    }
    emitTaskLog(runId, `AGENT_FAILED: ${agentId} — ${preflight.summary}`);
    syncTaskFromRun(runId);
    drainLaunchQueue();
    return;
  }

  if (dryRun) {
    const result = await executeWorker(PROJECT_ROOT, {
      runId,
      agentId,
      dryRun,
      signal: undefined
    });
    emitTaskLog(runId, `${result.execution.status === 'completed' ? 'HANDOFF_READY' : 'AGENT_FAILED'}: ${agentId} — ${result.execution.summary}`);
    syncTaskFromRun(runId);
    drainLaunchQueue();
    return;
  }

  const launchPlan = buildInteractiveRuntimeLaunchPlan(PROJECT_ROOT, envelope);
  emitTaskLog(runId, `LIVE_SESSION: ${agentId} — ${reason}`);
  recordLiveExecutionStart(
    runId,
    agentId,
    launchPlan.executionId,
    launchPlan.summary,
    preflight,
    launchPlan.requestFile,
    launchPlan.responseFile,
    launchPlan.transcriptFile,
    false
  );

  sessionManager.start(
    {
      runId,
      agentId,
      executionId: launchPlan.executionId,
      binary: launchPlan.binary,
      args: launchPlan.args,
      cwd: launchPlan.cwd,
      env: launchPlan.env,
      requestFile: launchPlan.requestFile,
      responseFile: launchPlan.responseFile,
      transcriptFile: launchPlan.transcriptFile,
      summary: launchPlan.summary
    },
    {
      onLine: (line) => {
        emitWorkerStream(runId, agentId, line);
        emitTaskLog(runId, `WORKER_STREAM:${agentId}: ${line}`);
      },
      onMessage: (message) => {
        handleStructuredWorkerMessage(runId, agentId, message);
      },
      onState: (state) => {
        handleStructuredWorkerState(runId, agentId, state);
      },
      onExit: (event) => {
        const updated = readRunState(PROJECT_ROOT, runId).workers.find((entry) => entry.agentId === agentId);
        if (!updated) {
          return;
        }
        if (updated.status !== 'handoff_ready' && updated.status !== 'blocked' && updated.status !== 'terminated') {
          const recoveredState = recoverStructuredMarker<StructuredHarnessState>(event.cleanedOutput, '@@GG_STATE');
          if (recoveredState?.status) {
            handleStructuredWorkerState(runId, agentId, recoveredState);
            syncTaskFromRun(runId);
            drainLaunchQueue();
            return;
          }

          const recoveredMessage = recoverStructuredMarker<StructuredHarnessMessage>(event.cleanedOutput, '@@GG_MSG');
          const exitSummary =
            recoveredMessage?.body ||
            event.lastMeaningfulLine ||
            (event.exitCode === 0 ? 'Worker session exited cleanly' : `Worker session exited with code ${event.exitCode}`);
          const exitStatus = event.exitCode === 0 ? 'handoff_ready' : 'failed';
          finalizeLiveWorker(runId, agentId, {
            status: exitStatus,
            executionStatus: event.exitCode === 0 ? 'completed' : 'failed',
            summary: exitSummary,
            error: event.exitCode === 0 ? undefined : exitSummary
          });
          if (updated.parentAgentId) {
            postBusMessageAndNotify({
              runId,
              fromAgentId: agentId,
              toAgentId: updated.parentAgentId,
              type: event.exitCode === 0 ? 'HANDOFF_READY' : 'BLOCKED',
              payload:
                event.exitCode === 0
                  ? {
                      executionId: launchPlan.executionId,
                      summary: exitSummary,
                      transcriptFile: launchPlan.transcriptFile,
                      responseFile: launchPlan.responseFile
                    }
                  : {
                      executionId: launchPlan.executionId,
                      reason: exitSummary,
                      responseFile: launchPlan.responseFile
                    },
              requiresAck: true
            });
          }
          emitTaskLog(runId, `${event.exitCode === 0 ? 'HANDOFF_READY' : 'AGENT_FAILED'}: ${agentId} — ${exitSummary}`);
        }
        syncTaskFromRun(runId);
        drainLaunchQueue();
      }
    }
  );

  syncTaskFromRun(runId);
}

async function launchWorkerNow(runId: string, agentId: string, dryRun: boolean, reason: string): Promise<void> {
  const key = routeKey(runId, agentId);
  if (runningControllers.has(key) || sessionManager.has(runId, agentId)) {
    return;
  }

  try {
    const { envelope } = launchEnvelopeFromRun(runId, agentId);
    if (supportsInteractiveRuntimeLaunch(PROJECT_ROOT, envelope)) {
      await launchWorkerSessionNow(runId, agentId, dryRun, reason);
      return;
    }
  } catch (error) {
    emitTaskLog(
      runId,
      `LIVE_SESSION_FALLBACK: ${agentId} — ${error instanceof Error ? error.message : String(error)}`
    );
    // Fall back to one-shot execution path so the worker still records an actionable failure.
  }

  const controller = new AbortController();
  runningControllers.set(key, controller);
  emitTaskLog(runId, `LAUNCH_WORKER: ${agentId} — ${reason}`);
  syncTaskFromRun(runId);

  try {
    const result = await executeWorker(PROJECT_ROOT, {
      runId,
      agentId,
      dryRun,
      signal: controller.signal
    });
    emitTaskLog(runId, `${result.execution.status === 'completed' ? 'HANDOFF_READY' : 'AGENT_FAILED'}: ${agentId} — ${result.execution.summary}`);
  } catch (error) {
    if (controller.signal.aborted) {
      terminateWorker(PROJECT_ROOT, {
        runId,
        agentId,
        reason: 'Worker aborted by harness operator'
      });
      emitTaskLog(runId, `AGENT_TERMINATED: ${agentId}`);
    } else {
      setWorkerStatus(PROJECT_ROOT, {
        runId,
        agentId,
        status: 'failed',
        summary: 'Worker execution failed before completion',
        error: error instanceof Error ? error.message : String(error),
        executionStatus: 'failed'
      });
      emitTaskLog(runId, `AGENT_FAILED: ${agentId} — ${error instanceof Error ? error.message : String(error)}`);
    }
  } finally {
    runningControllers.delete(key);
    syncTaskFromRun(runId);
    drainLaunchQueue();
  }
}

function drainLaunchQueue(): void {
  let snapshot = governorSnapshot();
  while (queue.length && snapshot.canSpawnNow) {
    const next = queue.shift();
    if (!next) {
      break;
    }
    emitTaskLog(next.runId, `DEQUEUE_WORKER: ${next.agentId}`);
    void launchWorkerNow(next.runId, next.agentId, next.dryRun, next.reason);
    snapshot = governorSnapshot();
  }
}

function parseJsonBody<T>(req: IncomingMessage): Promise<T> {
  return new Promise((resolve, reject) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      if (!body.trim()) {
        resolve({} as T);
        return;
      }
      try {
        resolve(JSON.parse(body) as T);
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function sendSseHeaders(res: ServerResponse): void {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
}

function busRunStatus(run: RunState): Record<string, unknown> {
  const snapshot = governorSnapshot();
  const runtimeBreakdown = summarizeCounts(run.workers.map((worker) => worker.runtime));
  const roleBreakdown = summarizeCounts(run.workers.map((worker) => worker.role));
  const activeStatuses = new Set(['spawn_requested', 'planned', 'queued', 'running']);
  const completedStatuses = new Set(['completed', 'terminated']);

  return {
    runId: run.runId,
    totalMessages: run.messages.length,
    workers: Object.fromEntries(
      run.workers.map((worker) => [
        worker.agentId,
        {
          status: toBusWorkerStatus(worker.status),
          progressPct: progressForStatus(worker.status),
          lastHeartbeat: worker.updatedAt,
          currentTask: worker.taskSummary,
          worktreePath: worker.worktree,
          runtime: worker.runtime,
          role: worker.role,
          personaId: worker.persona.personaId,
          launchTransport: worker.launchTransport,
          executionStatus: worker.execution.status,
          lastSummary: worker.execution.lastSummary || null
        }
      ])
    ),
    activeLocks: {},
    telemetry: {
      coordinatorRuntime: run.coordinatorRuntime,
      totalWorkers: run.workers.length,
      activeWorkers: run.workers.filter((worker) => activeStatuses.has(worker.status)).length,
      queuedWorkers: run.workers.filter((worker) => worker.status === 'queued').length,
      completedWorkers: run.workers.filter((worker) => completedStatuses.has(worker.status)).length,
      failedWorkers: run.workers.filter((worker) => ['failed', 'blocked'].includes(worker.status)).length,
      handoffReadyWorkers: run.workers.filter((worker) => worker.status === 'handoff_ready').length,
      activeLocks: 0,
      totalMessages: run.messages.length,
      delegationCount: run.delegationDecisions.filter((decision) => decision.status === 'approved').length,
      runtimeBreakdown,
      roleBreakdown,
      governorAllowedAgents: snapshot.allowedAgents,
      governorActiveWorkers: snapshot.activeWorkers,
      governorQueuedWorkers: snapshot.queuedWorkers,
      updatedAt: run.updatedAt
    }
  };
}

function busMessageEnvelope(message: ReturnType<typeof listRunMessages>[number]): Record<string, unknown> {
  const payload = { ...message.payload, toId: message.toAgentId };
  return {
    id: message.messageId,
    type: message.type === 'SYSTEM' ? 'AGENT_MSG' : message.type,
    agentId: message.fromAgentId,
    runId: message.runId,
    timestamp: message.timestamp,
    payload
  };
}

function fileTree(rootPath: string): Record<string, unknown> {
  if (!fs.existsSync(rootPath)) {
    throw new Error('Worktree not found');
  }

  const files: Array<Record<string, unknown>> = [];
  let totalSize = 0;
  const queue: Array<{ dirPath: string; depth: number }> = [{ dirPath: rootPath, depth: 0 }];
  const ignored = new Set(['.git', 'node_modules']);

  while (queue.length && files.length < 500) {
    const current = queue.shift();
    if (!current) {
      break;
    }

    const entries = fs
      .readdirSync(current.dirPath, { withFileTypes: true })
      .filter((entry) => !ignored.has(entry.name))
      .sort((left, right) => Number(right.isDirectory()) - Number(left.isDirectory()) || left.name.localeCompare(right.name));

    for (const entry of entries) {
      const entryPath = path.join(current.dirPath, entry.name);
      const stat = fs.statSync(entryPath);
      totalSize += entry.isDirectory() ? 0 : stat.size;
      files.push({
        name: entry.name,
        relativePath: entryPath,
        size: entry.isDirectory() ? 0 : stat.size,
        modifiedAt: stat.mtime.toISOString(),
        isDir: entry.isDirectory(),
        depth: current.depth + 1
      });
      if (entry.isDirectory()) {
        queue.push({ dirPath: entryPath, depth: current.depth + 1 });
      }
      if (files.length >= 500) {
        break;
      }
    }
  }

  return {
    path: rootPath,
    files,
    totalFiles: files.length,
    totalSize
  };
}

function buildRunRecord(body: TaskPayload, runId: string, mode: DispatchMode): ServerTaskRecord {
  const coordinatorRuntime = inferRuntime(body);
  return {
    runId,
    task: body.task,
    mode,
    source: body.source || 'console',
    coordinator: coordinatorRuntime,
    model: body.model || body.coordinatorModel || body.workerModel,
    coordinatorProvider: body.coordinatorProvider,
    coordinatorModel: body.coordinatorModel || body.model,
    workerBackend: body.workerBackend || 'kimi',
    workerModel: body.workerModel || body.model,
    dispatchPath: body.dispatchPath || body.workerBackend || 'kimi',
    status: 'accepted',
    prUrl: null,
    startedAt: nowIso(),
    updatedAt: nowIso(),
    completedAt: null,
    durationMs: null,
    log: []
  };
}

function spawnSwarm(body: TaskPayload, runId: string, dryRun = false): { runId: string; coordinatorAgentId: string } {
  const coordinatorSelection = selectCoordinatorRuntime(PROJECT_ROOT, coordinatorRuntimeHint(body));
  const coordinatorRuntime = coordinatorSelection.selected;
  const coordinatorPersona = buildPersonaPacket(PROJECT_ROOT, defaultPersonaIdForRole('coordinator'));
  const coordinatorAgentId = 'coordinator-1';
  const coordinatorWorktree = ensureWorkerWorktree(PROJECT_ROOT, runId, coordinatorAgentId);

  spawnWorker(PROJECT_ROOT, {
    runId,
    runtime: coordinatorRuntime,
    agentId: coordinatorAgentId,
    role: 'coordinator',
    taskSummary: body.task,
    persona: coordinatorPersona,
    toolBundle: ['filesystem', 'gg-skills'],
    worktree: coordinatorWorktree
  });
  emitTaskLog(runId, `SPAWN_COORDINATOR: ${coordinatorAgentId}`);
  emitTaskLog(runId, `COORDINATOR_SELECTION: ${coordinatorRuntime} — ${coordinatorSelection.reason}`);

  const childRuntime = inferChildRuntime(body);
  const roles = buildRolePlan(body);
  let builderIndex = 0;

  for (const role of roles) {
    const persona = buildPersonaPacket(PROJECT_ROOT, defaultPersonaIdForRole(role));
    builderIndex += 1;
    const agentId = `${role}-${builderIndex}`;
    let decisionWorkerId: string | null = null;

    try {
      const worktree = ensureWorkerWorktree(PROJECT_ROOT, runId, agentId);
      const decision = delegateTask(PROJECT_ROOT, {
        runId,
        fromAgentId: coordinatorAgentId,
        agentId,
        toRuntime: childRuntime,
        role,
        taskSummary: `${body.task}\n\nFocus: ${role} lane`,
        classification: classificationFromMode(normalizeDispatchMode(body.mode)),
        persona,
        boardApproved: false,
        toolBundle: ['filesystem', 'gg-skills'],
        worktree
      } as any);

      if (decision.worker) {
        decisionWorkerId = decision.worker.agentId;
        emitTaskLog(runId, `SPAWN_WORKER: ${decisionWorkerId} parent:${coordinatorAgentId}`);
        postMessage(PROJECT_ROOT, {
          runId,
          fromAgentId: coordinatorAgentId,
          toAgentId: decisionWorkerId,
          type: 'TASK_SPEC',
          payload: {
            message: `${role} worker assigned`,
            role,
            summary: `${body.task}\n\nFocus: ${role} lane`
          },
          requiresAck: true
        });
      } else {
        emitTaskLog(runId, `DELEGATION_BLOCKED: ${role} — ${decision.decision.rationale}`);
      }
    } catch (error) {
      emitTaskLog(runId, `SPAWN_FAILED: ${agentId} — ${error instanceof Error ? error.message : String(error)}`);
    }

    if (decisionWorkerId) {
      scheduleWorkerLaunch(runId, decisionWorkerId, `initial ${role} dispatch`, dryRun);
    }
  }

  scheduleWorkerLaunch(runId, coordinatorAgentId, 'initial coordinator launch', dryRun);
  syncTaskFromRun(runId);
  return { runId, coordinatorAgentId };
}

async function startQualityJob(projectRoot: string, tools: string[], profile: string): Promise<QualityJobRecord> {
  const job: QualityJobRecord = {
    id: nextId('quality'),
    status: 'running',
    tools,
    profile,
    startedAt: nowIso(),
    completedAt: null,
    exitCode: null,
    output: [],
    failures: []
  };
  writeQualityJob(projectRoot, job);

  const commands: Array<{ label: string; command: string; args: string[] }> = [];
  if (tools.includes('lint')) {
    commands.push({ label: 'lint', command: 'npm', args: ['run', 'lint'] });
  }
  if (tools.includes('type-check') || tools.includes('typecheck')) {
    commands.push({ label: 'type-check', command: 'npm', args: ['run', 'type-check'] });
  }
  if (tools.includes('test')) {
    commands.push({ label: 'test', command: 'npm', args: ['test'] });
  }
  if (tools.includes('build')) {
    commands.push({ label: 'build', command: 'npm', args: ['run', 'build'] });
  }
  if (!commands.length) {
    job.status = 'completed';
    job.completedAt = nowIso();
    job.exitCode = 0;
    job.output.push('No executable quality tools were requested; recorded configuration only.');
    return writeQualityJob(projectRoot, job);
  }

  for (const entry of commands) {
    const result = spawnSync(entry.command, entry.args, {
      cwd: projectRoot,
      encoding: 'utf8'
    });
    job.output.push(`$ ${entry.command} ${entry.args.join(' ')}`);
    if (result.stdout.trim()) {
      job.output.push(result.stdout.trim());
    }
    if (result.stderr.trim()) {
      job.output.push(result.stderr.trim());
    }
    if (result.status !== 0) {
      job.failures.push({
        tool: entry.label,
        message: (result.stderr || result.stdout || `Command failed: ${entry.command}`).trim()
      });
      job.status = 'failed';
      job.exitCode = result.status;
      job.completedAt = nowIso();
      return writeQualityJob(projectRoot, job);
    }
  }

  job.status = 'completed';
  job.exitCode = 0;
  job.completedAt = nowIso();
  return writeQualityJob(projectRoot, job);
}

function readSkillStats(projectRoot: string): Array<{
  skill: string;
  type: string;
  calls: number;
  failures: number;
  avgDurationMs: number | null;
  lastUsed: string | null;
}> {
  const runsDir = path.join(projectRoot, '.agent', 'runs');
  if (!fs.existsSync(runsDir)) {
    return [];
  }

  const aggregate = new Map<
    string,
    {
      skill: string;
      type: string;
      calls: number;
      failures: number;
      totalDurationMs: number;
      durationCount: number;
      lastUsed: string | null;
    }
  >();

  for (const entry of fs.readdirSync(runsDir)) {
    if (!entry.endsWith('.json')) {
      continue;
    }
    const filePath = path.join(runsDir, entry);
    try {
      const payload = JSON.parse(fs.readFileSync(filePath, 'utf8')) as Record<string, unknown>;
      const matchedSkills = Array.isArray(payload.matchedSkills)
        ? payload.matchedSkills.filter((value): value is string => typeof value === 'string')
        : [];
      const selectedSkills = Array.isArray(payload.selectedSkills)
        ? payload.selectedSkills.filter((value): value is string => typeof value === 'string')
        : [];
      const skills = new Set([...matchedSkills, ...selectedSkills]);
      if (!skills.size) {
        continue;
      }

      const status = String(payload.status || '').toLowerCase();
      const failed = status === 'failed' || status === 'cancelled';
      const durationMs = typeof payload.durationMs === 'number' ? payload.durationMs : null;
      const lastUsed =
        typeof payload.completedAt === 'string'
          ? payload.completedAt
          : typeof payload.createdAt === 'string'
            ? payload.createdAt
            : null;

      for (const skill of skills) {
        const existing = aggregate.get(skill) || {
          skill,
          type: skill.includes('-') ? skill.split('-')[0] || 'skill' : 'skill',
          calls: 0,
          failures: 0,
          totalDurationMs: 0,
          durationCount: 0,
          lastUsed: null
        };
        existing.calls += 1;
        if (failed) {
          existing.failures += 1;
        }
        if (durationMs !== null) {
          existing.totalDurationMs += durationMs;
          existing.durationCount += 1;
        }
        if (lastUsed && (!existing.lastUsed || lastUsed > existing.lastUsed)) {
          existing.lastUsed = lastUsed;
        }
        aggregate.set(skill, existing);
      }
    } catch {
      continue;
    }
  }

  return Array.from(aggregate.values())
    .map((entry) => ({
      skill: entry.skill,
      type: entry.type,
      calls: entry.calls,
      failures: entry.failures,
      avgDurationMs: entry.durationCount ? entry.totalDurationMs / entry.durationCount : null,
      lastUsed: entry.lastUsed
    }))
    .sort((left, right) => right.calls - left.calls || left.skill.localeCompare(right.skill));
}

function readAgentAnalytics(projectRoot: string): {
  summary: {
    totalRuns: number;
    totalWorkers: number;
    activeWorkers: number;
    failedWorkers: number;
    distinctPersonas: number;
    distinctRuntimes: number;
    lastUpdatedAt: string | null;
  };
  coordinators: Array<{
    key: string;
    label: string;
    type: string;
    calls: number;
    failures: number;
    active: number;
    avgDurationMs: number | null;
    lastUsed: string | null;
  }>;
  workerRuntimes: Array<{
    key: string;
    label: string;
    type: string;
    calls: number;
    failures: number;
    active: number;
    avgDurationMs: number | null;
    lastUsed: string | null;
  }>;
  personas: Array<{
    key: string;
    label: string;
    type: string;
    calls: number;
    failures: number;
    active: number;
    avgDurationMs: number | null;
    lastUsed: string | null;
  }>;
  roles: Array<{
    key: string;
    label: string;
    type: string;
    calls: number;
    failures: number;
    active: number;
    avgDurationMs: number | null;
    lastUsed: string | null;
  }>;
} {
  type AggregateEntry = {
    key: string;
    label: string;
    type: string;
    calls: number;
    failures: number;
    active: number;
    totalDurationMs: number;
    durationCount: number;
    lastUsed: string | null;
  };

  const runs = listRunStates(projectRoot);
  const coordinators = new Map<string, AggregateEntry>();
  const workerRuntimes = new Map<string, AggregateEntry>();
  const personas = new Map<string, AggregateEntry>();
  const roles = new Map<string, AggregateEntry>();

  const activeStatuses = new Set(['spawn_requested', 'planned', 'queued', 'running']);
  const failedStatuses = new Set(['failed', 'blocked']);
  const personaSet = new Set<string>();
  const runtimeSet = new Set<string>();
  let totalWorkers = 0;
  let activeWorkers = 0;
  let failedWorkers = 0;
  let lastUpdatedAt: string | null = null;

  const ingest = (
    map: Map<string, AggregateEntry>,
    key: string,
    label: string,
    type: string,
    failed: boolean,
    active: boolean,
    lastUsed: string | null,
    durationMs: number | null
  ) => {
    const existing = map.get(key) || {
      key,
      label,
      type,
      calls: 0,
      failures: 0,
      active: 0,
      totalDurationMs: 0,
      durationCount: 0,
      lastUsed: null
    };
    existing.calls += 1;
    if (failed) {
      existing.failures += 1;
    }
    if (active) {
      existing.active += 1;
    }
    if (durationMs !== null) {
      existing.totalDurationMs += durationMs;
      existing.durationCount += 1;
    }
    if (lastUsed && (!existing.lastUsed || lastUsed > existing.lastUsed)) {
      existing.lastUsed = lastUsed;
    }
    map.set(key, existing);
  };

  for (const run of runs) {
    const runFailed = run.workers.some((worker) => failedStatuses.has(worker.status));
    const runActive = run.workers.some((worker) => activeStatuses.has(worker.status));
    const runLastUsed = run.updatedAt || run.createdAt;
    const runDurationMs = Math.max(0, Date.parse(run.updatedAt) - Date.parse(run.createdAt));
    ingest(
      coordinators,
      run.coordinatorRuntime,
      humanizeKey(run.coordinatorRuntime),
      'coordinator',
      runFailed,
      runActive,
      runLastUsed,
      Number.isFinite(runDurationMs) ? runDurationMs : null
    );

    if (runLastUsed && (!lastUpdatedAt || runLastUsed > lastUpdatedAt)) {
      lastUpdatedAt = runLastUsed;
    }

    for (const worker of run.workers) {
      totalWorkers += 1;
      runtimeSet.add(worker.runtime);
      personaSet.add(worker.persona.personaId);
      const active = activeStatuses.has(worker.status);
      const failed = failedStatuses.has(worker.status);
      if (active) {
        activeWorkers += 1;
      }
      if (failed) {
        failedWorkers += 1;
      }

      const workerLastUsed = worker.updatedAt || run.updatedAt || run.createdAt;
      const workerDurationMs =
        worker.execution.lastStartedAt && worker.execution.lastCompletedAt
          ? Math.max(0, Date.parse(worker.execution.lastCompletedAt) - Date.parse(worker.execution.lastStartedAt))
          : null;

      ingest(workerRuntimes, worker.runtime, humanizeKey(worker.runtime), 'worker-runtime', failed, active, workerLastUsed, workerDurationMs);
      ingest(personas, worker.persona.personaId, worker.persona.personaId, 'persona', failed, active, workerLastUsed, workerDurationMs);
      ingest(roles, worker.role, humanizeKey(worker.role), 'role', failed, active, workerLastUsed, workerDurationMs);
    }
  }

  const finalize = (map: Map<string, AggregateEntry>) =>
    Array.from(map.values())
      .map((entry) => ({
        key: entry.key,
        label: entry.label,
        type: entry.type,
        calls: entry.calls,
        failures: entry.failures,
        active: entry.active,
        avgDurationMs: entry.durationCount ? entry.totalDurationMs / entry.durationCount : null,
        lastUsed: entry.lastUsed
      }))
      .sort((left, right) => right.calls - left.calls || left.label.localeCompare(right.label));

  return {
    summary: {
      totalRuns: runs.length,
      totalWorkers,
      activeWorkers,
      failedWorkers,
      distinctPersonas: personaSet.size,
      distinctRuntimes: runtimeSet.size,
      lastUpdatedAt
    },
    coordinators: finalize(coordinators),
    workerRuntimes: finalize(workerRuntimes),
    personas: finalize(personas),
    roles: finalize(roles)
  };
}

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const method = req.method || 'GET';
  const url = new URL(req.url || '/', `http://${req.headers.host || '127.0.0.1'}`);
  const pathname = url.pathname;

  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  if (method === 'OPTIONS') {
    noContent(res);
    return;
  }

  try {
    if (pathname === '/health') {
      json(res, 200, {
        status: 'ok',
        port: DEFAULT_PORT,
        projectRoot: PROJECT_ROOT,
        uptime: process.uptime(),
        controlPlane: controlPlaneMeta()
      });
      return;
    }

    if (pathname === '/api/meta') {
      json(res, 200, controlPlaneMeta());
      return;
    }

    if (pathname === '/api/status') {
      const tasks = listTaskRecords(PROJECT_ROOT);
      const snapshot = governorSnapshot();
      const codexDiscovery = discoverRuntimeCredentials(PROJECT_ROOT, 'codex');
      const claudeDiscovery = discoverRuntimeCredentials(PROJECT_ROOT, 'claude');
      const kimiDiscovery = discoverRuntimeCredentials(PROJECT_ROOT, 'kimi');
      json(res, 200, {
        codex: {
          available: codexDiscovery.authenticated,
          path: codexDiscovery.binaryPath,
          runningAcp: activeWorkerCountByRuntime('codex')
        },
        kimi: {
          available: kimiDiscovery.authenticated,
          path: kimiDiscovery.binaryPath || (kimiDiscovery.directApiAvailable ? 'provider-api' : null),
          runningAcp: activeWorkerCountByRuntime('kimi')
        },
        claude: {
          available: claudeDiscovery.authenticated,
          path: claudeDiscovery.binaryPath,
          runningAcp: activeWorkerCountByRuntime('claude')
        },
        pool: {
          total: snapshot.allowedAgents,
          active: snapshot.activeWorkers,
          idle: Math.max(0, snapshot.allowedAgents - snapshot.activeWorkers)
        },
        runs: {
          total: tasks.length,
          running: tasks.filter((entry) => entry.status === 'running').length
        },
        controlPlane: controlPlaneMeta(),
        governor: snapshot,
        uptime: process.uptime()
      });
      return;
    }

    if (pathname === '/api/runtime-discovery' && method === 'GET') {
      const runtimeDiscoveries = ['codex', 'claude', 'kimi'].map((runtime) =>
        discoverRuntimeCredentials(PROJECT_ROOT, runtime as 'codex' | 'claude' | 'kimi')
      );
      const discoveries = [...runtimeDiscoveries, ...buildAntigravityProviderDiscoveries()];
      const selection = selectCoordinatorRuntime(PROJECT_ROOT, null);
      json(res, 200, {
        coordinatorSelection: selection,
        discoveries
      });
      return;
    }

    if (pathname === '/api/governor/status') {
      json(res, 200, governorSnapshot());
      return;
    }

    if (pathname === '/api/runs' && method === 'GET') {
      const runs = listTaskRecords(PROJECT_ROOT);
      json(res, 200, { runs });
      return;
    }

    if (pathname === '/api/runs/register' && method === 'POST') {
      const body = await parseJsonBody<Partial<ServerTaskRecord>>(req);
      if (!body.runId || !body.task) {
        json(res, 400, { error: 'runId and task are required' });
        return;
      }
      const record = writeTaskRecord(PROJECT_ROOT, {
        runId: body.runId,
        task: body.task,
        mode: body.mode || 'minion',
        source: body.source || 'register',
        coordinator: body.coordinator,
        model: body.model,
        coordinatorProvider: body.coordinatorProvider,
        coordinatorModel: body.coordinatorModel,
        workerBackend: body.workerBackend,
        workerModel: body.workerModel,
        dispatchPath: body.dispatchPath,
        status: body.status || 'accepted',
        prUrl: body.prUrl || null,
        startedAt: body.startedAt || nowIso(),
        updatedAt: nowIso(),
        completedAt: body.completedAt || null,
        durationMs: body.durationMs || null,
        log: body.log || []
      });
      emitRunEvent({
        type: 'run_created',
        runId: record.runId,
        status: record.status,
        coordinator: record.coordinator,
        model: record.model,
        coordinatorProvider: record.coordinatorProvider,
        coordinatorModel: record.coordinatorModel,
        workerBackend: record.workerBackend,
        workerModel: record.workerModel,
        dispatchPath: record.dispatchPath,
        task: record.task
      });
      json(res, 200, record);
      return;
    }

    if (pathname === '/api/events' && method === 'GET') {
      sendSseHeaders(res);
      eventSubscribers.add(res);
      res.write(`data: ${JSON.stringify({ type: 'snapshot', runs: listTaskRecords(PROJECT_ROOT), ts: nowIso() })}\n\n`);
      req.on('close', () => {
        eventSubscribers.delete(res);
      });
      return;
    }

    if (pathname === '/api/task' && method === 'POST') {
      const body = await parseJsonBody<TaskPayload>(req);
      if (!body.task || !body.task.trim()) {
        json(res, 400, { error: '"task" is required' });
        return;
      }

      const runId = nextId('run');
      const mode = normalizeDispatchMode(body.mode);
      const runtime = inferRuntime(body);
      createRunState(PROJECT_ROOT, {
        runId,
        summary: body.task,
        classification: classificationFromMode(mode),
        coordinatorRuntime: runtime
      });

      const record = writeTaskRecord(PROJECT_ROOT, buildRunRecord(body, runId, mode));
      emitTaskLog(runId, `[harness] Task accepted: ${body.task}`);
      emitRunEvent({
        type: 'run_created',
        runId,
        status: 'accepted',
        coordinator: record.coordinator,
        model: record.model,
        coordinatorProvider: record.coordinatorProvider,
        coordinatorModel: record.coordinatorModel,
        workerBackend: record.workerBackend,
        workerModel: record.workerModel,
        dispatchPath: record.dispatchPath,
        task: record.task
      });

      spawnSwarm(body, runId, Boolean(process.env.HARNESS_DRY_RUN === '1'));

      json(res, 202, {
        runId,
        status: 'accepted',
        mode,
        coordinator: record.coordinator,
        model: record.model,
        coordinatorProvider: record.coordinatorProvider,
        coordinatorModel: record.coordinatorModel,
        workerBackend: record.workerBackend,
        workerModel: record.workerModel,
        dispatchPath: record.dispatchPath,
        stream: `/api/task/${runId}/stream`,
        poll: `/api/task/${runId}`
      });
      return;
    }

    const taskMatch = pathname.match(/^\/api\/task\/([^/]+)$/);
    if (taskMatch && method === 'GET') {
      const runId = decodeURIComponent(taskMatch[1] || '');
      const record = syncTaskFromRun(runId) || readTaskRecord(PROJECT_ROOT, runId);
      if (!record) {
        json(res, 404, { error: 'Run not found' });
        return;
      }
      json(res, 200, record);
      return;
    }

    if (taskMatch && method === 'DELETE') {
      const runId = decodeURIComponent(taskMatch[1] || '');
      try {
        const run = readRunState(PROJECT_ROOT, runId);
        for (const worker of run.workers) {
          const controller = runningControllers.get(routeKey(runId, worker.agentId));
          controller?.abort();
          sessionManager.terminate(runId, worker.agentId);
          terminateWorker(PROJECT_ROOT, {
            runId,
            agentId: worker.agentId,
            reason: 'Run cancelled by operator'
          });
        }
      } catch {
        // Metadata-only runs can still be cancelled.
      }
      const task = syncTaskFromRun(runId);
      emitTaskLog(runId, '[harness] Run cancelled by API request');
      json(res, 200, { runId, status: task?.status || 'cancelled' });
      return;
    }

    const taskLogMatch = pathname.match(/^\/api\/task\/([^/]+)\/log$/);
    if (taskLogMatch && method === 'GET') {
      const runId = decodeURIComponent(taskLogMatch[1] || '');
      const task = readTaskRecord(PROJECT_ROOT, runId);
      if (!task) {
        json(res, 404, { error: 'Run not found' });
        return;
      }
      json(res, 200, { runId, log: task.log });
      return;
    }

    if (taskLogMatch && method === 'POST') {
      const runId = decodeURIComponent(taskLogMatch[1] || '');
      const body = await parseJsonBody<{ log?: string[]; status?: ServerTaskRecord['status'] }>(req);
      const task = readTaskRecord(PROJECT_ROOT, runId);
      if (!task) {
        json(res, 404, { error: 'Run not found' });
        return;
      }
      for (const line of body.log || []) {
        emitTaskLog(runId, line);
      }
      if (body.status) {
        writeTaskRecord(PROJECT_ROOT, { ...task, status: body.status });
      }
      json(res, 200, { runId, appended: (body.log || []).length, status: body.status || task.status });
      return;
    }

    const taskStreamMatch = pathname.match(/^\/api\/task\/([^/]+)\/stream$/);
    if (taskStreamMatch && method === 'GET') {
      const runId = decodeURIComponent(taskStreamMatch[1] || '');
      const task = readTaskRecord(PROJECT_ROOT, runId);
      if (!task) {
        json(res, 404, { error: 'Run not found' });
        return;
      }
      sendSseHeaders(res);
      taskLogSubscribers.set(runId, (taskLogSubscribers.get(runId) || new Set()).add(res));
      task.log.forEach((line, index) => {
        const logLine = taskLogEnvelope(runId, line, task.updatedAt || task.startedAt, `${runId}-${index}`);
        res.write(`data: ${JSON.stringify({ line, logLine })}\n\n`);
      });
      req.on('close', () => {
        taskLogSubscribers.get(runId)?.delete(res);
      });
      return;
    }

    if (pathname === '/api/logs/stream' && method === 'GET') {
      sendSseHeaders(res);
      for (const line of recentTaskLogEnvelopes()) {
        res.write(`data: ${JSON.stringify({ line })}\n\n`);
      }
      liveLogSubscribers.add(res);
      req.on('close', () => {
        liveLogSubscribers.delete(res);
      });
      req.on('aborted', () => {
        liveLogSubscribers.delete(res);
      });
      return;
    }

    if (pathname === '/api/bus' && method === 'GET') {
      const runs = listRunStates(PROJECT_ROOT).map((run) => ({
        runId: run.runId,
        agents: run.workers.length,
        startedAt: run.createdAt
      }));
      json(res, 200, { runs });
      return;
    }

    const busStatusMatch = pathname.match(/^\/api\/bus\/([^/]+)\/status$/);
    if (busStatusMatch && method === 'GET') {
      const runId = decodeURIComponent(busStatusMatch[1] || '');
      const run = readRunState(PROJECT_ROOT, runId);
      json(res, 200, busRunStatus(run));
      return;
    }

    const busStreamMatch = pathname.match(/^\/api\/bus\/([^/]+)\/stream$/);
    if (busStreamMatch && method === 'GET') {
      const runId = decodeURIComponent(busStreamMatch[1] || '');
      const messages = listRunMessages(PROJECT_ROOT, runId);
      sendSseHeaders(res);
      for (const message of messages) {
        res.write(`data: ${JSON.stringify({ event: 'bus_message', message: busMessageEnvelope(message), runId })}\n\n`);
      }
      busSubscriberSet(runId).add(res);
      req.on('close', () => {
        busSubscribers.get(runId)?.delete(res);
      });
      req.on('aborted', () => {
        busSubscribers.get(runId)?.delete(res);
      });
      return;
    }

    const workerStreamMatch = pathname.match(/^\/api\/workers\/([^/]+)\/([^/]+)\/stream$/);
    if (workerStreamMatch && method === 'GET') {
      const runId = decodeURIComponent(workerStreamMatch[1] || '');
      const agentId = decodeURIComponent(workerStreamMatch[2] || '');
      sendSseHeaders(res);
      workerSubscriberSet(runId, agentId).add(res);
      req.on('close', () => {
        workerStreamSubscribers.get(routeKey(runId, agentId))?.delete(res);
      });
      req.on('aborted', () => {
        workerStreamSubscribers.get(routeKey(runId, agentId))?.delete(res);
      });
      return;
    }

    if (pathname === '/api/escalations' && method === 'GET') {
      const escalations = listRunStates(PROJECT_ROOT)
        .flatMap((run) =>
          run.messages
            .filter((message) => message.type === 'BLOCKED' || message.type === 'DELEGATE_REQUEST')
            .map((message) => ({
              id: message.messageId,
              runId: run.runId,
              fromDomain: message.fromAgentId,
              targetDomain: message.toAgentId,
              finding: String(message.payload.reason || message.payload.message || message.type),
              severity: message.type === 'BLOCKED' ? 'high' : 'medium',
              timestamp: message.timestamp
            }))
        )
        .sort((left, right) => right.timestamp.localeCompare(left.timestamp));
      json(res, 200, { escalations });
      return;
    }

    if (pathname === '/api/skill-stats' && method === 'GET') {
      json(res, 200, { stats: readSkillStats(PROJECT_ROOT) });
      return;
    }

    if (pathname === '/api/agent-analytics' && method === 'GET') {
      json(res, 200, readAgentAnalytics(PROJECT_ROOT));
      return;
    }

    if (pathname === '/api/planner' && method === 'GET') {
      json(res, 200, readPlannerSnapshot(PROJECT_ROOT));
      return;
    }

    if (pathname === '/api/planner/tasks' && method === 'GET') {
      const snapshot = readPlannerSnapshot(PROJECT_ROOT);
      const status = url.searchParams.get('status');
      const projectId = url.searchParams.get('projectId');
      const tasks = snapshot.tasks.filter((task) => {
        if (status && task.status !== status) {
          return false;
        }
        if (projectId && task.projectId !== projectId) {
          return false;
        }
        return true;
      });
      json(res, 200, { tasks });
      return;
    }

    if (pathname === '/api/planner/tasks' && method === 'POST') {
      const body = await parseJsonBody<PlannerTaskRequestBody>(req);
      if (!body.title || !body.title.trim()) {
        json(res, 400, { error: 'title is required' });
        return;
      }
      const task = createPlannerTask(PROJECT_ROOT, {
        projectId: body.projectId,
        title: body.title,
        description: body.description,
        status: body.status as PlannerTaskInput['status'],
        priority: body.priority,
        source: body.source,
        sourceSession: body.sourceSession,
        labels: body.labels,
        attachments: body.attachments,
        isGlobal: body.isGlobal,
        runId: body.runId,
        runtime: body.runtime,
        linkedRunStatus: body.linkedRunStatus,
        assignedAgentId: body.assignedAgentId,
        worktreePath: body.worktreePath
      });
      json(res, 201, { task, snapshot: readPlannerSnapshot(PROJECT_ROOT) });
      return;
    }

    const plannerTaskMatch = pathname.match(/^\/api\/planner\/tasks\/([^/]+)$/);
    if (plannerTaskMatch && method === 'PATCH') {
      const taskId = decodeURIComponent(plannerTaskMatch[1] || '');
      const body = await parseJsonBody<PlannerTaskRequestBody>(req);
      const task = updatePlannerTask(PROJECT_ROOT, taskId, {
        title: body.title,
        description: body.description,
        status: body.status as PlannerTaskPatch['status'],
        priority: body.priority,
        source: body.source,
        sourceSession: body.sourceSession,
        labels: body.labels,
        attachments: body.attachments,
        isGlobal: body.isGlobal,
        runId: body.runId,
        runtime: body.runtime,
        linkedRunStatus: body.linkedRunStatus,
        assignedAgentId: body.assignedAgentId,
        worktreePath: body.worktreePath
      });
      json(res, 200, { task, snapshot: readPlannerSnapshot(PROJECT_ROOT) });
      return;
    }

    if (plannerTaskMatch && method === 'DELETE') {
      const taskId = decodeURIComponent(plannerTaskMatch[1] || '');
      deletePlannerTask(PROJECT_ROOT, taskId);
      json(res, 200, { ok: true, snapshot: readPlannerSnapshot(PROJECT_ROOT) });
      return;
    }

    if (pathname === '/api/planner/notes' && method === 'GET') {
      const snapshot = readPlannerSnapshot(PROJECT_ROOT);
      const taskId = url.searchParams.get('taskId');
      const projectId = url.searchParams.get('projectId');
      const notes = snapshot.notes.filter((note) => {
        if (taskId && note.taskId !== taskId) {
          return false;
        }
        if (projectId && note.projectId !== projectId) {
          return false;
        }
        return true;
      });
      json(res, 200, { notes });
      return;
    }

    if (pathname === '/api/planner/notes' && method === 'POST') {
      const body = await parseJsonBody<PlannerNoteRequestBody>(req);
      if (!body.content || !body.content.trim()) {
        json(res, 400, { error: 'content is required' });
        return;
      }
      const note = createPlannerNote(PROJECT_ROOT, {
        title: body.title,
        content: body.content,
        pinned: body.pinned,
        taskId: body.taskId,
        projectId: body.projectId,
        source: body.source
      } satisfies PlannerNoteInput);
      json(res, 201, { note, snapshot: readPlannerSnapshot(PROJECT_ROOT) });
      return;
    }

    const plannerNoteMatch = pathname.match(/^\/api\/planner\/notes\/([^/]+)$/);
    if (plannerNoteMatch && method === 'PATCH') {
      const noteId = decodeURIComponent(plannerNoteMatch[1] || '');
      const body = await parseJsonBody<PlannerNoteRequestBody>(req);
      const note = updatePlannerNote(PROJECT_ROOT, noteId, {
        title: body.title,
        content: body.content,
        pinned: body.pinned,
        taskId: body.taskId,
        projectId: body.projectId,
        source: body.source
      } satisfies PlannerNotePatch);
      json(res, 200, { note, snapshot: readPlannerSnapshot(PROJECT_ROOT) });
      return;
    }

    if (plannerNoteMatch && method === 'DELETE') {
      const noteId = decodeURIComponent(plannerNoteMatch[1] || '');
      deletePlannerNote(PROJECT_ROOT, noteId);
      json(res, 200, { ok: true, snapshot: readPlannerSnapshot(PROJECT_ROOT) });
      return;
    }

    if (pathname === '/api/usage' && method === 'GET') {
      json(res, 200, await collectUsageSnapshot());
      return;
    }

    if (pathname === '/api/replays/sources' && method === 'GET') {
      json(res, 200, { sources: listReplaySources() });
      return;
    }

    if (pathname === '/api/replays/sessions' && method === 'GET') {
      const limit = Number(url.searchParams.get('limit') || 100);
      json(res, 200, { sessions: await listReplaySessions(PROJECT_ROOT, Number.isFinite(limit) ? limit : 100) });
      return;
    }

    if (pathname === '/api/replays/render' && method === 'POST') {
      const body = await parseJsonBody<{ path?: string }>(req);
      if (!body.path) {
        json(res, 400, { error: 'path is required' });
        return;
      }
      json(res, 200, await renderReplay(PROJECT_ROOT, body.path));
      return;
    }

    if (pathname === '/api/replays/file' && method === 'GET') {
      const target = url.searchParams.get('path') || '';
      if (!target || !fs.existsSync(target)) {
        json(res, 404, { error: 'Replay file not found' });
        return;
      }
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.end(fs.readFileSync(target, 'utf8'));
      return;
    }

    if (pathname === '/api/model-fit/recommendations' && method === 'GET') {
      const limit = Number(url.searchParams.get('limit') || 12);
      json(res, 200, collectModelFitSnapshot(Number.isFinite(limit) ? limit : 12));
      return;
    }

    if (pathname === '/api/model-fit/system' && method === 'GET') {
      const snapshot = collectModelFitSnapshot(8);
      json(res, 200, {
        available: snapshot.available,
        binaryPath: snapshot.binaryPath,
        system: snapshot.system,
        error: snapshot.error
      });
      return;
    }

    if (pathname === '/api/model-fit/lmstudio-candidates' && method === 'GET') {
      const limit = Number(url.searchParams.get('limit') || 12);
      json(res, 200, {
        candidates: collectLMStudioCandidates(Number.isFinite(limit) ? limit : 12)
      });
      return;
    }

    if (pathname === '/api/free-models/providers' && method === 'GET') {
      json(res, 200, {
        providers: await collectFreeModelProviders(PROJECT_ROOT)
      });
      return;
    }

    if (pathname === '/api/free-models/catalog' && method === 'GET') {
      json(res, 200, await collectFreeModelsCatalog(PROJECT_ROOT));
      return;
    }

    if (pathname === '/api/integrations/settings' && method === 'GET') {
      json(res, 200, readIntegrationSettings(PROJECT_ROOT));
      return;
    }

    if (pathname === '/api/integrations/settings' && method === 'PUT') {
      const body = await parseJsonBody<IntegrationSettingsRecord>(req);
      json(res, 200, writeIntegrationSettings(PROJECT_ROOT, body));
      return;
    }

    if (pathname === '/api/integrations/mcp/catalog' && method === 'GET') {
      json(res, 200, readMcpCatalog(PROJECT_ROOT));
      return;
    }

    if (pathname === '/api/integrations/mcp/apply' && method === 'POST') {
      const body = await parseJsonBody<{ serverIds?: string[] }>(req);
      const settings = readIntegrationSettings(PROJECT_ROOT);
      settings.mcpCatalog.selectedServerIds = body.serverIds || [];
      writeIntegrationSettings(PROJECT_ROOT, settings);
      const catalog = builtInCatalog(PROJECT_ROOT);
      json(res, 200, {
        selectedServerIds: settings.mcpCatalog.selectedServerIds,
        appliedServers: catalog.servers
          .filter((entry) => settings.mcpCatalog.selectedServerIds.includes(entry.id))
          .map((entry) => entry.name),
        kimiConfigPath: settings.mcpCatalog.kimiConfigPath
      });
      return;
    }

    if (pathname === '/api/integrations/quality/jobs' && method === 'GET') {
      json(res, 200, { jobs: listQualityJobs(PROJECT_ROOT) });
      return;
    }

    const qualityJobMatch = pathname.match(/^\/api\/integrations\/quality\/jobs\/([^/]+)$/);
    if (qualityJobMatch && method === 'GET') {
      const job = readQualityJob(PROJECT_ROOT, decodeURIComponent(qualityJobMatch[1] || ''));
      if (!job) {
        json(res, 404, { error: 'Quality job not found' });
        return;
      }
      json(res, 200, job);
      return;
    }

    if (pathname === '/api/integrations/quality/run' && method === 'POST') {
      const body = await parseJsonBody<{ tools?: string[]; profile?: string }>(req);
      const settings = readIntegrationSettings(PROJECT_ROOT);
      const configuredRoot = settings.qualityTools.defaultProjectRoot || PROJECT_ROOT;
      const executionRoot = fs.existsSync(configuredRoot) ? path.resolve(configuredRoot) : PROJECT_ROOT;
      const job = await startQualityJob(executionRoot, body.tools || [], body.profile || 'default');
      json(res, 200, job);
      return;
    }

    if (pathname === '/api/worktree' && method === 'GET') {
      const target = url.searchParams.get('path') || '';
      if (!target || !fs.existsSync(target)) {
        json(res, 404, { error: 'Worktree not found' });
        return;
      }
      json(res, 200, fileTree(target));
      return;
    }

    const workerActionMatch = pathname.match(/^\/api\/workers\/([^/]+)\/([^/]+)\/(message|retry|retask|terminate)$/);
    if (workerActionMatch && method === 'POST') {
      const runId = decodeURIComponent(workerActionMatch[1] || '');
      const agentId = decodeURIComponent(workerActionMatch[2] || '');
      const action = workerActionMatch[3] || '';
      const body = await parseJsonBody<SteeringPayload>(req);

      if (action === 'message') {
        const response = postBusMessageAndNotify({
          runId,
          fromAgentId: 'operator',
          toAgentId: agentId,
          type: 'SYSTEM',
          payload: {
            message: body.message || body.summary || '',
            toId: agentId,
            from: 'operator'
          },
          requiresAck: true
        });
        const delivered = sessionManager.send(runId, agentId, formatOperatorGuidance(body.message || body.summary || ''));
        emitTaskLog(runId, `AGENT_MSG: operator → ${agentId} — ${body.message || body.summary || ''}`);
        json(res, 200, {
          status: delivered ? 'delivered' : 'queued',
          delivery: delivered ? 'live-session' : 'bus-only',
          messageId: response.message.messageId
        });
        return;
      }

      if (action === 'retry') {
        scheduleWorkerLaunch(runId, agentId, 'operator retry', Boolean(body.dryRun));
        json(res, 200, { status: 'queued', runId, agentId });
        return;
      }

      if (action === 'retask') {
        const taskSummary = body.taskSummary || body.summary || body.message;
        if (!taskSummary) {
          json(res, 400, { error: 'taskSummary, summary, or message is required' });
          return;
        }
        const updated = updateWorkerTask(PROJECT_ROOT, {
          runId,
          agentId,
          taskSummary
        });
        emitTaskLog(runId, `RETASK_WORKER: ${agentId} — ${taskSummary}`);
        scheduleWorkerLaunch(runId, agentId, 'operator retask', Boolean(body.dryRun));
        json(res, 200, { status: 'queued', worker: updated.worker });
        return;
      }

      if (action === 'terminate') {
        runningControllers.get(routeKey(runId, agentId))?.abort();
        sessionManager.terminate(runId, agentId);
        const result = terminateWorker(PROJECT_ROOT, {
          runId,
          agentId,
          reason: body.reason || 'Worker terminated by operator'
        });
        const latest = result.run.messages[result.run.messages.length - 1];
        if (latest) {
          emitBusMessage(runId, latest);
        }
        emitTaskLog(runId, `AGENT_TERMINATED: ${agentId}`);
        syncTaskFromRun(runId);
        json(res, 200, { status: 'terminated', worker: result.worker });
        return;
      }
    }

    json(res, 404, { error: `Route not found: ${method} ${pathname}` });
  } catch (error) {
    json(res, 500, {
      error: error instanceof Error ? error.message : String(error)
    });
  }
}

export function startControlPlaneServer(options?: { port?: number; projectRoot?: string }): http.Server {
  if (options?.projectRoot && path.resolve(options.projectRoot) !== PROJECT_ROOT) {
    throw new Error('PROJECT_ROOT environment variable must match the requested projectRoot');
  }

  ensureServerStore(PROJECT_ROOT);
  const server = http.createServer((req, res) => {
    void handleRequest(req, res);
  });

  server.listen(options?.port || DEFAULT_PORT, '127.0.0.1');
  setInterval(() => drainLaunchQueue(), 5000).unref();
  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = startControlPlaneServer();
  process.stdout.write(
    `[gg-control-plane] listening on http://127.0.0.1:${DEFAULT_PORT} for ${PROJECT_ROOT}\n`
  );
  process.on('SIGINT', () => {
    server.close(() => process.exit(0));
  });
  process.on('SIGTERM', () => {
    server.close(() => process.exit(0));
  });
}
