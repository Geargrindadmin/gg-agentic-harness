import fs from 'node:fs';
import path from 'node:path';
import type {
  HarnessContextSource,
  HarnessDocSyncMode,
  HarnessHydraMode,
  HarnessPromptImproverMode,
  HarnessValidateMode
} from '../../gg-core/dist/index.js';
import {
  defaultAdapterMode,
  defaultLaunchTransport,
  evaluateRuntimeLaunchPreflight,
  executeRuntimeLaunch,
  resolveLaunchAdapterMode,
  type AdapterMode,
  type LaunchTransport,
  type RuntimeExecutionResult,
  type RuntimePreflightReport
} from '../../gg-runtime-adapters/dist/index.js';

export type RuntimeId = 'codex' | 'claude' | 'kimi';
export type Classification = 'SIMPLE' | 'TASK' | 'TASK_LITE' | 'DECISION' | 'CRITICAL';
export type WorkerRole =
  | 'coordinator'
  | 'planner'
  | 'builder'
  | 'reviewer'
  | 'scout'
  | 'assembler'
  | 'specialist';
export type WorkerStatus =
  | 'planned'
  | 'spawn_requested'
  | 'queued'
  | 'running'
  | 'blocked'
  | 'handoff_ready'
  | 'completed'
  | 'failed'
  | 'terminated';
export type MessageType =
  | 'TASK_SPEC'
  | 'PROGRESS'
  | 'BLOCKED'
  | 'DELEGATE_REQUEST'
  | 'HANDOFF_READY'
  | 'SYSTEM';

interface PersonaRegistryFile {
  personas?: PersonaRegistryEntry[];
}

interface PersonaRegistryEntry {
  id: string;
  file?: string;
  role?: string;
  dispatchMode?: string;
  riskTier?: string;
  domains?: string[];
  selectionTriggers?: string[];
  defaultPartners?: string[];
  requiresBoardFor?: string[];
  memoryQuery?: string;
  allowed?: string[];
  blocked?: string[];
}

interface RuntimeRegistryFile {
  profiles?: Partial<Record<RuntimeId, RuntimeRegistryProfile>>;
}

interface RuntimeRegistryProfile {
  description?: string;
  mcpServers?: string[];
  disabled?: string[];
  optional?: string[];
}

export interface PersonaPacket {
  personaId: string;
  role: string;
  riskTier: 'low' | 'medium' | 'high' | '';
  dispatchMode: string;
  memoryQuery: string;
  domains: string[];
  allowed: string[];
  blocked: string[];
  requiresBoardFor: string[];
  defaultPartners: string[];
  promptPath: string;
  promptBody: string;
}

export interface RuntimeScorecard {
  runtime: RuntimeId;
  adapterMode: AdapterMode;
  mcpServers: string[];
  optionalMcpServers: string[];
  disabledMcpServers: string[];
  status: 'available';
}

export interface HarnessExecutionPolicy {
  loopBudget: number;
  retryLimit: number;
  retryBackoffSeconds: number[];
  promptImproverMode: HarnessPromptImproverMode;
  contextSource: HarnessContextSource;
  hydraMode: HarnessHydraMode;
  validateMode: HarnessValidateMode;
  docSyncMode: HarnessDocSyncMode;
}

export interface WorkerRecord {
  agentId: string;
  runtime: RuntimeId;
  parentAgentId: string | null;
  status: WorkerStatus;
  role: WorkerRole;
  taskSummary: string;
  persona: PersonaPacket;
  toolBundle: string[];
  worktree: string;
  harnessPolicy: HarnessExecutionPolicy | null;
  adapterMode: AdapterMode;
  launchTransport: LaunchTransport;
  launchSpec: Record<string, unknown>;
  execution: WorkerExecutionState;
  createdAt: string;
  updatedAt: string;
}

export interface WorkerExecutionState {
  status: 'pending' | 'running' | 'completed' | 'failed';
  attempts: number;
  lastExecutionId: string | null;
  lastPreflight: RuntimePreflightReport | null;
  requestFile: string | null;
  responseFile: string | null;
  transcriptFile: string | null;
  lastSummary: string;
  lastError: string;
  lastStartedAt: string | null;
  lastCompletedAt: string | null;
  dryRun: boolean;
}

export interface DelegationDecision {
  decisionId: string;
  runId: string;
  fromAgentId: string;
  requestedRuntime: RuntimeId;
  requestedRole: WorkerRole;
  personaId: string;
  taskSummary: string;
  classification: Classification;
  boardRequired: boolean;
  highRiskTerms: string[];
  status: 'approved' | 'rejected';
  rationale: string;
  timestamp: string;
  spawnedAgentId: string | null;
}

export interface BusMessage {
  cursor: number;
  messageId: string;
  runId: string;
  fromAgentId: string;
  toAgentId: string;
  type: MessageType;
  payload: Record<string, unknown>;
  requiresAck: boolean;
  ackedAt: string | null;
  timestamp: string;
}

export interface RunState {
  schemaVersion: 1;
  runId: string;
  summary: string;
  classification: Classification;
  coordinatorRuntime: RuntimeId;
  createdAt: string;
  updatedAt: string;
  bus: {
    transport: 'json-local';
    nextCursor: number;
    health: 'healthy';
  };
  runtimeScorecards: RuntimeScorecard[];
  workers: WorkerRecord[];
  messages: BusMessage[];
  delegationDecisions: DelegationDecision[];
}

export interface CreateRunInput {
  runId: string;
  summary: string;
  classification: Classification;
  coordinatorRuntime: RuntimeId;
}

export interface SpawnWorkerInput {
  runId: string;
  runtime: RuntimeId;
  agentId?: string;
  parentAgentId?: string | null;
  role: WorkerRole;
  taskSummary: string;
  persona: PersonaPacket;
  toolBundle?: string[];
  worktree?: string;
  launchTransport?: LaunchTransport;
  harnessPolicy?: HarnessExecutionPolicy | null;
}

export interface DelegateTaskInput {
  runId: string;
  fromAgentId: string;
  agentId?: string;
  toRuntime: RuntimeId;
  role: WorkerRole;
  taskSummary: string;
  classification: Classification;
  persona: PersonaPacket;
  boardApproved?: boolean;
  toolBundle?: string[];
  worktree?: string;
  launchTransport?: LaunchTransport;
  harnessPolicy?: HarnessExecutionPolicy | null;
}

export interface PostMessageInput {
  runId: string;
  fromAgentId: string;
  toAgentId: string;
  type: MessageType;
  payload?: Record<string, unknown>;
  requiresAck?: boolean;
}

export interface FetchInboxInput {
  runId: string;
  agentId: string;
  cursor?: number;
}

export interface AckMessageInput {
  runId: string;
  agentId: string;
  messageId: string;
}

export interface ExecuteWorkerInput {
  runId: string;
  agentId: string;
  dryRun?: boolean;
  signal?: AbortSignal;
}

export interface ControlPlanePaths {
  controlPlaneDir: string;
  runsDir: string;
  runFile: string;
  runArtifactFile: string;
}

const HIGH_RISK_TERMS = ['auth', 'payments', 'kyc', 'secrets', 'production'] as const;

function nowIso(): string {
  return new Date().toISOString();
}

function sleepMs(durationMs: number): void {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, durationMs);
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

function projectPaths(projectRoot: string, runId: string): ControlPlanePaths {
  const controlPlaneDir = path.join(projectRoot, '.agent', 'control-plane');
  const runsDir = path.join(controlPlaneDir, 'runs');
  return {
    controlPlaneDir,
    runsDir,
    runFile: path.join(runsDir, `${runId}.json`),
    runArtifactFile: path.join(projectRoot, '.agent', 'runs', `${runId}.json`)
  };
}

function runLockPath(projectRoot: string, runId: string): string {
  return `${projectPaths(projectRoot, runId).runFile}.lock`;
}

function acquireRunLock(projectRoot: string, runId: string): number {
  const lockPath = runLockPath(projectRoot, runId);
  ensureDir(path.dirname(lockPath));

  for (let attempt = 0; attempt < 80; attempt += 1) {
    try {
      return fs.openSync(lockPath, 'wx');
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'EEXIST') {
        throw error;
      }
      sleepMs(25);
    }
  }

  throw new Error(`Timed out waiting for control-plane lock: ${lockPath}`);
}

function releaseRunLock(projectRoot: string, runId: string, fd: number): void {
  const lockPath = runLockPath(projectRoot, runId);
  fs.closeSync(fd);
  if (fs.existsSync(lockPath)) {
    fs.unlinkSync(lockPath);
  }
}

function loadRuntimeRegistry(projectRoot: string): RuntimeRegistryFile {
  return readJson<RuntimeRegistryFile>(path.join(projectRoot, '.agent', 'registry', 'mcp-runtime.json')) || {};
}

function buildRuntimeScorecards(projectRoot: string): RuntimeScorecard[] {
  const registry = loadRuntimeRegistry(projectRoot);
  const runtimes: RuntimeId[] = ['codex', 'claude', 'kimi'];
  return runtimes.map((runtime) => {
    const profile = registry.profiles?.[runtime] || {};
    return {
      runtime,
      adapterMode: defaultAdapterMode(projectRoot, runtime),
      mcpServers: [...(profile.mcpServers || [])],
      optionalMcpServers: [...(profile.optional || [])],
      disabledMcpServers: [...(profile.disabled || [])],
      status: 'available'
    };
  });
}

function loadPersonaRegistry(projectRoot: string): PersonaRegistryEntry[] {
  const registry =
    readJson<PersonaRegistryFile>(path.join(projectRoot, '.agent', 'registry', 'persona-registry.json')) || {};
  return registry.personas || [];
}

const BUILTIN_PERSONA_FALLBACKS: Record<string, PersonaPacket> = {
  orchestrator: {
    personaId: 'orchestrator',
    role: 'coordinator',
    riskTier: 'medium',
    dispatchMode: 'multi-agent',
    memoryQuery: 'run coordination delegation worktree worker status',
    domains: ['orchestration', 'coordination'],
    allowed: ['coordinate workers', 'route tasks', 'monitor progress', 'request verification evidence'],
    blocked: ['directly mutate external production systems', 'change assigned persona'],
    requiresBoardFor: ['auth', 'payments', 'secrets', 'infra'],
    defaultPartners: ['project-planner', 'backend-specialist'],
    promptPath: '',
    promptBody: ''
  },
  'project-planner': {
    personaId: 'project-planner',
    role: 'planner',
    riskTier: 'medium',
    dispatchMode: 'structured',
    memoryQuery: 'task planning sequencing acceptance criteria',
    domains: ['planning', 'delivery'],
    allowed: ['write plans', 'clarify scope', 'define acceptance criteria'],
    blocked: ['deploy code', 'change assigned persona'],
    requiresBoardFor: ['auth', 'payments', 'infra'],
    defaultPartners: ['orchestrator', 'backend-specialist'],
    promptPath: '',
    promptBody: ''
  },
  'test-engineer': {
    personaId: 'test-engineer',
    role: 'reviewer',
    riskTier: 'low',
    dispatchMode: 'verification',
    memoryQuery: 'tests verification regressions qa',
    domains: ['testing', 'verification'],
    allowed: ['write tests', 'review regressions', 'report failures'],
    blocked: ['change assigned persona'],
    requiresBoardFor: [],
    defaultPartners: ['project-planner', 'backend-specialist'],
    promptPath: '',
    promptBody: ''
  },
  'explorer-agent': {
    personaId: 'explorer-agent',
    role: 'scout',
    riskTier: 'low',
    dispatchMode: 'discovery',
    memoryQuery: 'repository structure changed files recent context',
    domains: ['discovery', 'research'],
    allowed: ['inspect files', 'summarize findings', 'gather evidence'],
    blocked: ['change assigned persona'],
    requiresBoardFor: [],
    defaultPartners: ['orchestrator', 'project-planner'],
    promptPath: '',
    promptBody: ''
  },
  'backend-specialist': {
    personaId: 'backend-specialist',
    role: 'builder',
    riskTier: 'medium',
    dispatchMode: 'implementation',
    memoryQuery: 'backend services api implementation',
    domains: ['implementation', 'backend'],
    allowed: ['implement scoped changes', 'run local verification', 'prepare handoff summaries'],
    blocked: ['change assigned persona', 'spawn child agents directly'],
    requiresBoardFor: ['auth', 'payments', 'infra'],
    defaultPartners: ['project-planner', 'test-engineer'],
    promptPath: '',
    promptBody: ''
  }
};

function detectHighRiskTerms(taskSummary: string, persona: PersonaPacket): string[] {
  const lower = taskSummary.toLowerCase();
  const matches = new Set<string>();
  for (const term of HIGH_RISK_TERMS) {
    if (lower.includes(term)) {
      matches.add(term);
    }
  }
  for (const term of persona.requiresBoardFor) {
    if (lower.includes(term.toLowerCase())) {
      matches.add(term);
    }
  }
  if (persona.riskTier === 'high') {
    matches.add('high-risk-persona');
  }
  return [...matches];
}

function nextId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function trimPromptBody(raw: string): string {
  return raw.trim().replace(/\r\n/g, '\n');
}

function renderHarnessPersonaContract(packet: PersonaPacket, worker: SpawnWorkerInput): string {
  const policy = worker.harnessPolicy;
  const retryBudget = policy ? `${policy.retryLimit} attempts (${policy.retryBackoffSeconds.join('s, ')}s)` : '';
  const lines = [
    'You are operating inside the GG Agentic Harness.',
    `Persona ID: ${packet.personaId}`,
    `Role: ${packet.role}`,
    packet.memoryQuery ? `Memory query: ${packet.memoryQuery}` : '',
    packet.domains.length ? `Domains: ${packet.domains.join(', ')}` : '',
    '',
    'Allowed actions:',
    ...packet.allowed.map((item) => `- ${item}`),
    '',
    'Blocked actions:',
    ...packet.blocked.map((item) => `- ${item}`),
    '',
    'Harness rules:',
    '- Do not change your assigned persona.',
    '- Do not spawn child agents directly.',
    '- If you need another specialist, emit DELEGATE_REQUEST to the harness.',
    '- Communicate structured status updates on single lines so the harness can parse them in real time.',
    '- Emit progress updates as: @@GG_MSG {"type":"PROGRESS","body":"<summary>"}',
    '- Emit blocked states as: @@GG_MSG {"type":"BLOCKED","body":"<reason>","requiresAck":true}',
    '- When you need another specialist, emit: @@GG_MSG {"type":"DELEGATE_REQUEST","body":"<why>","payload":{"requestedRuntime":"kimi|claude|codex","requestedRole":"builder|reviewer|planner","personaId":"<persona-id>","taskSummary":"<task>"}}',
    '- When your scoped task is complete, emit: @@GG_STATE {"status":"handoff_ready","summary":"<summary>"}',
    '- If you must stop because you are blocked, emit: @@GG_STATE {"status":"blocked","reason":"<reason>"}',
    '',
    'Active harness execution policy:',
    policy ? `- Loop budget: ${policy.loopBudget}` : '- Loop budget: repo default',
    policy ? `- Retry budget: ${retryBudget}` : '- Retry budget: repo default',
    policy ? `- Prompt improver mode: ${policy.promptImproverMode}` : '- Prompt improver mode: repo default',
    policy ? `- Context source: ${policy.contextSource}` : '- Context source: repo default',
    policy ? `- Hydra mode: ${policy.hydraMode}` : '- Hydra mode: repo default',
    policy ? `- Validate mode: ${policy.validateMode}` : '- Validate mode: repo default',
    policy ? `- Doc sync mode: ${policy.docSyncMode}` : '- Doc sync mode: repo default',
    '- Treat the loop budget and retry budget as hard harness limits for this run.',
    `Assigned task role: ${worker.role}`,
    `Assigned task summary: ${worker.taskSummary}`
  ];
  return lines.filter(Boolean).join('\n');
}

function renderKimiLaunchSpec(projectRoot: string, worker: SpawnWorkerInput): Record<string, unknown> {
  const systemPrompt = renderHarnessPersonaContract(worker.persona, worker);
  const userPrompt = [
    `Run ID: ${worker.runId}`,
    worker.agentId ? `Agent ID: ${worker.agentId}` : '',
    worker.parentAgentId ? `Parent Agent ID: ${worker.parentAgentId}` : '',
    `Role: ${worker.role}`,
    `Task: ${worker.taskSummary}`,
    worker.worktree ? `Worktree: ${worker.worktree}` : '',
    worker.toolBundle?.length ? `Allowed tool bundle: ${worker.toolBundle.join(', ')}` : 'Allowed tool bundle: none declared'
  ]
    .filter(Boolean)
    .join('\n');

  const requestBody: Record<string, unknown> = {
    model: 'kimi-k2.5',
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt }
    ]
  };

  if ((worker.toolBundle || []).length > 0) {
    requestBody.thinking = { type: 'disabled' };
  }

  return {
    transport: worker.launchTransport === 'cli-session' ? 'kimi-cli-print' : 'openai-compatible-chat',
    adapterMode: resolveLaunchAdapterMode(projectRoot, 'kimi', worker.launchTransport || defaultLaunchTransport(projectRoot, 'kimi')),
    requestBody,
    notes: [
      'Kimi worker personas are injected by the harness through the system message.',
      'The worker must emit @@GG_MSG / @@GG_STATE markers so the control plane can parse live PTY output.',
      worker.launchTransport === 'cli-session'
        ? 'CLI transport inherits the local kimi session instead of copying API credentials.'
        : 'Populate tools/tool_choice from the harness-approved tool bundle at adapter execution time.'
    ]
  };
}

function renderGenericLaunchSpec(projectRoot: string, worker: SpawnWorkerInput): Record<string, unknown> {
  return {
    transport: worker.launchTransport || defaultLaunchTransport(projectRoot, worker.runtime),
    adapterMode: resolveLaunchAdapterMode(
      projectRoot,
      worker.runtime,
      worker.launchTransport || defaultLaunchTransport(projectRoot, worker.runtime)
    ),
    prompt: renderHarnessPersonaContract(worker.persona, worker),
    taskSummary: worker.taskSummary,
    toolBundle: worker.toolBundle || [],
    harnessPolicy: worker.harnessPolicy || null,
    notes: [
      'Background-terminal workers inherit the existing local CLI authentication for the current user.',
      'Live workers must emit @@GG_MSG / @@GG_STATE markers for structured harness communication.'
    ]
  };
}

function renderLaunchSpec(projectRoot: string, worker: SpawnWorkerInput): Record<string, unknown> {
  if (worker.runtime === 'kimi') {
    return renderKimiLaunchSpec(projectRoot, worker);
  }
  return renderGenericLaunchSpec(projectRoot, worker);
}

function createWorkerRecord(projectRoot: string, input: SpawnWorkerInput, agentId: string): WorkerRecord {
  const now = nowIso();
  const workerInput: SpawnWorkerInput = {
    ...input,
    agentId,
    parentAgentId: input.parentAgentId || null,
    toolBundle: input.toolBundle || [],
    worktree: input.worktree || projectRoot,
    launchTransport: input.launchTransport || defaultLaunchTransport(projectRoot, input.runtime),
    harnessPolicy: input.harnessPolicy || null
  };

  return {
    agentId,
    runtime: input.runtime,
    parentAgentId: input.parentAgentId || null,
    status: 'spawn_requested',
    role: input.role,
    taskSummary: input.taskSummary,
    persona: input.persona,
    toolBundle: [...(input.toolBundle || [])],
    worktree: input.worktree || projectRoot,
    harnessPolicy: input.harnessPolicy || null,
    adapterMode: resolveLaunchAdapterMode(
      projectRoot,
      input.runtime,
      workerInput.launchTransport || defaultLaunchTransport(projectRoot, input.runtime)
    ),
    launchTransport: workerInput.launchTransport || defaultLaunchTransport(projectRoot, input.runtime),
    launchSpec: renderLaunchSpec(projectRoot, workerInput),
    execution: {
      status: 'pending',
      attempts: 0,
      lastExecutionId: null,
      lastPreflight: null,
      requestFile: null,
      responseFile: null,
      transcriptFile: null,
      lastSummary: '',
      lastError: '',
      lastStartedAt: null,
      lastCompletedAt: null,
      dryRun: false
    },
    createdAt: now,
    updatedAt: now
  };
}

export function buildPersonaPacket(projectRoot: string, personaId: string): PersonaPacket {
  const registry = loadPersonaRegistry(projectRoot);
  const persona = registry.find((entry) => entry.id === personaId);
  if (!persona) {
    const fallback = BUILTIN_PERSONA_FALLBACKS[personaId];
    if (!fallback) {
      throw new Error(`Persona not found: ${personaId}`);
    }
    return { ...fallback };
  }

  const promptPath = path.join(projectRoot, persona.file || '');
  const promptBody = persona.file && fs.existsSync(promptPath) ? trimPromptBody(fs.readFileSync(promptPath, 'utf8')) : '';

  return {
    personaId: persona.id,
    role: persona.role || 'specialist',
    riskTier: persona.riskTier === 'low' || persona.riskTier === 'medium' || persona.riskTier === 'high' ? persona.riskTier : '',
    dispatchMode: persona.dispatchMode || '',
    memoryQuery: persona.memoryQuery || '',
    domains: [...(persona.domains || [])],
    allowed: [...(persona.allowed || [])],
    blocked: [...(persona.blocked || [])],
    requiresBoardFor: [...(persona.requiresBoardFor || [])],
    defaultPartners: [...(persona.defaultPartners || [])],
    promptPath,
    promptBody
  };
}

export function readRunState(projectRoot: string, runId: string): RunState {
  const filePath = projectPaths(projectRoot, runId).runFile;
  const run = readJson<RunState>(filePath);
  if (!run) {
    throw new Error(`Control-plane run not found: ${filePath}`);
  }
  return run;
}

export function writeRunState(projectRoot: string, state: RunState): string {
  const paths = projectPaths(projectRoot, state.runId);
  ensureDir(paths.runsDir);
  state.updatedAt = nowIso();
  writeJson(paths.runFile, state);
  syncRunArtifact(projectRoot, state.runId, (artifact) => {
    artifact.activeRuntime = state.coordinatorRuntime;
    artifact.messageBusHealth = {
      status: state.bus.health,
      transport: state.bus.transport,
      pendingMessages: state.messages.filter((message) => !message.ackedAt).length,
      lastCursor: Math.max(0, state.bus.nextCursor - 1)
    };
    artifact.runtimeScorecards = state.runtimeScorecards.map((entry) => ({
      runtime: entry.runtime,
      adapterMode: entry.adapterMode,
      status: entry.status,
      mcpServers: entry.mcpServers,
      optionalMcpServers: entry.optionalMcpServers,
      disabledMcpServers: entry.disabledMcpServers
    }));
    artifact.workerGraph = {
      workers: state.workers.map((worker) => ({
        agentId: worker.agentId,
        runtime: worker.runtime,
        role: worker.role,
        personaId: worker.persona.personaId,
        parentAgentId: worker.parentAgentId,
        status: worker.status
      })),
      edges: state.workers
        .filter((worker) => worker.parentAgentId)
        .map((worker) => ({
          fromAgentId: worker.parentAgentId,
          toAgentId: worker.agentId,
          relation: 'spawned'
        }))
    };
    artifact.delegationDecisions = state.delegationDecisions;
    artifact.delegationFailures = state.delegationDecisions
      .filter((decision) => decision.status === 'rejected')
      .map((decision) => ({
        decisionId: decision.decisionId,
        fromAgentId: decision.fromAgentId,
        requestedRuntime: decision.requestedRuntime,
        personaId: decision.personaId,
        reason: decision.rationale,
        timestamp: decision.timestamp
      }));
  });
  return paths.runFile;
}

export function listRunStates(projectRoot: string): RunState[] {
  const runsDir = path.join(projectRoot, '.agent', 'control-plane', 'runs');
  if (!fs.existsSync(runsDir)) {
    return [];
  }

  return fs
    .readdirSync(runsDir)
    .filter((entry) => entry.endsWith('.json'))
    .map((entry) => readJson<RunState>(path.join(runsDir, entry)))
    .filter((entry): entry is RunState => Boolean(entry))
    .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
}

function ensureArtifactShape(artifact: Record<string, unknown>, fallbackRuntime: RuntimeId): void {
  if (typeof artifact.activeRuntime !== 'string') {
    artifact.activeRuntime = fallbackRuntime;
  }
  if (!Array.isArray(artifact.delegationDecisions)) {
    artifact.delegationDecisions = [];
  }
  if (!Array.isArray(artifact.delegationFailures)) {
    artifact.delegationFailures = [];
  }
  if (!Array.isArray(artifact.runtimeScorecards)) {
    artifact.runtimeScorecards = [];
  }
  if (!artifact.workerGraph || typeof artifact.workerGraph !== 'object') {
    artifact.workerGraph = { workers: [], edges: [] };
  }
  if (!artifact.messageBusHealth || typeof artifact.messageBusHealth !== 'object') {
    artifact.messageBusHealth = {
      status: 'healthy',
      transport: 'json-local',
      pendingMessages: 0,
      lastCursor: 0
    };
  }
}

export function syncRunArtifact(
  projectRoot: string,
  runId: string,
  mutate: (artifact: Record<string, unknown>) => void
): void {
  const { runArtifactFile } = projectPaths(projectRoot, runId);
  if (!fs.existsSync(runArtifactFile)) {
    return;
  }
  const artifact = readJson<Record<string, unknown>>(runArtifactFile);
  if (!artifact) {
    return;
  }
  const runtime = (artifact.runtimeProfile as RuntimeId) || 'codex';
  ensureArtifactShape(artifact, runtime);
  mutate(artifact);
  artifact.updatedAt = nowIso();
  writeJson(runArtifactFile, artifact);
}

function appendBusMessage(
  run: RunState,
  input: {
    fromAgentId: string;
    toAgentId: string;
    type: MessageType;
    payload?: Record<string, unknown>;
    requiresAck?: boolean;
  }
): BusMessage {
  const message: BusMessage = {
    cursor: run.bus.nextCursor,
    messageId: nextId('msg'),
    runId: run.runId,
    fromAgentId: input.fromAgentId,
    toAgentId: input.toAgentId,
    type: input.type,
    payload: input.payload || {},
    requiresAck: Boolean(input.requiresAck),
    ackedAt: null,
    timestamp: nowIso()
  };
  run.bus.nextCursor += 1;
  run.messages.push(message);
  return message;
}

export function createRunState(projectRoot: string, input: CreateRunInput): { run: RunState; filePath: string } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const existing = readJson<RunState>(projectPaths(projectRoot, input.runId).runFile);
    if (existing) {
      throw new Error(`Control-plane run already exists: ${input.runId}`);
    }

    const now = nowIso();
    const run: RunState = {
      schemaVersion: 1,
      runId: input.runId,
      summary: input.summary,
      classification: input.classification,
      coordinatorRuntime: input.coordinatorRuntime,
      createdAt: now,
      updatedAt: now,
      bus: {
        transport: 'json-local',
        nextCursor: 1,
        health: 'healthy'
      },
      runtimeScorecards: buildRuntimeScorecards(projectRoot),
      workers: [],
      messages: [],
      delegationDecisions: []
    };

    const filePath = writeRunState(projectRoot, run);
    return { run, filePath };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function spawnWorker(projectRoot: string, input: SpawnWorkerInput): { run: RunState; worker: WorkerRecord } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const agentId = input.agentId || nextId('worker');
    if (run.workers.some((worker) => worker.agentId === agentId)) {
      throw new Error(`Worker already exists in run ${input.runId}: ${agentId}`);
    }

    const worker = createWorkerRecord(projectRoot, input, agentId);
    run.workers.push(worker);
    writeRunState(projectRoot, run);
    return { run, worker };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function delegateTask(
  projectRoot: string,
  input: DelegateTaskInput
): { run: RunState; decision: DelegationDecision; worker: WorkerRecord | null } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const parent = run.workers.find((worker) => worker.agentId === input.fromAgentId);
    if (!parent) {
      throw new Error(`Parent worker not found in run ${input.runId}: ${input.fromAgentId}`);
    }

    const highRiskTerms = detectHighRiskTerms(input.taskSummary, input.persona);
    const boardRequired = highRiskTerms.length > 0;
    const approved = !boardRequired || Boolean(input.boardApproved);
    const decision: DelegationDecision = {
      decisionId: nextId('delegation'),
      runId: input.runId,
      fromAgentId: input.fromAgentId,
      requestedRuntime: input.toRuntime,
      requestedRole: input.role,
      personaId: input.persona.personaId,
      taskSummary: input.taskSummary,
      classification: input.classification,
      boardRequired,
      highRiskTerms,
      status: approved ? 'approved' : 'rejected',
      rationale: approved
        ? 'Delegation approved by harness policy'
        : `Delegation blocked until board approval for: ${highRiskTerms.join(', ')}`,
      timestamp: nowIso(),
      spawnedAgentId: null
    };

    let worker: WorkerRecord | null = null;
    if (approved) {
      const agentId = input.agentId || nextId('worker');
      worker = createWorkerRecord(
        projectRoot,
        {
          runId: input.runId,
          runtime: input.toRuntime,
          parentAgentId: input.fromAgentId,
          role: input.role,
          taskSummary: input.taskSummary,
          persona: input.persona,
          toolBundle: input.toolBundle,
          worktree: input.worktree,
          launchTransport: input.launchTransport
        },
        agentId
      );
      run.workers.push(worker);
      decision.spawnedAgentId = worker.agentId;
    }

    run.delegationDecisions.push(decision);
    writeRunState(projectRoot, run);
    return { run, decision, worker };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

function launchEnvelopeFromWorker(runId: string, worker: WorkerRecord): {
  runId: string;
  agentId: string;
  runtime: RuntimeId;
  taskSummary: string;
  worktree: string;
  toolBundle: string[];
  launchTransport: LaunchTransport;
  launchSpec: Record<string, unknown>;
} {
  return {
    runId,
    agentId: worker.agentId,
    runtime: worker.runtime,
    taskSummary: worker.taskSummary,
    worktree: worker.worktree,
    toolBundle: [...worker.toolBundle],
    launchTransport: worker.launchTransport,
    launchSpec: worker.launchSpec
  };
}

function formatPreflightFailure(report: RuntimePreflightReport): string {
  return report.checks
    .filter((entry) => entry.status === 'fail')
    .map((entry) => entry.detail)
    .join(' | ');
}

function applyExecutionResult(worker: WorkerRecord, result: RuntimeExecutionResult, preflight: RuntimePreflightReport): void {
  worker.execution.status = result.status === 'completed' ? 'completed' : 'failed';
  worker.execution.lastExecutionId = result.executionId;
  worker.execution.lastPreflight = preflight;
  worker.execution.requestFile = result.requestFile;
  worker.execution.responseFile = result.responseFile;
  worker.execution.transcriptFile = result.transcriptFile;
  worker.execution.lastSummary = result.summary;
  worker.execution.lastError = result.error || '';
  worker.execution.lastStartedAt = result.startedAt;
  worker.execution.lastCompletedAt = result.completedAt;
  worker.execution.dryRun = result.dryRun;
  worker.updatedAt = nowIso();
  worker.status = result.status === 'completed' ? 'handoff_ready' : 'failed';
}

export async function executeWorker(
  projectRoot: string,
  input: ExecuteWorkerInput
): Promise<{ run: RunState; worker: WorkerRecord; execution: RuntimeExecutionResult }> {
  const currentRun = readRunState(projectRoot, input.runId);
  const currentWorker = currentRun.workers.find((entry) => entry.agentId === input.agentId);
  if (!currentWorker) {
    throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
  }

  const preflight = evaluateRuntimeLaunchPreflight(projectRoot, launchEnvelopeFromWorker(input.runId, currentWorker));
  if (preflight.status !== 'passed') {
    const lockFd = acquireRunLock(projectRoot, input.runId);
    try {
      const run = readRunState(projectRoot, input.runId);
      const worker = run.workers.find((entry) => entry.agentId === input.agentId);
      if (!worker) {
        throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
      }
      worker.execution.attempts += 1;
      worker.execution.status = 'failed';
      worker.execution.lastPreflight = preflight;
      worker.execution.lastError = formatPreflightFailure(preflight) || preflight.summary;
      worker.execution.lastSummary = preflight.summary;
      worker.execution.lastStartedAt = nowIso();
      worker.execution.lastCompletedAt = nowIso();
      worker.execution.dryRun = Boolean(input.dryRun);
      worker.status = 'failed';
      worker.updatedAt = nowIso();

      if (worker.parentAgentId) {
        appendBusMessage(run, {
          fromAgentId: worker.agentId,
          toAgentId: worker.parentAgentId,
          type: 'BLOCKED',
          payload: {
            reason: worker.execution.lastError,
            preflight
          },
          requiresAck: true
        });
      }

      writeRunState(projectRoot, run);
      return {
        run,
        worker,
        execution: {
          executionId: worker.execution.lastExecutionId || nextId('exec'),
          status: 'failed',
          dryRun: Boolean(input.dryRun),
          adapterMode: worker.adapterMode,
          launchTransport: worker.launchTransport,
          summary: preflight.summary,
          outputText: '',
          requestFile: null,
          responseFile: null,
          transcriptFile: null,
          error: worker.execution.lastError,
          responseStatus: null,
          startedAt: worker.execution.lastStartedAt || nowIso(),
          completedAt: worker.execution.lastCompletedAt || nowIso()
        }
      };
    } finally {
      releaseRunLock(projectRoot, input.runId, lockFd);
    }
  }

  {
    const lockFd = acquireRunLock(projectRoot, input.runId);
    try {
      const run = readRunState(projectRoot, input.runId);
      const worker = run.workers.find((entry) => entry.agentId === input.agentId);
      if (!worker) {
        throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
      }
      worker.execution.status = 'running';
      worker.execution.attempts += 1;
      worker.execution.lastPreflight = preflight;
      worker.execution.lastStartedAt = nowIso();
      worker.execution.lastCompletedAt = null;
      worker.execution.lastError = '';
      worker.execution.lastSummary = '';
      worker.execution.dryRun = Boolean(input.dryRun);
      worker.status = 'running';
      worker.updatedAt = nowIso();
      writeRunState(projectRoot, run);
    } finally {
      releaseRunLock(projectRoot, input.runId, lockFd);
    }
  }

  const execution = await executeRuntimeLaunch(
    projectRoot,
    launchEnvelopeFromWorker(input.runId, currentWorker),
    { dryRun: input.dryRun, signal: input.signal } as { dryRun?: boolean; signal?: AbortSignal }
  );

  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const worker = run.workers.find((entry) => entry.agentId === input.agentId);
    if (!worker) {
      throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
    }

    applyExecutionResult(worker, execution, preflight);

    if (worker.parentAgentId) {
      appendBusMessage(run, {
        fromAgentId: worker.agentId,
        toAgentId: worker.parentAgentId,
        type: execution.status === 'completed' ? 'HANDOFF_READY' : 'BLOCKED',
        payload:
          execution.status === 'completed'
            ? {
                executionId: execution.executionId,
                summary: execution.summary,
                transcriptFile: execution.transcriptFile,
                responseFile: execution.responseFile,
                dryRun: execution.dryRun
              }
            : {
                executionId: execution.executionId,
                reason: execution.error || execution.summary,
                responseFile: execution.responseFile
              },
        requiresAck: true
      });
    }

    writeRunState(projectRoot, run);
    return { run, worker, execution };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function postMessage(projectRoot: string, input: PostMessageInput): { run: RunState; message: BusMessage } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const message = appendBusMessage(run, input);
    writeRunState(projectRoot, run);
    return { run, message };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function fetchInbox(projectRoot: string, input: FetchInboxInput): { run: RunState; messages: BusMessage[] } {
  const run = readRunState(projectRoot, input.runId);
  const cursor = input.cursor || 0;
  const messages = run.messages.filter(
    (message) => message.toAgentId === input.agentId && message.cursor > cursor
  );
  return { run, messages };
}

export function ackMessage(projectRoot: string, input: AckMessageInput): { run: RunState; message: BusMessage } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const message = run.messages.find(
      (entry) => entry.messageId === input.messageId && entry.toAgentId === input.agentId
    );
    if (!message) {
      throw new Error(`Message not found for ${input.agentId}: ${input.messageId}`);
    }
    message.ackedAt = nowIso();
    writeRunState(projectRoot, run);
    return { run, message };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function listWorkers(projectRoot: string, runId: string, agentId?: string): WorkerRecord[] {
  const run = readRunState(projectRoot, runId);
  if (!agentId) {
    return run.workers;
  }
  return run.workers.filter((worker) => worker.agentId === agentId);
}

export function updateWorkerTask(
  projectRoot: string,
  input: { runId: string; agentId: string; taskSummary: string; append?: boolean }
): { run: RunState; worker: WorkerRecord } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const worker = run.workers.find((entry) => entry.agentId === input.agentId);
    if (!worker) {
      throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
    }

    const nextTaskSummary = input.append
      ? `${worker.taskSummary}\n${input.taskSummary}`.trim()
      : input.taskSummary.trim();

    worker.taskSummary = nextTaskSummary;
    worker.launchSpec = renderLaunchSpec(projectRoot, {
      runId: input.runId,
      runtime: worker.runtime,
      agentId: worker.agentId,
      parentAgentId: worker.parentAgentId,
      role: worker.role,
      taskSummary: nextTaskSummary,
      persona: worker.persona,
      toolBundle: worker.toolBundle,
      worktree: worker.worktree,
      launchTransport: worker.launchTransport
    });
    worker.updatedAt = nowIso();
    writeRunState(projectRoot, run);
    return { run, worker };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function setWorkerStatus(
  projectRoot: string,
  input: {
    runId: string;
    agentId: string;
    status: WorkerStatus;
    summary?: string;
    error?: string;
    executionStatus?: WorkerExecutionState['status'];
  }
): { run: RunState; worker: WorkerRecord } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const worker = run.workers.find((entry) => entry.agentId === input.agentId);
    if (!worker) {
      throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
    }

    worker.status = input.status;
    if (input.executionStatus) {
      worker.execution.status = input.executionStatus;
    }
    if (typeof input.summary === 'string') {
      worker.execution.lastSummary = input.summary;
    }
    if (typeof input.error === 'string') {
      worker.execution.lastError = input.error;
      worker.execution.lastCompletedAt = nowIso();
    }
    worker.updatedAt = nowIso();
    writeRunState(projectRoot, run);
    return { run, worker };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function terminateWorker(
  projectRoot: string,
  input: { runId: string; agentId: string; reason?: string }
): { run: RunState; worker: WorkerRecord } {
  const lockFd = acquireRunLock(projectRoot, input.runId);
  try {
    const run = readRunState(projectRoot, input.runId);
    const worker = run.workers.find((entry) => entry.agentId === input.agentId);
    if (!worker) {
      throw new Error(`Worker not found in run ${input.runId}: ${input.agentId}`);
    }

    worker.status = 'terminated';
    worker.execution.status = 'failed';
    worker.execution.lastError = input.reason || 'Worker terminated by harness operator';
    worker.execution.lastSummary = input.reason || 'Worker terminated by harness operator';
    worker.execution.lastCompletedAt = nowIso();
    worker.updatedAt = nowIso();

    if (worker.parentAgentId) {
      appendBusMessage(run, {
        fromAgentId: worker.agentId,
        toAgentId: worker.parentAgentId,
        type: 'BLOCKED',
        payload: {
          reason: worker.execution.lastError,
          terminated: true
        },
        requiresAck: true
      });
    }

    writeRunState(projectRoot, run);
    return { run, worker };
  } finally {
    releaseRunLock(projectRoot, input.runId, lockFd);
  }
}

export function listRunMessages(projectRoot: string, runId: string): BusMessage[] {
  return readRunState(projectRoot, runId).messages;
}

export function getControlPlanePaths(projectRoot: string, runId: string): ControlPlanePaths {
  return projectPaths(projectRoot, runId);
}
