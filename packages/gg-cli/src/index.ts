#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { spawnSync } from 'node:child_process';
import {
  buildCanonicalProductSpec,
  createProductBundle,
  getHarnessExecutionPreflight,
  harnessSettingsPath,
  getHarnessPaths,
  loadSkills,
  loadWorkflows,
  readHarnessSettings,
  readCatalogEntryContent,
  readJsonFile,
  resetHarnessSettings,
  resolveGoSourceInput,
  resolveProjectRoot,
  resolveHarnessDiagramPath,
  searchCatalog,
  writeHarnessSettings,
  type CatalogEntry
} from '../../gg-core/dist/index.js';
import {
  ackMessage,
  buildPersonaPacket,
  createRunState,
  delegateTask,
  executeWorker,
  fetchInbox,
  listWorkers,
  postMessage,
  type Classification,
  type RuntimeId,
  type WorkerRole,
  spawnWorker,
  writeRunState
} from '../../gg-orchestrator/dist/index.js';

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

interface FullDocUpdatePayload {
  summary: string;
  reportPath: string;
  runArtifactPath: string;
  changedFiles: string[];
  mandatoryDocs: Array<{ path: string; exists: boolean }>;
  conditionalDocs: Array<{ category: string; suggestedPaths: string[] }>;
}

type ContextSource = 'standard' | 'codegraphcontext' | 'hybrid';
type CodeGraphContextMode = 'off' | 'prefer' | 'hybrid' | 'required';
type PromptImproverMode = 'off' | 'auto' | 'force';
type HydraMode = 'off' | 'shadow' | 'active';
type HydraRoute = 'native' | 'single' | 'tandem' | 'council';
type ProductResolution = ReturnType<typeof buildCanonicalProductSpec>;

interface CommandTrace {
  command: string;
  code: number;
  stdout?: string;
  stderr?: string;
}

interface CodeGraphContextResult {
  mode: CodeGraphContextMode;
  source: ContextSource;
  available: boolean;
  indexed: boolean;
  query: string;
  summary: string[];
  evidence: string[];
  commands: CommandTrace[];
  error?: string;
}

interface PromptImproverOption {
  label: string;
  description: string;
}

interface PromptImproverQuestion {
  header: string;
  question: string;
  options: PromptImproverOption[];
}

interface PromptImproverPayload {
  rawObjective: string;
  normalizedObjective: string;
  clarity: 'clear' | 'needs_clarification';
  intent: 'feature' | 'bugfix' | 'refactor' | 'decision' | 'audit' | 'docs' | 'task';
  researchPlan: string[];
  codebaseFindings: string[];
  constraints: string[];
  acceptanceCriteria: string[];
  riskFlags: string[];
  questions: PromptImproverQuestion[];
  contextSource: ContextSource;
  contextEvidence: string[];
}

interface HydraDecisionPayload {
  mode: HydraMode;
  status: 'skipped' | 'blocked' | 'advisory' | 'delegated';
  route: HydraRoute;
  normalizedObjective: string;
  delegatedWorkflow: string | null;
  reason: string;
  codebaseEvidence: string[];
  internetEvidence: string[];
}

interface EvidencePreview {
  path: string;
  exists: boolean;
  kind: 'json' | 'markdown' | 'text' | 'missing';
  title: string;
  preview: string;
}

interface VisualExplainerMetrics {
  changedFilesCount: number;
  evidenceCount: number;
  validationsPass: number;
  validationsFail: number;
  eventsCount: number;
}

const BUILDER_ROUTABLE_LANES = new Set(['marketing-site', 'saas-dashboard', 'admin-panel']);

function isBuilderEligible(productResolution: ProductResolution): boolean {
  return BUILDER_ROUTABLE_LANES.has(productResolution.lane.id) &&
    productResolution.unsupportedRequestedPackIds.length === 0;
}

function buildBuilderRouteFlags(flags: Record<string, FlagValue>, runId: string): Record<string, FlagValue> {
  return {
    ...flags,
    'output-dir': path.join('.agent', 'product-bundles', runId)
  };
}

function routeSupportedProductToBuilder(
  projectRoot: string,
  request: string,
  flags: Record<string, FlagValue>,
  runId: string
): CommandResult {
  return runCreateWorkflow(projectRoot, request, buildBuilderRouteFlags(flags, runId), true);
}

interface VisualExplainerArtifact {
  mode: string;
  subject: string;
  generatedAt: string;
  changedFiles: string[];
  evidence: EvidencePreview[];
  validationRows: Array<{ name: string; status: string; detail: string }>;
  eventRows: Array<{ type: string; status: string; summary: string }>;
  contextSource: ContextSource;
  summaryBullets: string[];
  citations: string[];
  metrics: VisualExplainerMetrics;
}

interface AgenticStatusCheck {
  id: string;
  status: 'pass' | 'warn' | 'fail';
  summary: string;
  detail: string;
  source: 'doctor' | 'repo' | 'catalog' | 'control-plane' | 'runtime' | 'context';
}

interface AgenticStatusRecentRun {
  runId: string;
  workflow: string;
  status: string;
  createdAt: string;
  filePath: string;
}

interface AgenticStatusPayload {
  runId: string;
  generatedAt: string;
  overall: 'healthy' | 'attention' | 'degraded';
  summary: {
    failingChecks: number;
    warningChecks: number;
    dirtyFiles: number;
    recentRuns: number;
  };
  repo: {
    projectRoot: string;
    branch: string;
    dirty: boolean;
    changedFiles: string[];
    worktrees: string[];
  };
  catalogs: {
    skillsCount: number;
    workflowsCount: number;
    agentsCount: number;
    packsCount: number;
    productLanesCount: number;
    schemasCount: number;
  };
  controlPlane: {
    runsCount: number;
    worktreesCount: number;
    executionsCount: number;
    serverFilesCount: number;
  };
  runtime: {
    activation: {
      active: boolean;
      activationType: string | null;
      checks: AgenticStatusCheck[];
    };
    parity: {
      ok: boolean;
      strict: boolean;
      checks: AgenticStatusCheck[];
    };
    context: {
      status: 'current' | 'stale' | 'missing';
      detail: string;
    };
  };
  recentRuns: AgenticStatusRecentRun[];
  checks: AgenticStatusCheck[];
  runArtifact: string;
}

interface ProductLaneDefinition {
  id: string;
  name: string;
  description: string;
  v1Mandatory: boolean;
  category: string;
  allowedStacks: string[];
  defaultStack: string;
  requiredCapabilities: string[];
  defaultPacks: string[];
  allowedPacks: string[];
  requiredGates: string[];
}

interface ProductPackDefinition {
  id: string;
  name: string;
  description: string;
  v1Unattended: boolean;
  riskTier: 'low' | 'medium' | 'high';
  compatibleLanes: string[];
  requiredConfig: string[];
  addsCapabilities: string[];
  requiredGates: string[];
  reviewRequired: boolean;
}

type CanonicalProductSourceType = 'prompt' | 'prd' | 'prompt+constraints' | 'normalized';
type DeliveryTarget = 'local-repo' | 'portable-target' | 'downstream-install';

interface CanonicalProductSpec {
  schemaVersion: 1;
  sourceType: CanonicalProductSourceType;
  sourcePath?: string;
  summary: string;
  lane: string;
  laneConfidence: number;
  targetStack: string;
  riskTier: 'low' | 'medium' | 'high';
  enterprisePacks: string[];
  constraints: string[];
  requiredIntegrations: string[];
  acceptanceCriteria: string[];
  validationProfile: string;
  deliveryTarget: DeliveryTarget;
  downstreamTarget?: string;
  requiresHumanReview: boolean;
}

interface GoSourceInput {
  sourceType: CanonicalProductSourceType;
  rawInput: string;
  sourceText: string;
  sourcePath?: string;
  normalizedSpec?: Partial<CanonicalProductSpec>;
}

interface GoProductResolution {
  canonicalSpec: CanonicalProductSpec;
  lane: ProductLaneDefinition;
  laneConfidence: number;
  laneEvidence: string[];
  selectedPacks: ProductPackDefinition[];
  requestedPackIds: string[];
  unsupportedRequestedPackIds: string[];
  missingConfig: string[];
  reviewReasons: string[];
}

const PORTABLE_DOC_FILES = [
  'docs/agentic-harness.md',
  'docs/memory.md',
  'docs/runtime-profiles.md',
  'docs/setup/portable-agentic-harness-setup.md',
  'docs/architecture/agentic-harness-dynamic-user-diagram.html'
];

const PORTABLE_AGENT_PATHS = [
  '.agent/agents',
  '.agent/policies',
  '.agent/registry',
  '.agent/rules',
  '.agent/schemas',
  '.agent/skills',
  '.agent/templates',
  '.agent/workflows'
];

const PORTABLE_REQUIRED_PACKAGE_SCRIPTS: Record<string, string> = {
  'harness:lint': 'node scripts/harness-lint.mjs',
  'harness:artifact:init': 'node scripts/agent-run-artifact.mjs init',
  'harness:artifact:gate': 'node scripts/agent-run-artifact.mjs gate',
  'harness:artifact:mcp': 'node scripts/agent-run-artifact.mjs mcp',
  'harness:artifact:event': 'node scripts/agent-run-artifact.mjs event',
  'harness:artifact:feedback': 'node scripts/agent-run-artifact.mjs feedback',
  'harness:artifact:persona': 'node scripts/agent-run-artifact.mjs persona',
  'harness:artifact:complete': 'node scripts/agent-run-artifact.mjs complete',
  'harness:skills-audit': 'node scripts/skills-audit.mjs',
  'harness:project-context': 'node scripts/generate-project-context.mjs',
  'harness:project-context:check': 'node scripts/generate-project-context.mjs --check',
  'harness:persona:sync': 'node scripts/persona-registry-sync.mjs',
  'harness:persona:audit': 'node scripts/persona-registry-audit.mjs',
  'harness:persona:benchmark': 'node scripts/persona-registry-benchmark.mjs',
  'harness:runtime:activate': 'node scripts/runtime-project-sync.mjs activate --runtime codex',
  'harness:runtime:status': 'node scripts/runtime-project-sync.mjs status --runtime codex',
  'harness:codex:activate': 'node scripts/codex-project-sync.mjs activate',
  'harness:codex:status': 'node scripts/codex-project-sync.mjs status',
  'harness:runtime-parity': 'node scripts/runtime-parity-smoke.mjs',
  'harness:runtime-parity:json': 'node scripts/runtime-parity-smoke.mjs --json',
  'obsidian:doctor': 'node scripts/obsidian-cli-doctor.mjs',
  'obsidian:vault:init': 'node scripts/obsidian-vault-bootstrap.mjs',
  'obsidian:model-log': 'node scripts/obsidian-model-log.mjs'
};

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
  gg [--json] [--project-root <path>] workflow run <slug> [args...] [--validate none|tsc|lint|test|all] [--evidence <path[,path]>] [--doc-sync auto|off] [--mode <name>] [--prompt-improver off|auto|force] [--context-source off|prefer|hybrid|required] [--hydra-mode off|shadow|active] [--internet-evidence <citation[,citation]>] [--codebase-evidence <path[,path]>]
  gg [--json] [--project-root <path>] run <create|init|gate|mcp|event|feedback|persona|context|complete> [--key value]
  gg [--json] [--project-root <path>] worker <spawn|delegate|launch|status> [--key value]
  gg [--json] [--project-root <path>] bus <post|inbox|ack> [--key value]
  gg [--json] [--project-root <path>] runtime <activate|status> [targetDir] [--runtime codex|claude|kimi] [--codex-home <path>]
  gg [--json] [--project-root <path>] codex <activate|status> [targetDir] [--codex-home <path>]
  gg [--json] [--project-root <path>] context <check|refresh>
  gg [--json] [--project-root <path>] validate <tsc|lint|test|all>
  gg [--json] [--project-root <path>] harness settings <get|set|reset> [--key <dot.path> --value <value>]
  gg [--json] [--project-root <path>] harness diagram [--format json|html]
  gg [--json] [--project-root <path>] harness ui <snapshot|command|batch> [options]
  gg [--json] [--project-root <path>] obsidian <doctor|bootstrap|model-log>
  gg [--json] [--project-root <path>] portable init <targetDir> [--mode symlink|copy]
  gg [--json] [--project-root <path>] portable verify <targetDir> [--runtime structure|smoke]
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

function intFlagAllowZero(flags: Record<string, FlagValue>, name: string, fallback: number): number {
  const value = flagString(flags, name);
  if (value === undefined) {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`Invalid --${name} value: ${value}`);
  }
  return parsed;
}

function booleanFlag(flags: Record<string, FlagValue>, key: string, fallback = false): boolean {
  const value = flags[key];
  if (value === undefined) {
    return fallback;
  }
  if (typeof value === 'boolean') {
    return value;
  }
  if (Array.isArray(value)) {
    return booleanFlag({ [key]: value[0] }, key, fallback);
  }

  const normalized = value.trim().toLowerCase();
  if (['true', '1', 'yes', 'on'].includes(normalized)) return true;
  if (['false', '0', 'no', 'off'].includes(normalized)) return false;
  throw new Error(`Invalid --${key} value: ${value}`);
}

function parseRuntimeId(value: string | undefined, fallback: RuntimeId = 'codex'): RuntimeId {
  const runtime = (value || fallback) as RuntimeId;
  if (runtime !== 'codex' && runtime !== 'claude' && runtime !== 'kimi') {
    throw new Error(`Invalid runtime: ${value}`);
  }
  return runtime;
}

function parseClassification(value: string | undefined, fallback: Classification = 'TASK'): Classification {
  const classification = (value || fallback) as Classification;
  if (!['SIMPLE', 'TASK', 'TASK_LITE', 'DECISION', 'CRITICAL'].includes(classification)) {
    throw new Error(`Invalid classification: ${value}`);
  }
  return classification;
}

function parseWorkerRole(value: string | undefined, fallback: WorkerRole = 'builder'): WorkerRole {
  const role = (value || fallback) as WorkerRole;
  if (!['coordinator', 'planner', 'builder', 'reviewer', 'scout', 'assembler', 'specialist'].includes(role)) {
    throw new Error(`Invalid worker role: ${value}`);
  }
  return role;
}

function parseLaunchTransport(
  value: string | undefined
): 'contract-only' | 'background-terminal' | 'api-session' | 'cli-session' | undefined {
  if (!value) return undefined;
  if (!['contract-only', 'background-terminal', 'api-session', 'cli-session'].includes(value)) {
    throw new Error(`Invalid launch transport: ${value}`);
  }
  return value as 'contract-only' | 'background-terminal' | 'api-session' | 'cli-session';
}

function generateWorkerId(role: WorkerRole): string {
  return `${role}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

function generateRunId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function ensureHarnessWorktree(projectRoot: string, runId: string, agentId: string): string {
  const target = path.join(projectRoot, '.agent', 'control-plane', 'worktrees', runId, agentId);
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
    throw new Error((result.stderr || result.stdout || `Failed to create worktree for ${agentId}`).trim());
  }

  return target;
}

function parsePayload(value: string | undefined): Record<string, unknown> {
  if (!value) return {};
  try {
    const parsed = JSON.parse(value);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('payload must be a JSON object');
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'unknown error';
    throw new Error(`Invalid JSON payload: ${detail}`);
  }
}

function resolvePersonaPacketForTask(
  projectRoot: string,
  flags: Record<string, FlagValue>,
  taskSummary: string,
  classification: Classification
) {
  const explicitPersonaId = flagString(flags, 'persona-id');
  if (explicitPersonaId) {
    return {
      packet: buildPersonaPacket(projectRoot, explicitPersonaId),
      source: 'explicit',
      resolvedPersonaId: explicitPersonaId
    };
  }

  const resolvePrompt = flagString(flags, 'persona-prompt') || taskSummary;
  if (!resolvePrompt.trim()) {
    throw new Error('Provide --persona-id or a non-empty --task/--persona-prompt value');
  }

  const resolver = executeJsonNodeScript(
    projectRoot,
    path.join(projectRoot, 'scripts', 'persona-registry-resolve.mjs'),
    ['--prompt', resolvePrompt, '--classification', classification, '--json']
  );

  if (resolver.code !== 0) {
    throw new Error(`Persona resolver failed: ${(resolver.stderr || resolver.stdout).trim()}`);
  }

  const parsed = resolver.parsed as { primaryPersona?: { id?: string } } | null;
  const resolvedPersonaId = parsed?.primaryPersona?.id;
  if (!resolvedPersonaId) {
    throw new Error('Persona resolver did not return a primary persona');
  }

  return {
    packet: buildPersonaPacket(projectRoot, resolvedPersonaId),
    source: 'resolver',
    resolvedPersonaId
  };
}

function pushOptionalArtifactFlag(args: string[], flags: Record<string, FlagValue>, key: string): void {
  const value = flagString(flags, key);
  if (value !== undefined) {
    args.push(`--${key}`, value);
  }
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

function countEntries(dirPath: string, predicate?: (entry: fs.Dirent) => boolean): number {
  if (!fs.existsSync(dirPath)) {
    return 0;
  }

  return fs.readdirSync(dirPath, { withFileTypes: true }).filter((entry) => (predicate ? predicate(entry) : true)).length;
}

function listGitWorktrees(projectRoot: string): string[] {
  const result = executeCommand('git', ['worktree', 'list', '--porcelain'], projectRoot, true);
  if (result.code !== 0) {
    return [];
  }

  return result.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.startsWith('worktree '))
    .map((line) => line.slice('worktree '.length).trim());
}

function summarizeRecentRuns(projectRoot: string, limit: number): AgenticStatusRecentRun[] {
  return latestRunArtifactPaths(projectRoot, limit).map((filePath) => {
    const parsed = readJsonFile<Record<string, unknown>>(filePath) || {};
    const fileStats = fs.statSync(filePath);

    const runId = typeof parsed.runId === 'string' ? parsed.runId : path.basename(filePath, '.json');
    const workflow = typeof parsed.workflow === 'string'
      ? parsed.workflow
      : typeof parsed.slug === 'string'
        ? parsed.slug
        : typeof parsed.type === 'string'
          ? parsed.type
          : 'unknown';
    const status = typeof parsed.status === 'string'
      ? parsed.status
      : typeof parsed.outcome === 'string'
        ? parsed.outcome
        : typeof parsed.mode === 'string'
          ? parsed.mode
          : 'unknown';
    const createdAt = typeof parsed.createdAt === 'string'
      ? parsed.createdAt
      : typeof parsed.generatedAt === 'string'
        ? parsed.generatedAt
        : fileStats.mtime.toISOString();

    return {
      runId,
      workflow,
      status,
      createdAt,
      filePath: path.relative(projectRoot, filePath)
    };
  });
}

function buildAgenticStatus(projectRoot: string, flags: Record<string, FlagValue>): AgenticStatusPayload {
  const paths = getHarnessPaths(projectRoot);
  const generatedAt = isoNow();
  const runId = generateRunId('agentic-status');
  const runArtifact = path.join(paths.runArtifactDir, `${runId}.json`);
  const recentRunsLimit = intFlagAllowZero(flags, 'limit', 5);

  const doctorResult = commandDoctor(projectRoot, true).payload as
    | {
      checks?: Array<{ name?: string; ok?: boolean; detail?: string }>;
      skillsCount?: number;
      workflowsCount?: number;
    }
    | undefined;

  const doctorChecks: AgenticStatusCheck[] = Array.isArray(doctorResult?.checks)
    ? doctorResult.checks.map((check) => ({
      id: slugify(String(check.name || 'doctor-check')) || 'doctor-check',
      status: check.ok ? 'pass' : 'fail',
      summary: String(check.name || 'doctor check'),
      detail: String(check.detail || ''),
      source: 'doctor'
    }))
    : [];

  const changedFiles = parseGitStatusPaths(executeCommand('git', ['status', '--short'], projectRoot, true).stdout);
  const branch = executeCommand('git', ['branch', '--show-current'], projectRoot, true).stdout.trim() || 'DETACHED';
  const worktrees = listGitWorktrees(projectRoot);

  const repoChecks: AgenticStatusCheck[] = [
    {
      id: 'git_worktree_clean',
      status: changedFiles.length > 0 ? 'warn' : 'pass',
      summary: changedFiles.length > 0 ? 'Working tree has local modifications' : 'Working tree is clean',
      detail: changedFiles.length > 0 ? changedFiles.slice(0, 10).join(', ') : branch,
      source: 'repo'
    },
    {
      id: 'git_worktrees_available',
      status: worktrees.length > 0 ? 'pass' : 'warn',
      summary: worktrees.length > 0 ? 'Git worktrees are discoverable' : 'No git worktrees were discovered',
      detail: worktrees.length > 0 ? `${worktrees.length} worktree(s)` : 'git worktree list returned no entries',
      source: 'repo'
    }
  ];

  const agentsDir = path.join(projectRoot, '.agent', 'agents');
  const packsDir = path.join(projectRoot, '.agent', 'packs');
  const productLanesDir = path.join(projectRoot, '.agent', 'product-lanes');
  const schemasDir = path.join(projectRoot, '.agent', 'schemas');

  const catalogs = {
    skillsCount: typeof doctorResult?.skillsCount === 'number'
      ? doctorResult.skillsCount
      : countEntries(paths.skillsDir, (entry) => entry.isDirectory()),
    workflowsCount: typeof doctorResult?.workflowsCount === 'number'
      ? doctorResult.workflowsCount
      : countEntries(paths.workflowsDir, (entry) => entry.isFile() && entry.name.endsWith('.md')),
    agentsCount: countEntries(agentsDir, (entry) => entry.isFile() && entry.name.endsWith('.md')),
    packsCount: countEntries(packsDir, (entry) => entry.isFile() && entry.name.endsWith('.json')),
    productLanesCount: countEntries(productLanesDir, (entry) => entry.isFile() && entry.name.endsWith('.json')),
    schemasCount: countEntries(schemasDir, (entry) => entry.isFile() && entry.name.endsWith('.json'))
  };

  const catalogChecks: AgenticStatusCheck[] = [
    {
      id: 'catalog_skills_present',
      status: catalogs.skillsCount > 0 ? 'pass' : 'fail',
      summary: catalogs.skillsCount > 0 ? 'Skills catalog is populated' : 'Skills catalog is empty',
      detail: `${catalogs.skillsCount} skill directories`,
      source: 'catalog'
    },
    {
      id: 'catalog_workflows_present',
      status: catalogs.workflowsCount > 0 ? 'pass' : 'fail',
      summary: catalogs.workflowsCount > 0 ? 'Workflow catalog is populated' : 'Workflow catalog is empty',
      detail: `${catalogs.workflowsCount} workflow files`,
      source: 'catalog'
    },
    {
      id: 'catalog_product_lanes_present',
      status: catalogs.productLanesCount > 0 ? 'pass' : 'fail',
      summary: catalogs.productLanesCount > 0 ? 'Product lane registry is populated' : 'Product lane registry is empty',
      detail: `${catalogs.productLanesCount} product lane definitions`,
      source: 'catalog'
    },
    {
      id: 'catalog_packs_present',
      status: catalogs.packsCount > 0 ? 'pass' : 'fail',
      summary: catalogs.packsCount > 0 ? 'Enterprise pack registry is populated' : 'Enterprise pack registry is empty',
      detail: `${catalogs.packsCount} pack definitions`,
      source: 'catalog'
    }
  ];

  const controlPlaneRoot = path.join(projectRoot, '.agent', 'control-plane');
  const controlPlane = {
    runsCount: countEntries(path.join(controlPlaneRoot, 'runs'), (entry) => entry.isFile() && entry.name.endsWith('.json')),
    worktreesCount: countEntries(path.join(controlPlaneRoot, 'worktrees'), (entry) => entry.isDirectory()),
    executionsCount: countEntries(path.join(controlPlaneRoot, 'executions'), (entry) => entry.isFile() || entry.isDirectory()),
    serverFilesCount: countEntries(path.join(controlPlaneRoot, 'server'))
  };

  const controlPlaneChecks: AgenticStatusCheck[] = [
    {
      id: 'control_plane_root_present',
      status: fs.existsSync(controlPlaneRoot) ? 'pass' : 'fail',
      summary: fs.existsSync(controlPlaneRoot) ? 'Control-plane root is present' : 'Control-plane root is missing',
      detail: controlPlaneRoot,
      source: 'control-plane'
    },
    {
      id: 'control_plane_runs_dir_present',
      status: fs.existsSync(path.join(controlPlaneRoot, 'runs')) ? 'pass' : 'fail',
      summary: fs.existsSync(path.join(controlPlaneRoot, 'runs'))
        ? 'Control-plane run state directory is present'
        : 'Control-plane run state directory is missing',
      detail: path.join(controlPlaneRoot, 'runs'),
      source: 'control-plane'
    }
  ];

  const preflight = getHarnessExecutionPreflight(projectRoot, 'codex');
  const activationChecks: AgenticStatusCheck[] = preflight.activation.checks.map((check) => ({
    id: check.id,
    status: check.ok ? 'pass' : 'fail',
    summary: check.id,
    detail: check.detail,
    source: 'runtime'
  }));

  if (preflight.activation.parseError) {
    activationChecks.unshift({
      id: 'runtime_activation_payload',
      status: 'fail',
      summary: 'Runtime activation status could not be parsed',
      detail: preflight.activation.parseError,
      source: 'runtime'
    });
  }

  const parityChecks: AgenticStatusCheck[] = preflight.parity.checks.map((check) => ({
    id: check.id,
    status: check.status,
    summary: check.summary,
    detail: check.detail,
    source: 'runtime'
  }));

  if (preflight.parity.parseError) {
    parityChecks.unshift({
      id: 'runtime_parity_payload',
      status: 'fail',
      summary: 'Runtime parity status could not be parsed',
      detail: preflight.parity.parseError,
      source: 'runtime'
    });
  }

  const contextChecks: AgenticStatusCheck[] = [
    {
      id: 'project_context_check',
      status: preflight.context.status === 'current' ? 'pass' : 'fail',
      summary: preflight.context.status === 'current'
        ? 'Project context is current'
        : preflight.context.status === 'stale'
          ? 'Project context is stale'
          : 'Project context generator is missing',
      detail: preflight.context.detail,
      source: 'context'
    }
  ];

  const includeContextCheckInSummary = !parityChecks.some((check) => check.id === 'project_context');

  const recentRuns = summarizeRecentRuns(projectRoot, recentRunsLimit);

  const checks = [
    ...doctorChecks,
    ...repoChecks,
    ...catalogChecks,
    ...controlPlaneChecks,
    ...activationChecks,
    ...parityChecks,
    ...(includeContextCheckInSummary ? contextChecks : [])
  ];

  const failingChecks = checks.filter((check) => check.status === 'fail').length;
  const warningChecks = checks.filter((check) => check.status === 'warn').length;
  const overall: AgenticStatusPayload['overall'] = failingChecks > 0
    ? 'degraded'
    : warningChecks > 0
      ? 'attention'
      : 'healthy';

  const payload: AgenticStatusPayload = {
    runId,
    generatedAt,
    overall,
    summary: {
      failingChecks,
      warningChecks,
      dirtyFiles: changedFiles.length,
      recentRuns: recentRuns.length
    },
    repo: {
      projectRoot,
      branch,
      dirty: changedFiles.length > 0,
      changedFiles,
      worktrees
    },
    catalogs,
    controlPlane,
    runtime: {
      activation: {
        active: preflight.activation.active,
        activationType: preflight.activation.activationType,
        checks: activationChecks
      },
      parity: {
        ok: preflight.parity.ok,
        strict: preflight.parity.strict,
        checks: parityChecks
      },
      context: {
        status: preflight.context.status,
        detail: contextChecks[0].detail
      }
    },
    recentRuns,
    checks,
    runArtifact
  };

  writeJson(runArtifact, payload);
  return payload;
}

function runAgenticStatusWorkflow(
  projectRoot: string,
  _input: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  const payload = buildAgenticStatus(projectRoot, flags);

  if (!jsonMode) {
    console.log(`Agentic status: ${payload.overall}`);
    console.log(`Failing checks: ${payload.summary.failingChecks}`);
    console.log(`Warnings: ${payload.summary.warningChecks}`);
    console.log(`Branch: ${payload.repo.branch}`);
    console.log(`Dirty files: ${payload.summary.dirtyFiles}`);
    console.log(`Recent runs: ${payload.summary.recentRuns}`);
    console.log(`Run artifact: ${payload.runArtifact}`);
  }

  return {
    code: payload.summary.failingChecks > 0 ? 1 : 0,
    payload
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

const CODEGRAPH_CONTEXT_MODE_VALUES = ['off', 'prefer', 'hybrid', 'required'] as const;
const PROMPT_IMPROVER_MODE_VALUES = ['off', 'auto', 'force'] as const;
const HYDRA_MODE_VALUES = ['off', 'shadow', 'active'] as const;
const STOP_WORDS = new Set([
  'a',
  'an',
  'and',
  'as',
  'at',
  'by',
  'for',
  'from',
  'in',
  'into',
  'it',
  'of',
  'on',
  'or',
  'the',
  'this',
  'that',
  'to',
  'up',
  'we',
  'with'
]);
const PROMPT_FILLER_PATTERNS = [
  /^please\s+/iu,
  /^can you\s+/iu,
  /^could you\s+/iu,
  /^would you\s+/iu,
  /^just\s+/iu,
  /^quickly\s+/iu,
  /^help me\s+/iu,
  /^i need you to\s+/iu,
  /^i want you to\s+/iu,
  /^go ahead and\s+/iu
];
const PROMPT_ABBREVIATIONS: Array<[RegExp, string]> = [
  [/\bimpl\b/giu, 'implement'],
  [/\bfn\b/gu, 'function'],
  [/\bauth\b/giu, 'authentication'],
  [/\bconfig\b/giu, 'configuration'],
  [/\butil\b/giu, 'utility'],
  [/\butils\b/giu, 'utilities'],
  [/\bparams\b/giu, 'parameters'],
  [/\bparam\b/giu, 'parameter'],
  [/\benv\b/giu, 'environment'],
  [/\bdoc\b/giu, 'documentation'],
  [/\bdocs\b/giu, 'documentation'],
  [/\bopt\b/giu, 'optimize']
];

function coerceEnum<T extends string>(value: string | undefined, allowed: readonly T[], fallback: T): T {
  if (!value) {
    return fallback;
  }

  const normalized = value.trim().toLowerCase() as T;
  return allowed.includes(normalized) ? normalized : fallback;
}

function toCommandTrace(result: ExecOutcome): CommandTrace {
  return {
    command: `${result.command} ${result.args.join(' ')}`.trim(),
    code: result.code,
    stdout: result.stdout.trim(),
    stderr: result.stderr.trim()
  };
}

function uniqueStrings(items: string[]): string[] {
  return Array.from(new Set(items.filter(Boolean)));
}

function escapeHtml(input: string): string {
  return input
    .replace(/&/gu, '&amp;')
    .replace(/</gu, '&lt;')
    .replace(/>/gu, '&gt;')
    .replace(/"/gu, '&quot;')
    .replace(/'/gu, '&#39;');
}

function truncate(input: string, maxLength = 240): string {
  if (input.length <= maxLength) {
    return input;
  }
  return `${input.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function collectChangedFiles(projectRoot: string, manualChanged: string[] = []): string[] {
  const gitStatus = executeCommand('git', ['status', '--short'], projectRoot, true);
  const gitDiffHeadRange = executeCommand('git', ['diff', '--name-only', 'HEAD~1..HEAD'], projectRoot, true);
  const gitDiffHead = executeCommand('git', ['diff', '--name-only', 'HEAD'], projectRoot, true);
  const gitDiffCached = executeCommand('git', ['diff', '--cached', '--name-only'], projectRoot, true);

  const changedSet = new Set<string>(manualChanged);
  parseGitStatusPaths(gitStatus.stdout).forEach((item) => changedSet.add(item));
  parseLineList(gitDiffHeadRange.stdout).forEach((item) => changedSet.add(item));
  parseLineList(gitDiffHead.stdout).forEach((item) => changedSet.add(item));
  parseLineList(gitDiffCached.stdout).forEach((item) => changedSet.add(item));

  return Array.from(changedSet).sort((a, b) => a.localeCompare(b));
}

function latestRunArtifactPaths(projectRoot: string, limit: number): string[] {
  const runDir = path.join(projectRoot, '.agent', 'runs');
  if (!fs.existsSync(runDir)) {
    return [];
  }

  return fs
    .readdirSync(runDir)
    .filter((item) => item.endsWith('.json'))
    .map((item) => path.join(runDir, item))
    .map((item) => ({ path: item, mtimeMs: fs.statSync(item).mtimeMs }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs)
    .slice(0, limit)
    .map((item) => item.path);
}

function normalizeObjectiveText(text: string): string {
  if (!text.trim()) {
    return '';
  }

  let result = text.trim();
  let previous = '';
  while (previous !== result) {
    previous = result;
    for (const pattern of PROMPT_FILLER_PATTERNS) {
      result = result.replace(pattern, '').trim();
    }
  }

  for (const [pattern, replacement] of PROMPT_ABBREVIATIONS) {
    result = result.replace(pattern, replacement);
  }

  return result.replace(/\s+/gu, ' ').trim();
}

function classifyObjectiveIntent(text: string): PromptImproverPayload['intent'] {
  const lower = text.toLowerCase();

  if (/\b(decide|decision|trade[- ]?off|strategy|architecture|adr)\b/u.test(lower)) {
    return 'decision';
  }
  if (/\b(review|audit|assess|investigate|analyze)\b/u.test(lower)) {
    return 'audit';
  }
  if (/\b(doc|documentation|readme|walkthrough|report|diagram)\b/u.test(lower)) {
    return 'docs';
  }
  if (/\b(fix|bug|error|failure|broken|regression)\b/u.test(lower)) {
    return 'bugfix';
  }
  if (/\b(refactor|cleanup|extract|rename|simplify|rework)\b/u.test(lower)) {
    return 'refactor';
  }
  if (/\b(add|build|create|implement|wire|integrate|support|enable)\b/u.test(lower)) {
    return 'feature';
  }
  return 'task';
}

function detectObjectiveClarity(text: string): PromptImproverPayload['clarity'] {
  const normalized = normalizeObjectiveText(text);
  const lower = normalized.toLowerCase();
  const wordCount = normalized.split(/\s+/u).filter(Boolean).length;
  const hasAnchor =
    /[/#:][A-Za-z0-9._/-]+/u.test(normalized) ||
    /\b(line|file|function|class|workflow|route|script|component|module)\b/u.test(lower);
  const vagueOnly =
    /^(fix|improve|update|refactor|add|build|change|investigate|look into)(?:\s+(it|this|that|bug|issue|stuff))?$/u.test(lower);
  const vagueToken = /\b(it|this|that|thing|stuff|issue|bug)\b/u.test(lower);

  if (wordCount < 4 || vagueOnly || (vagueToken && !hasAnchor)) {
    return 'needs_clarification';
  }

  return 'clear';
}

function extractObjectiveKeywords(text: string): string[] {
  return uniqueStrings(
    normalizeObjectiveText(text)
      .toLowerCase()
      .split(/[^a-z0-9._/-]+/u)
      .map((token) => token.trim())
      .filter((token) => token.length > 2 && !STOP_WORDS.has(token))
  ).slice(0, 5);
}

function extractCandidatePathsFromFindings(findings: string[]): string[] {
  const candidates = findings
    .map((finding) => /^([^:\s]+):\d+/u.exec(finding)?.[1] || '')
    .filter(Boolean);
  return uniqueStrings(candidates).slice(0, 4);
}

function collectCodebaseFindings(projectRoot: string, objective: string): string[] {
  const findings: string[] = [];
  for (const keyword of extractObjectiveKeywords(objective).slice(0, 3)) {
    const result = executeCommand(
      'rg',
      [
        '-n',
        '-m',
        '3',
        '-F',
        '--glob',
        '!node_modules',
        '--glob',
        '!dist',
        '--glob',
        '!.git',
        '--glob',
        '!package-lock.json',
        '--glob',
        '!pnpm-lock.yaml',
        '--glob',
        '!yarn.lock',
        keyword,
        '.'
      ],
      projectRoot,
      true
    );
    if (result.code !== 0) {
      continue;
    }
    parseLineList(result.stdout)
      .slice(0, 3)
      .forEach((line) => findings.push(line));
  }

  return uniqueStrings(findings).slice(0, 6);
}

function expandEvidencePaths(projectRoot: string, rawPaths: string[]): string[] {
  const expanded: string[] = [];

  for (const rawPath of rawPaths) {
    const absolutePath = path.resolve(projectRoot, rawPath);
    if (!fs.existsSync(absolutePath)) {
      expanded.push(rawPath);
      continue;
    }

    const stats = fs.statSync(absolutePath);
    if (!stats.isDirectory()) {
      expanded.push(path.relative(projectRoot, absolutePath));
      continue;
    }

    const nested = fs
      .readdirSync(absolutePath)
      .map((item) => path.join(absolutePath, item))
      .filter((item) => fs.statSync(item).isFile())
      .filter((item) => /\.(json|md|txt|html)$/u.test(item))
      .map((item) => ({ path: item, mtimeMs: fs.statSync(item).mtimeMs }))
      .sort((a, b) => b.mtimeMs - a.mtimeMs)
      .slice(0, 3)
      .map((item) => path.relative(projectRoot, item.path));

    if (nested.length > 0) {
      expanded.push(...nested);
    }
  }

  return uniqueStrings(expanded);
}

function resolveCodeGraphContext(projectRoot: string, objective: string, flags: Record<string, FlagValue>): CodeGraphContextResult {
  const mode = coerceEnum(
    flagString(flags, 'context-source') || process.env.HARNESS_CODEGRAPH_CONTEXT_MODE,
    CODEGRAPH_CONTEXT_MODE_VALUES,
    'off'
  );
  const commands: CommandTrace[] = [];
  const fallback = (error?: string): CodeGraphContextResult => ({
    mode,
    source: 'standard',
    available: false,
    indexed: false,
    query: '',
    summary: [],
    evidence: [],
    commands,
    error
  });

  if (mode === 'off') {
    return fallback();
  }

  const cgcBinary = executeCommand('which', ['cgc'], projectRoot, true);
  commands.push(toCommandTrace(cgcBinary));
  if (cgcBinary.code !== 0) {
    return fallback('CodeGraphContext CLI (`cgc`) is not installed on this machine.');
  }

  const query = extractObjectiveKeywords(objective)[0] || path.basename(projectRoot);
  const listed = executeCommand('cgc', ['list'], projectRoot, true);
  commands.push(toCommandTrace(listed));
  let indexed =
    listed.code === 0 &&
    (listed.stdout.includes(projectRoot) || listed.stdout.toLowerCase().includes(path.basename(projectRoot).toLowerCase()));

  if (!indexed) {
    const indexedNow = executeCommand('cgc', ['index', '.'], projectRoot, true);
    commands.push(toCommandTrace(indexedNow));
    indexed = indexedNow.code === 0;
  }

  if (!indexed) {
    return fallback('CodeGraphContext could not index the repository, so the harness fell back to standard context.');
  }

  let search = executeCommand('cgc', ['find', 'pattern', query], projectRoot, true);
  commands.push(toCommandTrace(search));
  if (search.code !== 0 || !search.stdout.trim()) {
    search = executeCommand('cgc', ['find', 'content', query], projectRoot, true);
    commands.push(toCommandTrace(search));
  }

  const summary = parseLineList(search.stdout).slice(0, 5);
  if (!summary.length) {
    return fallback('CodeGraphContext indexed the repo but returned no usable matches for the current objective.');
  }

  return {
    mode,
    source: mode === 'hybrid' ? 'hybrid' : 'codegraphcontext',
    available: true,
    indexed: true,
    query,
    summary,
    evidence: summary.map((line) => `CodeGraphContext query "${query}" -> ${line}`),
    commands
  };
}

function buildPromptImproverQuestions(
  normalizedObjective: string,
  intent: PromptImproverPayload['intent'],
  findings: string[]
): PromptImproverQuestion[] {
  const questions: PromptImproverQuestion[] = [];
  const candidatePaths = extractCandidatePathsFromFindings(findings);

  if (candidatePaths.length > 0) {
    questions.push({
      header: 'Target',
      question: 'Which code path should own this work?',
      options: candidatePaths.slice(0, 3).map((candidate) => ({
        label: candidate.split('/').slice(-2).join('/'),
        description: `Matched during codebase research: ${candidate}`
      }))
    });
  } else {
    questions.push({
      header: 'Target',
      question: 'What is the narrowest target for this request?',
      options: [
        {
          label: 'Single file',
          description: 'Keep the change isolated to one file or one explicit entrypoint.'
        },
        {
          label: 'Component slice',
          description: 'Touch the smallest module boundary that can satisfy the request.'
        },
        {
          label: 'End-to-end',
          description: 'Allow controller, service, tests, and docs to move together.'
        }
      ]
    });
  }

  if (intent === 'feature' || intent === 'refactor' || intent === 'task') {
    questions.push({
      header: 'Scope',
      question: 'How wide should the implementation scope be?',
      options: [
        {
          label: 'Minimal diff',
          description: 'Only the smallest viable code and tests needed for the requested behavior.'
        },
        {
          label: 'Hardened slice',
          description: 'Include edge cases, validation, and docs parity in the same pass.'
        },
        {
          label: 'System update',
          description: 'Allow wider workflow, architecture, and documentation adjustments if needed.'
        }
      ]
    });
  }

  questions.push({
    header: 'Proof',
    question: 'What verification depth should the harness enforce?',
    options: [
      {
        label: 'Type + lint',
        description: 'Fastest feedback loop for docs or low-risk refactors.'
      },
      {
        label: 'Targeted tests',
        description: 'Run type-check, lint, and the smallest relevant test slice.'
      },
      {
        label: 'Full gate',
        description: 'Use the full harness quality path, including docs sync evidence.'
      }
    ]
  });

  return questions.slice(0, 3);
}

function createPromptImproverEnvelope(
  projectRoot: string,
  rawObjective: string,
  flags: Record<string, FlagValue>,
  overrideMode?: PromptImproverMode
): { mode: PromptImproverMode; promptImprover: PromptImproverPayload; contextPilot: CodeGraphContextResult } {
  const mode = overrideMode || coerceEnum(
    flagString(flags, 'prompt-improver') || process.env.HARNESS_PROMPT_IMPROVER_MODE,
    PROMPT_IMPROVER_MODE_VALUES,
    'auto'
  );
  const normalizedObjective = normalizeObjectiveText(rawObjective);
  const intent = classifyObjectiveIntent(normalizedObjective);
  const clarity = mode === 'force' ? 'needs_clarification' : detectObjectiveClarity(normalizedObjective);
  const contextPilot = resolveCodeGraphContext(projectRoot, normalizedObjective, flags);
  const codebaseFindings = uniqueStrings([
    ...contextPilot.summary.map((line) => `CGC ${line}`),
    ...collectCodebaseFindings(projectRoot, normalizedObjective)
  ]).slice(0, 8);

  const riskFlags: string[] = [];
  if (/\b(auth|authentication|payment|billing|stripe|security|secret|token|kyc|compliance)\b/iu.test(normalizedObjective)) {
    riskFlags.push('high-risk-domain');
  }
  if (/\b(board|architecture|strategy|workflow|orchestration|agentic|sidecar|integration)\b/iu.test(normalizedObjective)) {
    riskFlags.push('coordination-heavy');
  }
  if (clarity === 'needs_clarification') {
    riskFlags.push('ambiguous-intake');
  }
  if (contextPilot.source !== 'standard') {
    riskFlags.push('graph-context-pilot');
  }

  const researchPlan = [
    'Check conversation and repo-local docs for existing task context before routing.',
    `Search the codebase for objective anchors: ${extractObjectiveKeywords(normalizedObjective).join(', ') || 'no high-signal keywords found'}.`,
    contextPilot.source === 'standard'
      ? 'Use standard memory/project-context path because CodeGraphContext is unavailable or disabled.'
      : `Use ${contextPilot.source} context to enrich routing evidence before dispatch.`,
    'Derive acceptance criteria and validator depth before implementation begins.'
  ];

  const constraints = uniqueStrings([
    'Use existing harness skills/workflows before inventing new runtime paths.',
    'Keep deterministic validation ownership inside the harness core.',
    riskFlags.includes('high-risk-domain') ? 'Board review remains mandatory for auth, payments, security, and compliance changes.' : '',
    'Emit documentation sync evidence via full-doc-update at task completion.'
  ]).filter(Boolean);

  const acceptanceCriteria = uniqueStrings([
    'Objective is normalized into one primary workflow recommendation.',
    'Validation depth is explicit before implementation starts.',
    'Documentation parity evidence is captured for non-trivial tasks.',
    riskFlags.includes('high-risk-domain') ? 'Decision packets include codebase and dated internet evidence before routing or merge.' : ''
  ]).filter(Boolean);

  const promptImprover: PromptImproverPayload = {
    rawObjective,
    normalizedObjective,
    clarity,
    intent,
    researchPlan,
    codebaseFindings,
    constraints,
    acceptanceCriteria,
    riskFlags,
    questions: mode === 'off' || clarity === 'clear' ? [] : buildPromptImproverQuestions(normalizedObjective, intent, codebaseFindings),
    contextSource: contextPilot.source,
    contextEvidence: uniqueStrings([...contextPilot.evidence, ...codebaseFindings.slice(0, 4)])
  };

  return {
    mode,
    promptImprover,
    contextPilot
  };
}

function runPromptImprover(
  projectRoot: string,
  objective: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!objective.trim()) {
    throw new Error('prompt-improver requires an objective string');
  }

  const { mode, promptImprover, contextPilot } = createPromptImproverEnvelope(projectRoot, objective, flags, 'force');
  const runId = generateRunId('prompt-improver');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const reportPath = path.join(projectRoot, 'docs', 'reports', `${dateStamp()}-prompt-improver-${slugify(promptImprover.normalizedObjective) || 'objective'}.md`);
  const artifact = {
    schemaVersion: 1,
    runId,
    workflow: 'prompt-improver',
    mode,
    promptImprover,
    contextPilot,
    createdAt: isoNow()
  };

  writeJson(runPath, artifact);

  const report = [
    '# Prompt Improver Intake Packet',
    '',
    `- Raw objective: ${promptImprover.rawObjective}`,
    `- Normalized objective: ${promptImprover.normalizedObjective}`,
    `- Intent: ${promptImprover.intent}`,
    `- Clarity: ${promptImprover.clarity}`,
    `- Context source: ${promptImprover.contextSource}`,
    '',
    '## Constraints',
    ...promptImprover.constraints.map((item) => `- ${item}`),
    '',
    '## Acceptance Criteria',
    ...promptImprover.acceptanceCriteria.map((item) => `- ${item}`),
    '',
    '## Risk Flags',
    ...(promptImprover.riskFlags.length > 0 ? promptImprover.riskFlags.map((item) => `- ${item}`) : ['- none']),
    '',
    '## Research Plan',
    ...promptImprover.researchPlan.map((item, index) => `${index + 1}. ${item}`),
    '',
    '## Codebase Findings',
    ...(promptImprover.codebaseFindings.length > 0
      ? promptImprover.codebaseFindings.map((item) => `- ${item}`)
      : ['- No high-signal codebase matches were found.']),
    '',
    '## Clarifying Questions',
    ...(promptImprover.questions.length > 0
      ? promptImprover.questions.flatMap((question) => [
          `### ${question.header}`,
          `- ${question.question}`,
          ...question.options.map((option) => `  - ${option.label}: ${option.description}`),
          ''
        ])
      : ['- None. The objective is already specific enough for execution.']),
    ''
  ].join('\n');

  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${report}\n`, 'utf8');

  if (!jsonMode) {
    console.log(`Prompt improver packet created:`);
    console.log(`- ${reportPath}`);
    console.log(`- ${runPath}`);
  }

  return {
    code: 0,
    payload: {
      mode,
      runId,
      runArtifact: runPath,
      reportPath,
      ...promptImprover
    }
  };
}

function mapHydraRouteToWorkflow(route: HydraRoute): string | null {
  switch (route) {
    case 'single':
    case 'tandem':
      return 'symphony-lite';
    case 'council':
      return 'go';
    default:
      return null;
  }
}

function runHydraSidecarDecision(
  objective: string,
  flags: Record<string, FlagValue>,
  promptImprover: PromptImproverPayload,
  contextPilot: CodeGraphContextResult
): HydraDecisionPayload {
  const mode = coerceEnum(
    flagString(flags, 'hydra-mode') || process.env.HARNESS_HYDRA_MODE,
    HYDRA_MODE_VALUES,
    'off'
  );

  if (mode === 'off') {
    return {
      mode,
      status: 'skipped',
      route: 'native',
      normalizedObjective: promptImprover.normalizedObjective,
      delegatedWorkflow: null,
      reason: 'Hydra sidecar is disabled.',
      codebaseEvidence: [],
      internetEvidence: []
    };
  }

  const codebaseEvidence = uniqueStrings([
    ...flagStringArray(flags, 'codebase-evidence'),
    ...promptImprover.codebaseFindings.slice(0, 4),
    ...contextPilot.evidence.slice(0, 2)
  ]);
  const internetEvidence = uniqueStrings(flagStringArray(flags, 'internet-evidence'));

  if (codebaseEvidence.length === 0 || internetEvidence.length === 0) {
    return {
      mode,
      status: 'blocked',
      route: 'native',
      normalizedObjective: promptImprover.normalizedObjective,
      delegatedWorkflow: null,
      reason: 'Hydra sidecar failed closed because both codebase evidence and dated internet evidence are required.',
      codebaseEvidence,
      internetEvidence
    };
  }

  const lower = promptImprover.normalizedObjective.toLowerCase();
  let route: HydraRoute = 'single';
  if (
    promptImprover.riskFlags.includes('high-risk-domain') ||
    promptImprover.intent === 'decision' ||
    /\b(architecture|strategy|trade[- ]?off|policy|governance|orchestr)\b/u.test(lower)
  ) {
    route = 'council';
  } else if (
    promptImprover.intent === 'feature' ||
    promptImprover.intent === 'refactor' ||
    promptImprover.normalizedObjective.split(/\s+/u).length > 10
  ) {
    route = 'tandem';
  }

  const delegatedWorkflow = mapHydraRouteToWorkflow(route);
  return {
    mode,
    status: mode === 'active' && delegatedWorkflow ? 'delegated' : 'advisory',
    route,
    normalizedObjective: promptImprover.normalizedObjective,
    delegatedWorkflow,
    reason:
      route === 'council'
        ? 'High-risk or strategy-heavy intake requires council-level routing while the harness retains deterministic validation ownership.'
        : route === 'tandem'
          ? 'Multi-file or implementation-heavy intake benefits from planner/builder separation before validation.'
          : 'Focused objective can stay on a single execution lane with harness gates intact.',
    codebaseEvidence,
    internetEvidence
  };
}

function normalizeSearchText(input: string): string {
  return input.toLowerCase().replace(/[_-]+/gu, ' ');
}

function buildPaperclipPlan(
  projectRoot: string,
  objective: string,
  flags: Record<string, FlagValue>,
  promptEnvelope?: { mode: PromptImproverMode; promptImprover: PromptImproverPayload; contextPilot: CodeGraphContextResult }
): {
  runId: string;
  runPath: string;
  reportPath: string;
  primaryWorkflow: string;
  matchedSkills: CatalogEntry[];
  matchedWorkflows: CatalogEntry[];
  validators: string[];
  promptImproverMode: PromptImproverMode;
  promptImprover: PromptImproverPayload;
  contextPilot: CodeGraphContextResult;
  hydraSidecar: HydraDecisionPayload;
} {
  const envelope = promptEnvelope || createPromptImproverEnvelope(projectRoot, objective, flags);
  const normalizedObjective = envelope.promptImprover.normalizedObjective;
  const skills = loadSkills(projectRoot);
  const workflows = loadWorkflows(projectRoot);
  const matchedSkills = searchCatalog(skills, normalizedObjective, 5);
  const matchedWorkflows = searchCatalog(workflows, normalizedObjective, 5);
  const preferredOrder = ['create', 'go', 'minion', 'symphony-lite', 'paperclip-extracted', 'parallel-dispatcher', 'loop-planner', 'loop-executor'];
  const hydraSidecar = runHydraSidecarDecision(normalizedObjective, flags, envelope.promptImprover, envelope.contextPilot);
  const preferred = matchedWorkflows.find((item) => preferredOrder.includes(item.slug));
  const primaryWorkflow =
    hydraSidecar.status === 'delegated' && hydraSidecar.delegatedWorkflow
      ? hydraSidecar.delegatedWorkflow
      : preferred?.slug || 'go';
  const validators = ['npx tsc --noEmit', 'npm run lint', 'npm test', 'gg workflow run full-doc-update "<task summary>"'];
  const runId = generateRunId('paperclip');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const reportPath = path.join(projectRoot, 'docs', 'reports', `${dateStamp()}-paperclip-${slugify(normalizedObjective) || 'objective'}.md`);

  const artifact = {
    schemaVersion: 1,
    runId,
    workflow: 'paperclip-extracted',
    objective,
    normalizedObjective,
    promptImproverMode: envelope.mode,
    promptImprover: envelope.promptImprover,
    contextPilot: envelope.contextPilot,
    hydraSidecar,
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

  const report = [
    '# Paperclip Extracted Run',
    '',
    `- Raw objective: ${objective}`,
    `- Normalized objective: ${normalizedObjective}`,
    `- Primary workflow: ${primaryWorkflow}`,
    `- Prompt improver mode: ${envelope.mode}`,
    `- Context source: ${envelope.promptImprover.contextSource}`,
    `- Hydra sidecar: ${hydraSidecar.mode} (${hydraSidecar.status})`,
    `- Run artifact: ${path.relative(projectRoot, runPath)}`,
    '',
    '## Intake Packet',
    ...envelope.promptImprover.acceptanceCriteria.map((item) => `- ${item}`),
    '',
    '## Matched Skills',
    ...matchedSkills.map((item) => `- ${item.slug}: ${item.description}`),
    '',
    '## Matched Workflows',
    ...matchedWorkflows.map((item) => `- ${item.slug}: ${item.description}`),
    '',
    '## Validation Plan',
    ...validators.map((item) => `- ${item}`),
    '',
    '## Hydra Evidence Gate',
    ...(hydraSidecar.codebaseEvidence.length > 0
      ? hydraSidecar.codebaseEvidence.map((item) => `- Codebase: ${item}`)
      : ['- Codebase evidence not provided.']),
    ...(hydraSidecar.internetEvidence.length > 0
      ? hydraSidecar.internetEvidence.map((item) => `- Internet: ${item}`)
      : ['- Internet evidence not provided.']),
    ''
  ].join('\n');

  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${report}\n`, 'utf8');

  return {
    runId,
    runPath,
    reportPath,
    primaryWorkflow,
    matchedSkills,
    matchedWorkflows,
    validators,
    promptImproverMode: envelope.mode,
    promptImprover: envelope.promptImprover,
    contextPilot: envelope.contextPilot,
    hydraSidecar
  };
}

function runPaperclipExtracted(
  projectRoot: string,
  objective: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!objective.trim()) {
    throw new Error('paperclip-extracted requires an objective string');
  }

  const plan = buildPaperclipPlan(projectRoot, objective, flags);

  if (!jsonMode) {
    console.log(`Paperclip extracted run planned: ${plan.runId}`);
    console.log(`Primary workflow: ${plan.primaryWorkflow}`);
    console.log(`Context source: ${plan.promptImprover.contextSource}`);
    console.log(`Hydra sidecar: ${plan.hydraSidecar.mode} (${plan.hydraSidecar.status})`);
    console.log(`Report: ${plan.reportPath}`);
  }

  return {
    code: 0,
    payload: {
      runId: plan.runId,
      outcome: 'PLANNED',
      runArtifact: plan.runPath,
      reportPath: plan.reportPath,
      primaryWorkflow: plan.primaryWorkflow,
      matchedSkills: plan.matchedSkills,
      matchedWorkflows: plan.matchedWorkflows,
      validators: plan.validators,
      promptImproverMode: plan.promptImproverMode,
      promptImprover: plan.promptImprover,
      contextPilot: plan.contextPilot,
      hydraSidecar: plan.hydraSidecar
    }
  };
}

function runGoWorkflow(
  projectRoot: string,
  goal: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!goal.trim()) {
    throw new Error('go requires a goal string');
  }

  const source = resolveGoSourceInput(projectRoot, goal, flags);
  const promptEnvelope = createPromptImproverEnvelope(projectRoot, source.sourceText, flags);
  const productResolution = buildCanonicalProductSpec(projectRoot, source, promptEnvelope.promptImprover, flags);
  const preflight = getHarnessExecutionPreflight(projectRoot, 'codex');
  const runId = generateRunId('go');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const specPath = path.join(projectRoot, '.agent', 'runs', `${runId}.spec.json`);
  const baseArtifact = {
    schemaVersion: 1,
    runId,
    workflow: 'go',
    goal,
    sourceType: source.sourceType,
    sourcePath: source.sourcePath,
    normalizedGoal: promptEnvelope.promptImprover.normalizedObjective,
    promptImproverMode: promptEnvelope.mode,
    promptImprover: promptEnvelope.promptImprover,
    contextPilot: promptEnvelope.contextPilot,
    canonicalSpecPath: path.relative(projectRoot, specPath),
    canonicalSpec: productResolution.canonicalSpec,
    laneSelection: {
      laneId: productResolution.lane.id,
      confidence: productResolution.laneConfidence,
      evidence: productResolution.laneEvidence
    },
    packSelection: {
      selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
      requestedPackIds: productResolution.requestedPackIds,
      unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
      missingConfig: productResolution.missingConfig,
      reviewReasons: productResolution.reviewReasons
    },
    preflight,
    createdAt: isoNow()
  };

  writeJson(specPath, productResolution.canonicalSpec);

  if (!preflight.isRunnable) {
    writeJson(runPath, {
      ...baseArtifact,
      status: 'BLOCKED',
      blockingIssues: preflight.blockingIssues
    });

    return {
      code: 1,
      payload: {
        runId,
        outcome: 'BLOCKED',
        sourceType: source.sourceType,
        sourcePath: source.sourcePath,
        normalizedGoal: promptEnvelope.promptImprover.normalizedObjective,
        canonicalSpec: productResolution.canonicalSpec,
        laneSelection: {
          laneId: productResolution.lane.id,
          confidence: productResolution.laneConfidence,
          evidence: productResolution.laneEvidence
        },
        packSelection: {
          selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
          requestedPackIds: productResolution.requestedPackIds,
          unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
          missingConfig: productResolution.missingConfig,
          reviewReasons: productResolution.reviewReasons
        },
        preflight,
        blockingIssues: preflight.blockingIssues,
        runArtifact: runPath,
        specArtifact: specPath,
        promptImprover: promptEnvelope.promptImprover,
        contextPilot: promptEnvelope.contextPilot
      }
    };
  }

  if (isBuilderEligible(productResolution)) {
    const builderResult = routeSupportedProductToBuilder(projectRoot, goal, flags, runId);
    const builderPayload = (builderResult.payload || {}) as {
      outcome?: string;
      runArtifact?: string;
      specArtifact?: string;
      bundleDir?: string;
      bundleManifest?: string;
      generatedFiles?: string[];
      preflightWarnings?: string[];
    };
    const outcome = builderPayload.outcome || (builderResult.code === 0 ? 'HANDOFF_READY' : 'FAILED');

    writeJson(runPath, {
      ...baseArtifact,
      status: outcome,
      routedWorkflow: 'create',
      resolvedExecutionPath: 'builder',
      builderEligible: true,
      builderInvoked: true,
      downstreamRunArtifact: builderPayload.runArtifact
        ? path.relative(projectRoot, builderPayload.runArtifact)
        : undefined,
      downstreamSpecArtifact: builderPayload.specArtifact
        ? path.relative(projectRoot, builderPayload.specArtifact)
        : undefined,
      bundleDir: typeof builderPayload.bundleDir === 'string'
        ? path.relative(projectRoot, builderPayload.bundleDir)
        : undefined,
      bundleManifestPath: typeof builderPayload.bundleManifest === 'string'
        ? path.relative(projectRoot, builderPayload.bundleManifest)
        : undefined,
      generatedFiles: Array.isArray(builderPayload.generatedFiles) ? builderPayload.generatedFiles : undefined,
      preflightWarnings: Array.isArray(builderPayload.preflightWarnings) ? builderPayload.preflightWarnings : []
    });

    if (!jsonMode) {
      console.log(`Go intake routed: ${runId}`);
      console.log(`Normalized goal: ${promptEnvelope.promptImprover.normalizedObjective}`);
      console.log(`Product lane: ${productResolution.canonicalSpec.lane} (${productResolution.canonicalSpec.laneConfidence})`);
      console.log(`Target stack: ${productResolution.canonicalSpec.targetStack}`);
      console.log(`Enterprise packs: ${productResolution.canonicalSpec.enterprisePacks.join(', ') || 'none'}`);
      console.log('Routed workflow: create');
      if (typeof builderPayload.bundleDir === 'string') {
        console.log(`Bundle directory: ${builderPayload.bundleDir}`);
      }
      console.log(`Canonical spec: ${specPath}`);
      console.log(`Run artifact: ${runPath}`);
    }

    return {
      code: builderResult.code,
      payload: {
        runId,
        outcome,
        sourceType: source.sourceType,
        sourcePath: source.sourcePath,
        normalizedGoal: promptEnvelope.promptImprover.normalizedObjective,
        canonicalSpec: productResolution.canonicalSpec,
        laneSelection: {
          laneId: productResolution.lane.id,
          confidence: productResolution.laneConfidence,
          evidence: productResolution.laneEvidence
        },
        packSelection: {
          selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
          requestedPackIds: productResolution.requestedPackIds,
          unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
          missingConfig: productResolution.missingConfig,
          reviewReasons: productResolution.reviewReasons
        },
        routedWorkflow: 'create',
        resolvedExecutionPath: 'builder',
        builderEligible: true,
        builderInvoked: true,
        bundleDir: builderPayload.bundleDir,
        bundleManifest: builderPayload.bundleManifest,
        generatedFiles: builderPayload.generatedFiles,
        runArtifact: runPath,
        specArtifact: specPath,
        downstreamRunArtifact: builderPayload.runArtifact,
        downstreamSpecArtifact: builderPayload.specArtifact,
        preflight,
        preflightWarnings: builderPayload.preflightWarnings || [],
        promptImprover: promptEnvelope.promptImprover,
        contextPilot: promptEnvelope.contextPilot
      }
    };
  }

  const plan = buildPaperclipPlan(projectRoot, promptEnvelope.promptImprover.normalizedObjective, flags, promptEnvelope);
  writeJson(runPath, {
    ...baseArtifact,
    status: 'PLANNED',
    routedWorkflow: plan.primaryWorkflow,
    resolvedExecutionPath: 'planner',
    builderEligible: false,
    builderInvoked: false,
    downstreamRunArtifact: path.relative(projectRoot, plan.runPath)
  });

  if (!jsonMode) {
    console.log(`Go intake routed: ${runId}`);
    console.log(`Normalized goal: ${promptEnvelope.promptImprover.normalizedObjective}`);
    console.log(`Product lane: ${productResolution.canonicalSpec.lane} (${productResolution.canonicalSpec.laneConfidence})`);
    console.log(`Target stack: ${productResolution.canonicalSpec.targetStack}`);
    console.log(`Enterprise packs: ${productResolution.canonicalSpec.enterprisePacks.join(', ') || 'none'}`);
    console.log(`Routed workflow: ${plan.primaryWorkflow}`);
    console.log(`Canonical spec: ${specPath}`);
    console.log(`Run artifact: ${runPath}`);
  }

  return {
    code: 0,
    payload: {
      runId,
      sourceType: source.sourceType,
      sourcePath: source.sourcePath,
      normalizedGoal: promptEnvelope.promptImprover.normalizedObjective,
      canonicalSpec: productResolution.canonicalSpec,
      laneSelection: {
        laneId: productResolution.lane.id,
        confidence: productResolution.laneConfidence,
        evidence: productResolution.laneEvidence
      },
      packSelection: {
        selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
        requestedPackIds: productResolution.requestedPackIds,
        unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
        missingConfig: productResolution.missingConfig,
        reviewReasons: productResolution.reviewReasons
      },
      routedWorkflow: plan.primaryWorkflow,
      resolvedExecutionPath: 'planner',
      builderEligible: false,
      builderInvoked: false,
      runArtifact: runPath,
      specArtifact: specPath,
      downstreamRunArtifact: plan.runPath,
      preflight,
      promptImprover: promptEnvelope.promptImprover,
      contextPilot: promptEnvelope.contextPilot,
      hydraSidecar: plan.hydraSidecar
    }
  };
}

function runCreateWorkflow(
  projectRoot: string,
  request: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!request.trim()) {
    throw new Error('create requires a request string or PRD path');
  }

  const source = resolveGoSourceInput(projectRoot, request, flags);
  const promptEnvelope = createPromptImproverEnvelope(projectRoot, source.sourceText, flags);
  const productResolution = buildCanonicalProductSpec(projectRoot, source, promptEnvelope.promptImprover, flags);
  const preflight = getHarnessExecutionPreflight(projectRoot, 'codex');
  const runId = generateRunId('create');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const specPath = path.join(projectRoot, '.agent', 'runs', `${runId}.spec.json`);
  const outputDir = flagString(flags, 'output-dir');
  const overwrite = flags.overwrite === true || flags.force === true;
  const preflightWarnings = preflight.isRunnable ? [] : preflight.blockingIssues;

  writeJson(specPath, productResolution.canonicalSpec);

  const baseArtifact = {
    schemaVersion: 1,
    runId,
    workflow: 'create',
    request,
    sourceType: source.sourceType,
    sourcePath: source.sourcePath,
    normalizedRequest: promptEnvelope.promptImprover.normalizedObjective,
    promptImproverMode: promptEnvelope.mode,
    promptImprover: promptEnvelope.promptImprover,
    contextPilot: promptEnvelope.contextPilot,
    canonicalSpecPath: path.relative(projectRoot, specPath),
    canonicalSpec: productResolution.canonicalSpec,
    laneSelection: {
      laneId: productResolution.lane.id,
      confidence: productResolution.laneConfidence,
      evidence: productResolution.laneEvidence
    },
    packSelection: {
      selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
      requestedPackIds: productResolution.requestedPackIds,
      unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
      missingConfig: productResolution.missingConfig,
      reviewReasons: productResolution.reviewReasons
    },
    preflight,
    preflightWarnings,
    createdAt: isoNow()
  };

  try {
    const bundle = createProductBundle({
      projectRoot,
      spec: productResolution.canonicalSpec,
      lane: productResolution.lane,
      selectedPacks: productResolution.selectedPacks,
      bundleId: runId,
      outputDir,
      overwrite
    });

    writeJson(runPath, {
      ...baseArtifact,
      status: 'HANDOFF_READY',
      bundleDir: path.relative(projectRoot, bundle.bundleDir),
      bundleManifestPath: path.relative(projectRoot, bundle.manifestPath),
      generatedFiles: bundle.files
    });

    if (!jsonMode) {
      console.log(`Create bundle completed: ${runId}`);
      console.log(`Normalized request: ${promptEnvelope.promptImprover.normalizedObjective}`);
      console.log(`Product lane: ${productResolution.canonicalSpec.lane} (${productResolution.canonicalSpec.laneConfidence})`);
      console.log(`Target stack: ${productResolution.canonicalSpec.targetStack}`);
      console.log(`Bundle directory: ${bundle.bundleDir}`);
      console.log(`Bundle manifest: ${bundle.manifestPath}`);
      if (preflightWarnings.length > 0) {
        console.log(`Preflight warnings: ${preflightWarnings.join(' | ')}`);
      }
      console.log(`Run artifact: ${runPath}`);
    }

    return {
      code: 0,
      payload: {
        runId,
        outcome: 'HANDOFF_READY',
        sourceType: source.sourceType,
        sourcePath: source.sourcePath,
        normalizedRequest: promptEnvelope.promptImprover.normalizedObjective,
        canonicalSpec: productResolution.canonicalSpec,
        laneSelection: {
          laneId: productResolution.lane.id,
          confidence: productResolution.laneConfidence,
          evidence: productResolution.laneEvidence
        },
        packSelection: {
          selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
          requestedPackIds: productResolution.requestedPackIds,
          unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
          missingConfig: productResolution.missingConfig,
          reviewReasons: productResolution.reviewReasons
        },
        bundleDir: bundle.bundleDir,
        bundleManifest: bundle.manifestPath,
        generatedFiles: bundle.files,
        preflight,
        preflightWarnings,
        runArtifact: runPath,
        specArtifact: specPath,
        promptImprover: promptEnvelope.promptImprover,
        contextPilot: promptEnvelope.contextPilot
      }
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    writeJson(runPath, {
      ...baseArtifact,
      status: 'FAILED',
      error: message
    });

    return {
      code: 1,
      payload: {
        runId,
        outcome: 'FAILED',
        error: message,
        sourceType: source.sourceType,
        sourcePath: source.sourcePath,
        normalizedRequest: promptEnvelope.promptImprover.normalizedObjective,
        canonicalSpec: productResolution.canonicalSpec,
        preflight,
        preflightWarnings,
        runArtifact: runPath,
        specArtifact: specPath,
        promptImprover: promptEnvelope.promptImprover,
        contextPilot: promptEnvelope.contextPilot
      }
    };
  }
}

function buildMinionExecutionTask(canonicalSpec: CanonicalProductSpec): string {
  const acceptanceSummary = canonicalSpec.acceptanceCriteria.slice(0, 4).join(' ');
  const packSummary = canonicalSpec.enterprisePacks.join(', ') || 'none';
  const deliverySummary = canonicalSpec.deliveryTarget === 'downstream-install'
    ? `downstream install into ${canonicalSpec.downstreamTarget || 'the requested target'}`
    : canonicalSpec.deliveryTarget.replace(/-/gu, ' ');

  return normalizeObjectiveText([
    canonicalSpec.summary,
    `Execute the ${canonicalSpec.lane} lane on ${canonicalSpec.targetStack}.`,
    `Apply enterprise packs: ${packSummary}.`,
    `Delivery target: ${deliverySummary}.`,
    acceptanceSummary
  ].filter(Boolean).join(' '));
}

function resolveMinionValidateMode(flags: Record<string, FlagValue>, canonicalSpec: CanonicalProductSpec): string {
  const explicit = flagString(flags, 'validate');
  if (explicit) {
    return explicit;
  }

  if (canonicalSpec.riskTier === 'high' || canonicalSpec.requiresHumanReview) {
    return 'all';
  }

  if (canonicalSpec.riskTier === 'medium') {
    return 'lint';
  }

  return 'tsc';
}

function runMinionWorkflow(
  projectRoot: string,
  task: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!task.trim()) {
    throw new Error('minion requires a task string');
  }

  const source = resolveGoSourceInput(projectRoot, task, flags);
  const promptEnvelope = createPromptImproverEnvelope(projectRoot, source.sourceText, flags);
  const productResolution = buildCanonicalProductSpec(projectRoot, source, promptEnvelope.promptImprover, flags);
  const preflight = getHarnessExecutionPreflight(projectRoot, 'codex');
  const runId = generateRunId('minion');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const specPath = path.join(projectRoot, '.agent', 'runs', `${runId}.spec.json`);
  const validateMode = resolveMinionValidateMode(flags, productResolution.canonicalSpec);
  const docSyncMode = flagString(flags, 'doc-sync') || 'auto';
  const worktreeMode = flagString(flags, 'worktree') || 'none';
  const delegatedTask = buildMinionExecutionTask(productResolution.canonicalSpec);
  const baseArtifact = {
    schemaVersion: 1,
    runId,
    workflow: 'minion',
    task,
    sourceType: source.sourceType,
    sourcePath: source.sourcePath,
    normalizedTask: promptEnvelope.promptImprover.normalizedObjective,
    promptImproverMode: promptEnvelope.mode,
    promptImprover: promptEnvelope.promptImprover,
    contextPilot: promptEnvelope.contextPilot,
    canonicalSpecPath: path.relative(projectRoot, specPath),
    canonicalSpec: productResolution.canonicalSpec,
    laneSelection: {
      laneId: productResolution.lane.id,
      confidence: productResolution.laneConfidence,
      evidence: productResolution.laneEvidence
    },
    packSelection: {
      selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
      requestedPackIds: productResolution.requestedPackIds,
      unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
      missingConfig: productResolution.missingConfig,
      reviewReasons: productResolution.reviewReasons
    },
    preflight,
    executionPlan: {
      delegatedWorkflow: 'symphony-lite',
      delegatedTask,
      validateMode,
      docSyncMode,
      worktreeMode
    },
    createdAt: isoNow()
  };

  writeJson(specPath, productResolution.canonicalSpec);

  if (!preflight.isRunnable) {
    writeJson(runPath, {
      ...baseArtifact,
      status: 'BLOCKED',
      blockingIssues: preflight.blockingIssues
    });

    return {
      code: 1,
      payload: {
        runId,
        sourceType: source.sourceType,
        sourcePath: source.sourcePath,
        normalizedTask: promptEnvelope.promptImprover.normalizedObjective,
        canonicalSpec: productResolution.canonicalSpec,
        laneSelection: {
          laneId: productResolution.lane.id,
          confidence: productResolution.laneConfidence,
          evidence: productResolution.laneEvidence
        },
        packSelection: {
          selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
          requestedPackIds: productResolution.requestedPackIds,
          unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
          missingConfig: productResolution.missingConfig,
          reviewReasons: productResolution.reviewReasons
        },
        executionPlan: {
          delegatedWorkflow: 'symphony-lite',
          delegatedTask,
          validateMode,
          docSyncMode,
          worktreeMode
        },
        outcome: 'BLOCKED',
        preflight,
        blockingIssues: preflight.blockingIssues,
        runArtifact: runPath,
        specArtifact: specPath,
        promptImprover: promptEnvelope.promptImprover,
        contextPilot: promptEnvelope.contextPilot
      }
    };
  }

  if (isBuilderEligible(productResolution)) {
    const builderResult = routeSupportedProductToBuilder(projectRoot, task, flags, runId);
    const builderPayload = (builderResult.payload || {}) as {
      outcome?: string;
      runArtifact?: string;
      specArtifact?: string;
      bundleDir?: string;
      bundleManifest?: string;
      generatedFiles?: string[];
      preflightWarnings?: string[];
    };
    const outcome = builderPayload.outcome || (builderResult.code === 0 ? 'HANDOFF_READY' : 'FAILED');

    writeJson(runPath, {
      ...baseArtifact,
      status: outcome,
      executionPlan: {
        delegatedWorkflow: 'create',
        delegatedTask,
        validateMode,
        docSyncMode,
        worktreeMode
      },
      resolvedExecutionPath: 'builder',
      builderEligible: true,
      builderInvoked: true,
      downstreamRunArtifact: builderPayload.runArtifact
        ? path.relative(projectRoot, builderPayload.runArtifact)
        : undefined,
      downstreamSpecArtifact: builderPayload.specArtifact
        ? path.relative(projectRoot, builderPayload.specArtifact)
        : undefined,
      bundleDir: typeof builderPayload.bundleDir === 'string'
        ? path.relative(projectRoot, builderPayload.bundleDir)
        : undefined,
      bundleManifestPath: typeof builderPayload.bundleManifest === 'string'
        ? path.relative(projectRoot, builderPayload.bundleManifest)
        : undefined,
      generatedFiles: Array.isArray(builderPayload.generatedFiles) ? builderPayload.generatedFiles : undefined,
      preflightWarnings: Array.isArray(builderPayload.preflightWarnings) ? builderPayload.preflightWarnings : []
    });

    if (!jsonMode) {
      console.log(`Minion execution routed: ${runId}`);
      console.log(`Normalized task: ${promptEnvelope.promptImprover.normalizedObjective}`);
      console.log(`Product lane: ${productResolution.canonicalSpec.lane} (${productResolution.canonicalSpec.laneConfidence})`);
      console.log(`Target stack: ${productResolution.canonicalSpec.targetStack}`);
      console.log(`Enterprise packs: ${productResolution.canonicalSpec.enterprisePacks.join(', ') || 'none'}`);
      console.log('Delegated workflow: create');
      if (typeof builderPayload.bundleDir === 'string') {
        console.log(`Bundle directory: ${builderPayload.bundleDir}`);
      }
      console.log(`Canonical spec: ${specPath}`);
      console.log(`Run artifact: ${runPath}`);
    }

    return {
      code: builderResult.code,
      payload: {
        runId,
        sourceType: source.sourceType,
        sourcePath: source.sourcePath,
        normalizedTask: promptEnvelope.promptImprover.normalizedObjective,
        canonicalSpec: productResolution.canonicalSpec,
        laneSelection: {
          laneId: productResolution.lane.id,
          confidence: productResolution.laneConfidence,
          evidence: productResolution.laneEvidence
        },
        packSelection: {
          selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
          requestedPackIds: productResolution.requestedPackIds,
          unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
          missingConfig: productResolution.missingConfig,
          reviewReasons: productResolution.reviewReasons
        },
        executionPlan: {
          delegatedWorkflow: 'create',
          delegatedTask,
          validateMode,
          docSyncMode,
          worktreeMode
        },
        outcome,
        resolvedExecutionPath: 'builder',
        builderEligible: true,
        builderInvoked: true,
        bundleDir: builderPayload.bundleDir,
        bundleManifest: builderPayload.bundleManifest,
        generatedFiles: builderPayload.generatedFiles,
        preflight,
        preflightWarnings: builderPayload.preflightWarnings || [],
        runArtifact: runPath,
        specArtifact: specPath,
        downstreamRunArtifact: builderPayload.runArtifact,
        downstreamSpecArtifact: builderPayload.specArtifact,
        promptImprover: promptEnvelope.promptImprover,
        contextPilot: promptEnvelope.contextPilot
      }
    };
  }

  const delegatedFlags: Record<string, FlagValue> = {
    ...flags,
    validate: validateMode,
    'doc-sync': docSyncMode,
    worktree: worktreeMode
  };
  const delegatedResult = runSymphonyLite(projectRoot, delegatedTask, delegatedFlags, true);
  const delegatedPayload = (delegatedResult.payload || {}) as {
    outcome?: string;
    runArtifact?: string;
    validateMode?: string;
    docSync?: unknown;
    worktreeMode?: string;
    validations?: unknown;
  };
  writeJson(runPath, {
    ...baseArtifact,
    resolvedExecutionPath: 'autonomous',
    builderEligible: false,
    builderInvoked: false,
    downstreamRunArtifact: delegatedPayload.runArtifact
      ? path.relative(projectRoot, delegatedPayload.runArtifact)
      : undefined,
    status: delegatedPayload.outcome || (delegatedResult.code === 0 ? 'HANDOFF_READY' : 'BLOCKED')
  });

  if (!jsonMode) {
    console.log(`Minion execution routed: ${runId}`);
    console.log(`Normalized task: ${promptEnvelope.promptImprover.normalizedObjective}`);
    console.log(`Product lane: ${productResolution.canonicalSpec.lane} (${productResolution.canonicalSpec.laneConfidence})`);
    console.log(`Target stack: ${productResolution.canonicalSpec.targetStack}`);
    console.log(`Enterprise packs: ${productResolution.canonicalSpec.enterprisePacks.join(', ') || 'none'}`);
    console.log(`Delegated workflow: symphony-lite`);
    console.log(`Validation mode: ${validateMode}`);
    console.log(`Canonical spec: ${specPath}`);
    console.log(`Run artifact: ${runPath}`);
  }

  return {
    code: delegatedResult.code,
    payload: {
      runId,
      sourceType: source.sourceType,
      sourcePath: source.sourcePath,
      normalizedTask: promptEnvelope.promptImprover.normalizedObjective,
      canonicalSpec: productResolution.canonicalSpec,
      laneSelection: {
        laneId: productResolution.lane.id,
        confidence: productResolution.laneConfidence,
        evidence: productResolution.laneEvidence
      },
      packSelection: {
        selectedPackIds: productResolution.selectedPacks.map((pack) => pack.id),
        requestedPackIds: productResolution.requestedPackIds,
        unsupportedRequestedPackIds: productResolution.unsupportedRequestedPackIds,
        missingConfig: productResolution.missingConfig,
        reviewReasons: productResolution.reviewReasons
      },
      executionPlan: {
        delegatedWorkflow: 'symphony-lite',
        delegatedTask,
        validateMode,
        docSyncMode,
        worktreeMode
      },
      outcome: delegatedPayload.outcome || (delegatedResult.code === 0 ? 'HANDOFF_READY' : 'BLOCKED'),
      resolvedExecutionPath: 'autonomous',
      builderEligible: false,
      builderInvoked: false,
      preflight,
      runArtifact: runPath,
      specArtifact: specPath,
      downstreamRunArtifact: delegatedPayload.runArtifact,
      delegatedResult: delegatedPayload,
      promptImprover: promptEnvelope.promptImprover,
      contextPilot: promptEnvelope.contextPilot
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
  const docSyncMode = flagString(flags, 'doc-sync') || 'auto';
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

  let docSync: { mode: string; status: 'skipped' | 'completed' | 'failed'; details?: FullDocUpdatePayload; error?: string } = {
    mode: docSyncMode,
    status: 'skipped'
  };

  if (!failed && docSyncMode !== 'off') {
    try {
      const docResult = runFullDocUpdate(projectRoot, task, {}, true);
      if (docResult.code === 0) {
        docSync = {
          mode: docSyncMode,
          status: 'completed',
          details: (docResult.payload || undefined) as FullDocUpdatePayload | undefined
        };
      } else {
        docSync = {
          mode: docSyncMode,
          status: 'failed',
          error: 'full-doc-update returned non-zero exit code'
        };
      }
    } catch (error) {
      docSync = {
        mode: docSyncMode,
        status: 'failed',
        error: error instanceof Error ? error.message : String(error)
      };
    }
  }

  const outcome = failed || docSync.status === 'failed' ? 'BLOCKED' : 'HANDOFF_READY';
  const runId = generateRunId('symphony');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);

  const artifact = {
    schemaVersion: 1,
    runId,
    workflow: 'symphony-lite',
    task,
    worktreeMode,
    validateMode,
    docSync,
    validations: commandResults,
    status: outcome,
    createdAt: isoNow()
  };

  writeJson(runPath, artifact);

  if (!jsonMode) {
    console.log(`Symphony run completed with status: ${outcome}`);
    console.log(`Run artifact: ${runPath}`);
    if (docSync.status === 'completed' && docSync.details) {
      console.log(`Documentation sync report: ${docSync.details.reportPath}`);
    }
    if (docSync.status === 'failed' && docSync.error) {
      console.log(`Documentation sync failed: ${docSync.error}`);
    }
  }

  return {
    code: failed || docSync.status === 'failed' ? 1 : 0,
    payload: {
      runId,
      outcome,
      validateMode,
      docSync,
      worktreeMode,
      runArtifact: runPath,
      validations: commandResults
    }
  };
}

function parseGitStatusPaths(output: string): string[] {
  return output
    .split('\n')
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .map((line) => line.slice(3).trim())
    .filter(Boolean)
    .map((entry) => {
      const renameSeparator = ' -> ';
      if (entry.includes(renameSeparator)) {
        return entry.split(renameSeparator).pop() || entry;
      }
      return entry;
    });
}

function parseLineList(output: string): string[] {
  return output
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);
}

function runFullDocUpdate(
  projectRoot: string,
  summaryInput: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  const manualChanged = flagStringArray(flags, 'changed');
  const gitLogSubject = executeCommand('git', ['log', '-1', '--pretty=%s'], projectRoot, true);
  const changedFiles = collectChangedFiles(projectRoot, manualChanged);

  const summary = summaryInput.trim() || gitLogSubject.stdout.trim() || 'Documentation synchronization update';

  const mandatoryPaths = ['Task.md', 'CHANGELOG.md', 'docs/project/changelog.md'];
  const mandatoryDocs = mandatoryPaths.map((item) => ({
    path: item,
    exists: fs.existsSync(path.join(projectRoot, item))
  }));

  const checks: Array<{ category: string; matchers: RegExp[]; suggestedPaths: string[] }> = [
    {
      category: 'API/Contracts',
      matchers: [/^src\/api\//u, /\/routes?\//u, /\/controllers?\//u, /\/dto/u, /\/contracts?\//u],
      suggestedPaths: ['docs/api/*', 'docs/contracts/*', 'docs/API_INVENTORY.md']
    },
    {
      category: 'Architecture/Boundaries',
      matchers: [/^docs\/architecture\//u, /\/architecture\//u, /\/module/u],
      suggestedPaths: ['docs/architecture/*', 'docs/decisions/*']
    },
    {
      category: 'Infra/Runtime/Secrets',
      matchers: [/docker/u, /\.env/u, /runtime/u, /config/u, /deploy/u, /terraform/u],
      suggestedPaths: ['.env.example', 'docs/setup/*', 'docs/runbooks/secret-rotation.md']
    },
    {
      category: 'Security/Auth/Payments',
      matchers: [/auth/u, /security/u, /stripe/u, /payment/u, /kyc/u, /compliance/u],
      suggestedPaths: ['docs/security/*', 'docs/governance/*', 'docs/decisions/*']
    },
    {
      category: 'Operations',
      matchers: [/worker/u, /queue/u, /incident/u, /alert/u, /runbook/u],
      suggestedPaths: ['docs/runbooks/*', 'docs/operations/*']
    },
    {
      category: 'Developer Workflow/Tooling',
      matchers: [/README\.md$/u, /CONTRIBUTING\.md$/u, /AGENTS\.md$/u, /CLAUDE\.md$/u, /^scripts\//u],
      suggestedPaths: ['README.md', 'CONTRIBUTING.md', 'AGENTS.md', 'CLAUDE.md']
    }
  ];

  const conditionalDocs = checks
    .filter((check) => changedFiles.some((file) => check.matchers.some((matcher) => matcher.test(file))))
    .map((check) => ({ category: check.category, suggestedPaths: check.suggestedPaths }));

  const reportSlug = slugify(summary) || 'task';
  const baseName = `${dateStamp()}-full-doc-update-${reportSlug}`;
  const reportDir = path.join(projectRoot, 'docs', 'reports');
  fs.mkdirSync(reportDir, { recursive: true });
  const reportPath = path.join(reportDir, `${baseName}.md`);

  const reportLines = [
    '## Documentation Sync Report',
    '',
    `- Task: ${summary}`,
    `- Generated: ${isoNow()}`,
    '',
    '### Changed Files',
    ...(changedFiles.length > 0 ? changedFiles.map((item) => `- ${item}`) : ['- No changed files detected.']),
    '',
    '### Mandatory Docs Status',
    ...mandatoryDocs.map((item) => `- ${item.path}: ${item.exists ? 'present' : 'missing'}`),
    '',
    '### Conditional Docs Suggested',
    ...(conditionalDocs.length > 0
      ? conditionalDocs.flatMap((item) => [`- ${item.category}:`, ...item.suggestedPaths.map((docPath) => `  - ${docPath}`)])
      : ['- No conditional documentation categories triggered.']),
    '',
    '### Docs Intentionally Not Updated',
    '- This workflow creates a documentation sync report and recommendations. Update canonical docs in your normal doc format as needed.',
    '',
    '### Residual Follow-Ups',
    ...mandatoryDocs.filter((item) => !item.exists).map((item) => `- Create or adopt canonical documentation file: ${item.path}`),
    ''
  ];

  fs.writeFileSync(reportPath, `${reportLines.join('\n')}\n`, 'utf8');

  const runId = generateRunId('full-doc-update');
  const runArtifactPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const runArtifact = {
    schemaVersion: 1,
    runId,
    workflow: 'full-doc-update',
    summary,
    changedFiles,
    mandatoryDocs,
    conditionalDocs,
    reportPath,
    createdAt: isoNow()
  };
  writeJson(runArtifactPath, runArtifact);

  if (!jsonMode) {
    console.log('Documentation sync report created:');
    console.log(`- ${reportPath}`);
    console.log(`- ${runArtifactPath}`);
  }

  return {
    code: 0,
    payload: {
      summary,
      reportPath,
      runArtifactPath,
      changedFiles,
      mandatoryDocs,
      conditionalDocs
    }
  };
}

function readEvidencePreview(projectRoot: string, evidencePath: string): EvidencePreview {
  const absolutePath = path.resolve(projectRoot, evidencePath);
  if (!fs.existsSync(absolutePath)) {
    return {
      path: path.relative(projectRoot, absolutePath),
      exists: false,
      kind: 'missing',
      title: path.basename(evidencePath),
      preview: 'File not found.'
    };
  }

  const raw = fs.readFileSync(absolutePath, 'utf8');
  const relativePath = path.relative(projectRoot, absolutePath);

  if (absolutePath.endsWith('.json')) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const title = typeof parsed.runId === 'string' ? `${parsed.runId}` : path.basename(relativePath);
      const previewParts = [
        typeof parsed.workflow === 'string' ? `workflow=${parsed.workflow}` : '',
        typeof parsed.status === 'string' ? `status=${parsed.status}` : '',
        Array.isArray(parsed.gates) ? `gates=${parsed.gates.length}` : '',
        Array.isArray(parsed.events) ? `events=${parsed.events.length}` : ''
      ].filter(Boolean);

      return {
        path: relativePath,
        exists: true,
        kind: 'json',
        title,
        preview: previewParts.join(' | ') || truncate(raw.replace(/\s+/gu, ' '), 220)
      };
    } catch {
      return {
        path: relativePath,
        exists: true,
        kind: 'text',
        title: path.basename(relativePath),
        preview: truncate(raw.replace(/\s+/gu, ' '), 220)
      };
    }
  }

  const lines = parseLineList(raw).slice(0, 8);
  return {
    path: relativePath,
    exists: true,
    kind: absolutePath.endsWith('.md') ? 'markdown' : 'text',
    title: lines[0]?.replace(/^#+\s*/u, '') || path.basename(relativePath),
    preview: truncate(lines.slice(0, 4).join(' '), 220)
  };
}

function buildVisualExplainerArtifact(
  projectRoot: string,
  subject: string,
  flags: Record<string, FlagValue>
): VisualExplainerArtifact {
  const mode = flagString(flags, 'mode') || 'architecture';
  const changedFiles = collectChangedFiles(projectRoot, flagStringArray(flags, 'changed'));
  const explicitEvidence = flagStringArray(flags, 'evidence');
  const evidencePaths = explicitEvidence.length > 0
    ? expandEvidencePaths(projectRoot, explicitEvidence)
    : latestRunArtifactPaths(projectRoot, 1).map((item) => path.relative(projectRoot, item));
  const evidence = evidencePaths.map((item) => readEvidencePreview(projectRoot, item));
  const validationRows: Array<{ name: string; status: string; detail: string }> = [];
  const eventRows: Array<{ type: string; status: string; summary: string }> = [];
  let contextSource: ContextSource = 'standard';

  for (const evidencePath of evidencePaths) {
    const absolutePath = path.resolve(projectRoot, evidencePath);
    if (!fs.existsSync(absolutePath) || !absolutePath.endsWith('.json')) {
      continue;
    }

    try {
      const parsed = JSON.parse(fs.readFileSync(absolutePath, 'utf8')) as Record<string, unknown>;
      const parsedContextSource = typeof parsed.contextSource === 'string' ? parsed.contextSource : '';
      const nestedContextSource =
        typeof parsed.promptImprover === 'object' &&
        parsed.promptImprover &&
        typeof (parsed.promptImprover as { contextSource?: unknown }).contextSource === 'string'
          ? ((parsed.promptImprover as { contextSource: ContextSource }).contextSource)
          : '';
      const pilotSource =
        typeof parsed.contextPilot === 'object' &&
        parsed.contextPilot &&
        typeof (parsed.contextPilot as { source?: unknown }).source === 'string'
          ? ((parsed.contextPilot as { source: ContextSource }).source)
          : '';
      contextSource = (pilotSource || nestedContextSource || parsedContextSource || contextSource) as ContextSource;

      const gates = Array.isArray(parsed.gates) ? parsed.gates as Array<Record<string, unknown>> : [];
      gates.forEach((gate) => {
        validationRows.push({
          name: String(gate.name || gate.gate || 'gate'),
          status: String(gate.status || 'unknown'),
          detail: truncate(String(gate.command || gate.detail || ''), 160)
        });
      });

      const validations = Array.isArray(parsed.validations) ? parsed.validations as Array<Record<string, unknown>> : [];
      validations.forEach((validation) => {
        validationRows.push({
          name: String(validation.id || validation.name || 'validation'),
          status: Number(validation.code || 0) === 0 ? 'pass' : 'fail',
          detail: truncate(
            `${String(validation.command || '')} ${Array.isArray(validation.args) ? validation.args.join(' ') : ''}`.trim(),
            160
          )
        });
      });

      const events = Array.isArray(parsed.events) ? parsed.events as Array<Record<string, unknown>> : [];
      events.forEach((event) => {
        eventRows.push({
          type: String(event.eventType || 'event'),
          status: String(event.status || 'info'),
          summary: truncate(String(event.summary || ''), 160)
        });
      });
    } catch {
      // Ignore malformed evidence files here; preview already captures the fallback.
    }
  }

  const metrics: VisualExplainerMetrics = {
    changedFilesCount: changedFiles.length,
    evidenceCount: evidence.length,
    validationsPass: validationRows.filter((row) => row.status === 'pass').length,
    validationsFail: validationRows.filter((row) => row.status === 'fail').length,
    eventsCount: eventRows.length
  };

  const summaryBullets = uniqueStrings([
    `${mode} explainer generated for "${subject}".`,
    changedFiles.length > 0 ? `${changedFiles.length} changed files detected in the current repo state.` : 'No current changed files were detected; report is evidence-driven only.',
    validationRows.length > 0
      ? `${metrics.validationsPass} validation checks passed and ${metrics.validationsFail} failed across referenced artifacts.`
      : 'No validation evidence was found in the supplied artifacts.',
    contextSource !== 'standard' ? `Context source expanded via ${contextSource}.` : 'Context source remained on the standard project-context path.'
  ]);

  const citations = uniqueStrings([
    ...changedFiles.slice(0, 8).map((item) => `git diff/git status -> ${item}`),
    ...evidence.filter((item) => item.exists).map((item) => item.path)
  ]);

  return {
    mode,
    subject,
    generatedAt: isoNow(),
    changedFiles,
    evidence,
    validationRows,
    eventRows,
    contextSource,
    summaryBullets,
    citations,
    metrics
  };
}

function renderVisualExplainerMarkdown(artifact: VisualExplainerArtifact): string {
  return [
    `# Visual Explainer: ${artifact.subject}`,
    '',
    `- Mode: ${artifact.mode}`,
    `- Generated: ${artifact.generatedAt}`,
    `- Context source: ${artifact.contextSource}`,
    '',
    '## Summary',
    ...artifact.summaryBullets.map((item) => `- ${item}`),
    '',
    '## Metrics',
    `- Changed files: ${artifact.metrics.changedFilesCount}`,
    `- Evidence items: ${artifact.metrics.evidenceCount}`,
    `- Validation pass/fail: ${artifact.metrics.validationsPass}/${artifact.metrics.validationsFail}`,
    `- Event rows: ${artifact.metrics.eventsCount}`,
    '',
    '## Evidence',
    ...(artifact.evidence.length > 0
      ? artifact.evidence.map((item) => `- ${item.path} (${item.kind}): ${item.preview}`)
      : ['- No evidence files supplied.']),
    '',
    '## Validation Signals',
    ...(artifact.validationRows.length > 0
      ? artifact.validationRows.map((item) => `- ${item.name}: ${item.status} — ${item.detail}`)
      : ['- No validation rows found.']),
    '',
    '## Event Signals',
    ...(artifact.eventRows.length > 0
      ? artifact.eventRows.map((item) => `- ${item.type}: ${item.status} — ${item.summary}`)
      : ['- No event rows found.']),
    '',
    '## Changed Files',
    ...(artifact.changedFiles.length > 0 ? artifact.changedFiles.map((item) => `- ${item}`) : ['- None detected.']),
    '',
    '## Citations',
    ...(artifact.citations.length > 0 ? artifact.citations.map((item) => `- ${item}`) : ['- No citations available.']),
    ''
  ].join('\n');
}

function renderVisualExplainerHtml(artifact: VisualExplainerArtifact): string {
  const evidenceCards = artifact.evidence.length > 0
    ? artifact.evidence
        .map(
          (item) => `<article class="card">
            <div class="eyebrow">${escapeHtml(item.kind.toUpperCase())}</div>
            <h3>${escapeHtml(item.title)}</h3>
            <p class="meta">${escapeHtml(item.path)}</p>
            <p>${escapeHtml(item.preview)}</p>
          </article>`
        )
        .join('')
    : '<article class="card"><h3>No evidence provided</h3><p>Supply --evidence paths or rely on the latest run artifact.</p></article>';

  const validationRows = artifact.validationRows.length > 0
    ? artifact.validationRows
        .map(
          (item) => `<tr><td>${escapeHtml(item.name)}</td><td><span class="status status-${escapeHtml(item.status)}">${escapeHtml(item.status)}</span></td><td>${escapeHtml(item.detail)}</td></tr>`
        )
        .join('')
    : '<tr><td colspan="3">No validation signals found.</td></tr>';

  const eventRows = artifact.eventRows.length > 0
    ? artifact.eventRows
        .map(
          (item) => `<tr><td>${escapeHtml(item.type)}</td><td><span class="status status-${escapeHtml(item.status)}">${escapeHtml(item.status)}</span></td><td>${escapeHtml(item.summary)}</td></tr>`
        )
        .join('')
    : '<tr><td colspan="3">No event signals found.</td></tr>';

  const changedFilesList = artifact.changedFiles.length > 0
    ? artifact.changedFiles.map((item) => `<li>${escapeHtml(item)}</li>`).join('')
    : '<li>No changed files detected.</li>';

  const citationsList = artifact.citations.length > 0
    ? artifact.citations.map((item) => `<li>${escapeHtml(item)}</li>`).join('')
    : '<li>No citations available.</li>';

  const summaryList = artifact.summaryBullets.map((item) => `<li>${escapeHtml(item)}</li>`).join('');

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Visual Explainer: ${escapeHtml(artifact.subject)}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&display=swap" rel="stylesheet" />
    <style>
      :root {
        --bg: #f6f4ef;
        --surface: #ffffff;
        --surface-alt: #ecf2f0;
        --border: rgba(0, 0, 0, 0.08);
        --text: #122025;
        --text-dim: #5d6a70;
        --accent: #0f766e;
        --accent-soft: rgba(15, 118, 110, 0.1);
        --warning: #b45309;
        --warning-soft: rgba(180, 83, 9, 0.12);
        --danger: #9f1239;
        --danger-soft: rgba(159, 18, 57, 0.12);
        --success: #3f6212;
        --success-soft: rgba(63, 98, 18, 0.12);
        --font-body: 'IBM Plex Sans', system-ui, sans-serif;
        --font-mono: 'IBM Plex Mono', monospace;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --bg: #151917;
          --surface: #1d2321;
          --surface-alt: #26302d;
          --border: rgba(255, 255, 255, 0.08);
          --text: #edf2ee;
          --text-dim: #9fb1a9;
          --accent-soft: rgba(94, 234, 212, 0.14);
          --warning-soft: rgba(251, 191, 36, 0.14);
          --danger-soft: rgba(253, 164, 175, 0.14);
          --success-soft: rgba(190, 242, 100, 0.14);
        }
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        font-family: var(--font-body);
        color: var(--text);
        background:
          radial-gradient(circle at top left, var(--accent-soft), transparent 35%),
          radial-gradient(circle at bottom right, var(--warning-soft), transparent 32%),
          var(--bg);
      }
      main {
        max-width: 1200px;
        margin: 0 auto;
        padding: 32px 20px 56px;
      }
      .hero {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 24px;
        padding: 28px;
        box-shadow: 0 14px 40px rgba(0, 0, 0, 0.06);
      }
      .eyebrow {
        font-family: var(--font-mono);
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--accent);
      }
      h1 {
        margin: 12px 0 8px;
        font-size: clamp(2rem, 4vw, 3.3rem);
        line-height: 1.04;
      }
      .meta {
        color: var(--text-dim);
        font-size: 0.95rem;
      }
      .summary {
        margin-top: 18px;
        display: grid;
        gap: 10px;
      }
      .metrics {
        margin-top: 28px;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 14px;
      }
      .metric {
        background: var(--surface-alt);
        border: 1px solid var(--border);
        border-radius: 18px;
        padding: 16px;
      }
      .metric .value {
        font-size: 1.9rem;
        font-weight: 700;
        margin-top: 6px;
      }
      .sections {
        margin-top: 28px;
        display: grid;
        gap: 20px;
      }
      .panel {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 22px;
        padding: 22px;
      }
      .panel h2 {
        margin: 0 0 16px;
        font-size: 1.25rem;
      }
      .card-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
      }
      .card {
        background: var(--surface-alt);
        border: 1px solid var(--border);
        border-radius: 18px;
        padding: 16px;
        min-width: 0;
      }
      .card h3 {
        margin: 8px 0 6px;
        font-size: 1rem;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        font-size: 0.95rem;
      }
      th, td {
        text-align: left;
        padding: 10px 12px;
        border-bottom: 1px solid var(--border);
        vertical-align: top;
      }
      th {
        font-family: var(--font-mono);
        font-size: 0.78rem;
        letter-spacing: 0.05em;
        text-transform: uppercase;
        color: var(--text-dim);
      }
      .status {
        display: inline-flex;
        align-items: center;
        border-radius: 999px;
        padding: 4px 10px;
        font-size: 0.8rem;
        font-family: var(--font-mono);
      }
      .status-pass { background: var(--success-soft); color: var(--success); }
      .status-fail { background: var(--danger-soft); color: var(--danger); }
      .status-info, .status-skipped, .status-unknown { background: var(--accent-soft); color: var(--accent); }
      ul {
        margin: 0;
        padding-left: 20px;
        display: grid;
        gap: 8px;
      }
      code {
        font-family: var(--font-mono);
        font-size: 0.9em;
      }
      @media (max-width: 720px) {
        main { padding: 20px 14px 40px; }
        .hero, .panel { padding: 18px; border-radius: 18px; }
      }
    </style>
  </head>
  <body>
    <main>
      <section class="hero">
        <div class="eyebrow">${escapeHtml(artifact.mode)} explainer</div>
        <h1>${escapeHtml(artifact.subject)}</h1>
        <p class="meta">Generated ${escapeHtml(artifact.generatedAt)} · Context source: <code>${escapeHtml(artifact.contextSource)}</code></p>
        <ul class="summary">${summaryList}</ul>
        <div class="metrics">
          <article class="metric"><div class="eyebrow">Changed files</div><div class="value">${artifact.metrics.changedFilesCount}</div></article>
          <article class="metric"><div class="eyebrow">Evidence</div><div class="value">${artifact.metrics.evidenceCount}</div></article>
          <article class="metric"><div class="eyebrow">Validation</div><div class="value">${artifact.metrics.validationsPass}/${artifact.metrics.validationsFail}</div></article>
          <article class="metric"><div class="eyebrow">Events</div><div class="value">${artifact.metrics.eventsCount}</div></article>
        </div>
      </section>
      <section class="sections">
        <section class="panel">
          <h2>Evidence</h2>
          <div class="card-grid">${evidenceCards}</div>
        </section>
        <section class="panel">
          <h2>Validation Signals</h2>
          <table>
            <thead><tr><th>Check</th><th>Status</th><th>Detail</th></tr></thead>
            <tbody>${validationRows}</tbody>
          </table>
        </section>
        <section class="panel">
          <h2>Event Signals</h2>
          <table>
            <thead><tr><th>Event</th><th>Status</th><th>Summary</th></tr></thead>
            <tbody>${eventRows}</tbody>
          </table>
        </section>
        <section class="panel">
          <h2>Changed Files</h2>
          <ul>${changedFilesList}</ul>
        </section>
        <section class="panel">
          <h2>Citations</h2>
          <ul>${citationsList}</ul>
        </section>
      </section>
    </main>
  </body>
</html>`;
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

  const artifact = buildVisualExplainerArtifact(projectRoot, subject, flags);
  const reportSlug = slugify(subject) || 'report';
  const baseName = `${dateStamp()}-${reportSlug}`;
  const reportDir = path.join(projectRoot, 'docs', 'reports');
  fs.mkdirSync(reportDir, { recursive: true });

  const markdownPath = path.join(reportDir, `${baseName}.md`);
  const htmlPath = path.join(reportDir, `${baseName}.html`);

  fs.writeFileSync(markdownPath, `${renderVisualExplainerMarkdown(artifact)}\n`, 'utf8');
  fs.writeFileSync(htmlPath, renderVisualExplainerHtml(artifact), 'utf8');

  if (!jsonMode) {
    console.log(`Visual explainer created:`);
    console.log(`- ${markdownPath}`);
    console.log(`- ${htmlPath}`);
  }

  return {
    code: 0,
    payload: {
      subject,
      mode: artifact.mode,
      markdownPath,
      htmlPath,
      evidence: artifact.evidence.map((item) => item.path),
      contextSource: artifact.contextSource,
      citations: artifact.citations
    }
  };
}

function runHydraSidecar(
  projectRoot: string,
  objective: string,
  flags: Record<string, FlagValue>,
  jsonMode: boolean
): CommandResult {
  if (!objective.trim()) {
    throw new Error('hydra-sidecar requires an objective string');
  }

  const promptEnvelope = createPromptImproverEnvelope(projectRoot, objective, flags);
  const decision = runHydraSidecarDecision(objective, flags, promptEnvelope.promptImprover, promptEnvelope.contextPilot);
  const runId = generateRunId('hydra-sidecar');
  const runPath = path.join(projectRoot, '.agent', 'runs', `${runId}.json`);
  const artifact = {
    schemaVersion: 1,
    runId,
    workflow: 'hydra-sidecar',
    objective,
    promptImprover: promptEnvelope.promptImprover,
    contextPilot: promptEnvelope.contextPilot,
    hydraSidecar: decision,
    createdAt: isoNow()
  };

  writeJson(runPath, artifact);

  if (!jsonMode) {
    console.log(`Hydra sidecar decision recorded: ${decision.mode} (${decision.status})`);
    console.log(`Suggested route: ${decision.route}`);
    console.log(`Run artifact: ${runPath}`);
  }

  return {
    code: decision.status === 'blocked' ? 1 : 0,
    payload: {
      runId,
      runArtifact: runPath,
      promptImprover: promptEnvelope.promptImprover,
      contextPilot: promptEnvelope.contextPilot,
      hydraSidecar: decision
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

    if (slug === 'go') {
      return runGoWorkflow(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'create') {
      return runCreateWorkflow(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'minion') {
      return runMinionWorkflow(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'paperclip-extracted') {
      return runPaperclipExtracted(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'symphony-lite') {
      return runSymphonyLite(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'prompt-improver') {
      return runPromptImprover(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'visual-explainer') {
      return runVisualExplainer(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'full-doc-update') {
      return runFullDocUpdate(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'hydra-sidecar') {
      return runHydraSidecar(projectRoot, runtimeInput, flags, jsonMode);
    }

    if (slug === 'agentic-status') {
      return runAgenticStatusWorkflow(projectRoot, runtimeInput, flags, jsonMode);
    }

    const paths = getHarnessPaths(projectRoot);
    const runId = generateRunId(`workflow-${slug}`);
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
  if (!action || !['create', 'init', 'gate', 'mcp', 'event', 'feedback', 'persona', 'context', 'complete'].includes(action)) {
    throw new Error('Usage: gg run <create|init|gate|mcp|event|feedback|persona|context|complete> [--key value]');
  }

  if (action === 'create') {
    const { flags } = parseArgs(argv);
    const runtime = parseRuntimeId(flagString(flags, 'runtime'), 'codex');
    const classification = parseClassification(flagString(flags, 'classification'), 'TASK');
    const summary = flagString(flags, 'summary') || '';
    const runId = flagString(flags, 'id') || `run-${Date.now().toString(36)}`;
    const created = createRunState(projectRoot, {
      runId,
      summary,
      classification,
      coordinatorRuntime: runtime
    });

    const scriptPath = path.join(projectRoot, 'scripts', 'agent-run-artifact.mjs');
    const artifactArgs = [scriptPath, 'init', '--id', runId, '--runtime', runtime, '--classification', classification];
    pushOptionalArtifactFlag(artifactArgs, flags, 'summary');
    pushOptionalArtifactFlag(artifactArgs, flags, 'context-source');
    pushOptionalArtifactFlag(artifactArgs, flags, 'integration-flags');
    pushOptionalArtifactFlag(artifactArgs, flags, 'prompt-version');
    pushOptionalArtifactFlag(artifactArgs, flags, 'workflow-version');
    pushOptionalArtifactFlag(artifactArgs, flags, 'blueprint-version');
    pushOptionalArtifactFlag(artifactArgs, flags, 'tool-bundle');
    pushOptionalArtifactFlag(artifactArgs, flags, 'risk-tier');

    const artifactResult = executeCommand('node', artifactArgs, projectRoot, true);
    if (artifactResult.code !== 0) {
      throw new Error((artifactResult.stderr || artifactResult.stdout).trim() || 'Failed to initialize run artifact');
    }

    writeRunState(projectRoot, created.run);

    if (!jsonMode) {
      console.log(`Created control-plane run: ${runId}`);
      console.log(`State file: ${path.join(projectRoot, '.agent', 'control-plane', 'runs', `${runId}.json`)}`);
      console.log(`Artifact file: ${path.join(projectRoot, '.agent', 'runs', `${runId}.json`)}`);
    }

    return {
      code: 0,
      payload: {
        runId,
        runtime,
        classification,
        summary,
        stateFile: path.join(projectRoot, '.agent', 'control-plane', 'runs', `${runId}.json`),
        artifactFile: path.join(projectRoot, '.agent', 'runs', `${runId}.json`)
      }
    };
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

async function commandWorker(
  projectRoot: string,
  action: string | undefined,
  argv: string[],
  jsonMode: boolean
): Promise<CommandResult> {
  if (!action || !['spawn', 'delegate', 'launch', 'status'].includes(action)) {
    throw new Error('Usage: gg worker <spawn|delegate|launch|status> [--key value]');
  }

  const { flags, positionals } = parseArgs(argv);

  if (action === 'status') {
    const runId = flagString(flags, 'run-id');
    if (!runId) {
      throw new Error('Usage: gg worker status --run-id <runId> [--agent-id <agentId>]');
    }
    const agentId = flagString(flags, 'agent-id');
    const workers = listWorkers(projectRoot, runId, agentId);
    if (!jsonMode) {
      for (const worker of workers) {
        console.log(
          `${worker.agentId}\t${worker.runtime}\t${worker.role}\t${worker.persona.personaId}\t${worker.status}\t${worker.execution.status}`
        );
      }
    }
    return { code: 0, payload: { runId, workers } };
  }

  const runId = flagString(flags, 'run-id');
  if (!runId) {
    throw new Error(`Usage: gg worker ${action} --run-id <runId> ...`);
  }

  if (action === 'launch') {
    const agentId = flagString(flags, 'agent-id');
    if (!agentId) {
      throw new Error('Usage: gg worker launch --run-id <runId> --agent-id <agentId> [--dry-run]');
    }

    const launched = await executeWorker(projectRoot, {
      runId,
      agentId,
      dryRun: Boolean(flags['dry-run'])
    });

    if (!jsonMode) {
      console.log(`Worker launch ${launched.execution.status}: ${agentId}`);
      console.log(`Summary: ${launched.execution.summary}`);
      if (launched.execution.requestFile) {
        console.log(`Request file: ${launched.execution.requestFile}`);
      }
      if (launched.execution.transcriptFile) {
        console.log(`Transcript file: ${launched.execution.transcriptFile}`);
      }
      if (launched.execution.error) {
        console.log(`Error: ${launched.execution.error}`);
      }
    }

    return {
      code: launched.execution.status === 'completed' ? 0 : 1,
      payload: {
        runId,
        worker: launched.worker,
        execution: launched.execution
      }
    };
  }

  const taskSummary = flagString(flags, 'task') || positionals.join(' ').trim();
  if (!taskSummary) {
    throw new Error(`Usage: gg worker ${action} --run-id <runId> --task "<summary>" ...`);
  }

  const classification = parseClassification(flagString(flags, 'classification'), 'TASK');
  const role = parseWorkerRole(flagString(flags, 'role'), 'builder');
  const persona = resolvePersonaPacketForTask(projectRoot, flags, taskSummary, classification);
  const toolBundle = flagStringArray(flags, 'tool');
  const launchTransport = parseLaunchTransport(flagString(flags, 'launch-transport'));

  if (action === 'spawn') {
    const runtime = parseRuntimeId(flagString(flags, 'runtime'), 'kimi');
    const agentId = flagString(flags, 'agent-id') || generateWorkerId(role);
    const worktree = flagString(flags, 'worktree') || ensureHarnessWorktree(projectRoot, runId, agentId);
    const spawned = spawnWorker(projectRoot, {
      runId,
      runtime,
      agentId,
      parentAgentId: flagString(flags, 'parent-agent-id') || null,
      role,
      taskSummary,
      persona: persona.packet,
      toolBundle,
      worktree,
      launchTransport
    });
    const launched = flags.execute
      ? await executeWorker(projectRoot, {
          runId,
          agentId: spawned.worker.agentId,
          dryRun: Boolean(flags['dry-run'])
        })
      : null;

    if (!jsonMode) {
      console.log(`Spawn recorded for ${spawned.worker.agentId}`);
      console.log(`Runtime: ${spawned.worker.runtime}`);
      console.log(`Persona: ${spawned.worker.persona.personaId} (${persona.source})`);
      console.log(`Transport: ${spawned.worker.launchTransport}`);
      if (launched) {
        console.log(`Execution: ${launched.execution.status}`);
        console.log(`Summary: ${launched.execution.summary}`);
      }
    }

    return {
      code: !launched || launched.execution.status === 'completed' ? 0 : 1,
      payload: {
        runId,
        worker: launched?.worker || spawned.worker,
        personaSource: persona.source,
        execution: launched?.execution || null
      }
    };
  }

  const fromAgentId = flagString(flags, 'from-agent-id');
  if (!fromAgentId) {
    throw new Error('Usage: gg worker delegate --run-id <runId> --from-agent-id <agentId> --to-runtime <runtime> --task "<summary>"');
  }
  const toRuntime = parseRuntimeId(flagString(flags, 'to-runtime'), 'kimi');
  const delegatedAgentId = flagString(flags, 'agent-id') || generateWorkerId(role);
  const worktree = flagString(flags, 'worktree') || ensureHarnessWorktree(projectRoot, runId, delegatedAgentId);
  const delegated = delegateTask(projectRoot, {
    runId,
    fromAgentId,
    agentId: delegatedAgentId,
    toRuntime,
    role,
    taskSummary,
    classification,
    persona: persona.packet,
    boardApproved: Boolean(flags['board-approved']),
    toolBundle,
    worktree,
    launchTransport
  } as any);
  const launched = flags.execute && delegated.worker
    ? await executeWorker(projectRoot, {
        runId,
        agentId: delegated.worker.agentId,
        dryRun: Boolean(flags['dry-run'])
      })
    : null;

  if (!jsonMode) {
    console.log(`Delegation ${delegated.decision.status}: ${delegated.decision.decisionId}`);
    console.log(`Persona: ${delegated.decision.personaId} (${persona.source})`);
    console.log(`Rationale: ${delegated.decision.rationale}`);
    if (delegated.worker) {
      console.log(`Spawned worker: ${delegated.worker.agentId}`);
    }
    if (launched) {
      console.log(`Execution: ${launched.execution.status}`);
      console.log(`Summary: ${launched.execution.summary}`);
    }
  }

  return {
      code: delegated.decision.status === 'approved' && (!launched || launched.execution.status === 'completed') ? 0 : 1,
      payload: {
        runId,
        decision: delegated.decision,
        worker: launched?.worker || delegated.worker,
        personaSource: persona.source,
        execution: launched?.execution || null
      }
  };
}

function commandBus(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  if (!action || !['post', 'inbox', 'ack'].includes(action)) {
    throw new Error('Usage: gg bus <post|inbox|ack> [--key value]');
  }

  const { flags } = parseArgs(argv);
  const runId = flagString(flags, 'run-id');
  if (!runId) {
    throw new Error(`Usage: gg bus ${action} --run-id <runId> ...`);
  }

  if (action === 'post') {
    const fromAgentId = flagString(flags, 'from-agent-id');
    const toAgentId = flagString(flags, 'to-agent-id');
    const type = (flagString(flags, 'type') || 'TASK_SPEC') as
      | 'TASK_SPEC'
      | 'PROGRESS'
      | 'BLOCKED'
      | 'DELEGATE_REQUEST'
      | 'HANDOFF_READY'
      | 'SYSTEM';

    if (!fromAgentId || !toAgentId) {
      throw new Error('Usage: gg bus post --run-id <runId> --from-agent-id <id> --to-agent-id <id> --type <type> [--payload <json>]');
    }

    const posted = postMessage(projectRoot, {
      runId,
      fromAgentId,
      toAgentId,
      type,
      payload: parsePayload(flagString(flags, 'payload')),
      requiresAck: Boolean(flags['requires-ack'])
    });

    if (!jsonMode) {
      console.log(`Posted message: ${posted.message.messageId}`);
    }
    return { code: 0, payload: { runId, message: posted.message } };
  }

  if (action === 'inbox') {
    const agentId = flagString(flags, 'agent-id');
    if (!agentId) {
      throw new Error('Usage: gg bus inbox --run-id <runId> --agent-id <id> [--cursor <n>]');
    }
    const inbox = fetchInbox(projectRoot, {
      runId,
      agentId,
      cursor: intFlagAllowZero(flags, 'cursor', 0)
    });

    if (!jsonMode) {
      for (const message of inbox.messages) {
        console.log(`${message.cursor}\t${message.messageId}\t${message.type}\t${message.fromAgentId}`);
      }
    }
    return { code: 0, payload: { runId, agentId, messages: inbox.messages } };
  }

  const agentId = flagString(flags, 'agent-id');
  const messageId = flagString(flags, 'message-id');
  if (!agentId || !messageId) {
    throw new Error('Usage: gg bus ack --run-id <runId> --agent-id <id> --message-id <messageId>');
  }
  const acked = ackMessage(projectRoot, { runId, agentId, messageId });
  if (!jsonMode) {
    console.log(`Acknowledged message: ${acked.message.messageId}`);
  }
  return { code: 0, payload: { runId, message: acked.message } };
}

function commandRuntime(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  if (!action || !['activate', 'status'].includes(action)) {
    throw new Error('Usage: gg runtime <activate|status> [targetDir] [--runtime codex|claude|kimi] [--codex-home <path>]');
  }

  const scriptPath = path.join(projectRoot, 'scripts', 'runtime-project-sync.mjs');
  const { flags, positionals } = parseArgs(argv);
  const targetRoot = path.resolve(positionals[0] || projectRoot);
  const args = [scriptPath, action, targetRoot];
  const runtime = flagString(flags, 'runtime');
  const codexHome = flagString(flags, 'codex-home');

  if (runtime) {
    args.push('--runtime', runtime);
  }
  if (codexHome) {
    args.push('--codex-home', codexHome);
  }
  if (jsonMode) {
    args.push('--json');
  }

  const result = executeCommand('node', args, projectRoot, true);
  if (!jsonMode) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    return { code: result.code };
  }

  return {
    code: result.code,
    payload: result.stdout.trim() ? JSON.parse(result.stdout) : null
  };
}

function commandCodex(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  const args = ['--runtime', 'codex', ...argv];
  return commandRuntime(projectRoot, action, args, jsonMode);
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

function parseScalarFlagValue(raw: string): unknown {
  const trimmed = raw.trim();
  if (!trimmed.length) {
    return '';
  }
  if (trimmed === 'null') return null;
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (/^-?\d+(?:\.\d+)?$/u.test(trimmed)) {
    return Number(trimmed);
  }
  if ((trimmed.startsWith('[') && trimmed.endsWith(']')) || (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return trimmed;
    }
  }
  return trimmed;
}

function parseJsonObjectFlag(raw: string, label: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error(`${label} must be a JSON object`);
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'unknown error';
    throw new Error(`Invalid ${label}: ${detail}`);
  }
}

function parseJsonArrayFlag(raw: string, label: string): Array<Record<string, unknown>> {
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.some((item) => !item || typeof item !== 'object' || Array.isArray(item))) {
      throw new Error(`${label} must be a JSON array of objects`);
    }
    return parsed as Array<Record<string, unknown>>;
  } catch (error) {
    const detail = error instanceof Error ? error.message : 'unknown error';
    throw new Error(`Invalid ${label}: ${detail}`);
  }
}

interface HarnessUIRPCRequest {
  type: 'snapshot' | 'command';
  command?: Record<string, unknown>;
}

interface HarnessUIRPCResponse {
  ok: boolean;
  processedCommandId?: string | null;
  snapshot?: unknown;
  error?: string | null;
}

function parseHarnessUIRPCRequest(raw: string, label: string): HarnessUIRPCRequest {
  const parsed = parseJsonObjectFlag(raw, label) as Record<string, unknown>;
  if (parsed.type !== 'snapshot' && parsed.type !== 'command') {
    throw new Error(`Invalid ${label}: type must be "snapshot" or "command"`);
  }
  return parsed as unknown as HarnessUIRPCRequest;
}

async function sendHarnessUIRPCRequest(host: string, port: number, request: HarnessUIRPCRequest): Promise<HarnessUIRPCResponse> {
  return await new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port }, () => {
      socket.end(JSON.stringify(request));
    });
    const chunks: Buffer[] = [];

    socket.on('data', (chunk) => {
      chunks.push(chunk);
    });
    socket.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8').trim();
        resolve(JSON.parse(raw) as HarnessUIRPCResponse);
      } catch (error) {
        const detail = error instanceof Error ? error.message : 'unknown error';
        reject(new Error(`Invalid harness UI RPC response: ${detail}`));
      }
    });
    socket.on('error', (error) => {
      reject(error);
    });
  });
}

function buildHarnessUICommandEnvelope(flags: Record<string, FlagValue>): Record<string, unknown> {
  const rawCommand = flagString(flags, 'command');
  if (rawCommand) {
    return parseJsonObjectFlag(rawCommand, '--command');
  }

  const commandFile = flagString(flags, 'command-file');
  if (commandFile) {
    return parseJsonObjectFlag(fs.readFileSync(path.resolve(commandFile), 'utf8'), '--command-file');
  }

  const type = flagString(flags, 'type');
  if (!type) {
    throw new Error('Usage: gg harness ui command (--command <json> | --command-file <path> | --type <type> [--id <value>] [...])');
  }

  const command: Record<string, unknown> = { type };
  const id = flagString(flags, 'id');
  if (id) command.id = id;

  const fieldMap: Array<[string, string]> = [
    ['tab', 'tab'],
    ['run-id', 'runId'],
    ['agent-id', 'agentId'],
    ['title', 'title'],
    ['runtime', 'runtime'],
    ['text', 'text'],
    ['patch', 'patch'],
    ['reason', 'reason'],
    ['problem-id', 'problemId'],
    ['problem-action', 'problemAction'],
    ['path', 'path'],
    ['source-label', 'sourceLabel'],
    ['worktree-path', 'worktreePath'],
    ['worktree-label', 'worktreeLabel'],
    ['panel', 'panel'],
    ['explorer-root', 'explorerRoot'],
    ['preset', 'preset'],
    ['working-directory', 'workingDirectory'],
    ['destination', 'destination']
  ];

  for (const [flag, key] of fieldMap) {
    const value = flagString(flags, flag);
    if (value !== undefined) {
      command[key] = value;
    }
  }

  if (flags['dry-run'] !== undefined) {
    command.dryRun = booleanFlag(flags, 'dry-run', false);
  }

  return command;
}

async function commandHarnessUI(argv: string[], jsonMode: boolean): Promise<CommandResult> {
  const [uiAction, ...rest] = argv;
  if (!uiAction || !['snapshot', 'command', 'batch'].includes(uiAction)) {
    throw new Error('Usage: gg harness ui <snapshot|command|batch> [options]');
  }

  const { flags } = parseArgs(rest);
  const host = flagString(flags, 'host') || '127.0.0.1';
  const port = intFlag(flags, 'port', 7331);

  if (uiAction === 'snapshot') {
    const request: HarnessUIRPCRequest = { type: 'snapshot' };
    const response = await sendHarnessUIRPCRequest(host, port, request);
    if (!jsonMode) {
      console.log(JSON.stringify(response, null, 2));
    }
    return {
      code: response.ok ? 0 : 1,
      payload: { host, port, request, response }
    };
  }

  if (uiAction === 'command') {
    const rawRequest = flagString(flags, 'request');
    const requestFile = flagString(flags, 'request-file');
    const request = rawRequest
      ? parseHarnessUIRPCRequest(rawRequest, '--request')
      : requestFile
        ? parseHarnessUIRPCRequest(fs.readFileSync(path.resolve(requestFile), 'utf8'), '--request-file')
        : { type: 'command' as const, command: buildHarnessUICommandEnvelope(flags) };
    const response = await sendHarnessUIRPCRequest(host, port, request);
    if (!jsonMode) {
      console.log(JSON.stringify(response, null, 2));
    }
    return {
      code: response.ok ? 0 : 1,
      payload: { host, port, request, response }
    };
  }

  const rawCommands = flagString(flags, 'commands');
  const commandsFile = flagString(flags, 'commands-file');
  const commands = rawCommands
    ? parseJsonArrayFlag(rawCommands, '--commands')
    : commandsFile
      ? parseJsonArrayFlag(fs.readFileSync(path.resolve(commandsFile), 'utf8'), '--commands-file')
      : null;
  if (!commands || commands.length === 0) {
    throw new Error('Usage: gg harness ui batch (--commands <json-array> | --commands-file <path>) [--host <host>] [--port <port>]');
  }

  const responses: HarnessUIRPCResponse[] = [];
  for (const command of commands) {
    responses.push(await sendHarnessUIRPCRequest(host, port, { type: 'command', command }));
  }
  const failed = responses.find((response) => !response.ok);

  if (!jsonMode) {
    console.log(JSON.stringify(responses, null, 2));
  }

  return {
    code: failed ? 1 : 0,
    payload: { host, port, requests: commands, responses }
  };
}

function setByDotPath(target: Record<string, unknown>, dotPath: string, value: unknown): void {
  const parts = dotPath.split('.').map((part) => part.trim()).filter(Boolean);
  if (!parts.length) {
    throw new Error('Harness settings key must not be empty');
  }

  let cursor: Record<string, unknown> = target;
  for (let index = 0; index < parts.length - 1; index += 1) {
    const key = parts[index];
    const existing = cursor[key];
    if (!existing || typeof existing !== 'object' || Array.isArray(existing)) {
      cursor[key] = {};
    }
    cursor = cursor[key] as Record<string, unknown>;
  }

  cursor[parts[parts.length - 1]] = value;
}

async function commandHarness(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): Promise<CommandResult> {
  if (!action || !['settings', 'diagram', 'ui'].includes(action)) {
    throw new Error('Usage: gg harness <settings|diagram|ui> ...');
  }

  if (action === 'ui') {
    return await commandHarnessUI(argv, jsonMode);
  }

  if (action === 'diagram') {
    const { flags } = parseArgs(argv);
    const format = flagString(flags, 'format') === 'html' ? 'html' : 'json';
    const settings = readHarnessSettings(projectRoot);
    const artifactPath = resolveHarnessDiagramPath(projectRoot, settings);

    if (!jsonMode && format === 'html') {
      console.log(artifactPath);
    }

    return {
      code: fs.existsSync(artifactPath) ? 0 : 1,
      payload: {
        format,
        artifactPath,
        artifactRelativePath: settings.diagram.primaryArtifact,
        settings
      }
    };
  }

  const [settingsAction, ...rest] = argv;
  if (!settingsAction || !['get', 'set', 'reset'].includes(settingsAction)) {
    throw new Error('Usage: gg harness settings <get|set|reset> [--key <dot.path> --value <value>]');
  }

  if (settingsAction === 'get') {
    const settings = readHarnessSettings(projectRoot);
    if (!jsonMode) {
      console.log(JSON.stringify(settings, null, 2));
    }
    return {
      code: 0,
      payload: {
        settings,
        path: harnessSettingsPath(projectRoot)
      }
    };
  }

  if (settingsAction === 'reset') {
    const settings = resetHarnessSettings(projectRoot);
    if (!jsonMode) {
      console.log(`Reset harness settings: ${harnessSettingsPath(projectRoot)}`);
    }
    return {
      code: 0,
      payload: {
        settings,
        path: harnessSettingsPath(projectRoot)
      }
    };
  }

  const { flags } = parseArgs(rest);
  const key = flagString(flags, 'key');
  const rawValue = flagString(flags, 'value');
  if (!key || rawValue === undefined) {
    throw new Error('Usage: gg harness settings set --key <dot.path> --value <value>');
  }

  const next = readHarnessSettings(projectRoot);
  setByDotPath(next as unknown as Record<string, unknown>, key, parseScalarFlagValue(rawValue));
  const settings = writeHarnessSettings(projectRoot, next);
  if (!jsonMode) {
    console.log(`Updated harness settings: ${key}`);
  }
  return {
    code: 0,
    payload: {
      settings,
      path: harnessSettingsPath(projectRoot)
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

function ensureFileCopied(source: string, destination: string): void {
  if (fs.existsSync(destination)) {
    return;
  }

  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

function ensurePortableDocs(projectRoot: string, targetRoot: string): void {
  for (const relativePath of PORTABLE_DOC_FILES) {
    ensureFileCopied(path.join(projectRoot, relativePath), path.join(targetRoot, relativePath));
  }

  fs.mkdirSync(path.join(targetRoot, 'docs', 'decisions'), { recursive: true });
  fs.mkdirSync(path.join(targetRoot, 'docs', 'governance', 'feedback-loop-proposals'), { recursive: true });
}

function ensurePortableAgentAssets(projectRoot: string, targetRoot: string, mode: 'symlink' | 'copy'): void {
  fs.mkdirSync(path.join(targetRoot, '.agent'), { recursive: true });

  for (const relativePath of PORTABLE_AGENT_PATHS) {
    ensureSymlinkOrCopy(path.join(projectRoot, relativePath), path.join(targetRoot, relativePath), mode);
  }

  fs.mkdirSync(path.join(targetRoot, '.agent', 'control-plane', 'server'), { recursive: true });
  fs.mkdirSync(path.join(targetRoot, '.agent', 'control-plane', 'runs'), { recursive: true });
  fs.mkdirSync(path.join(targetRoot, '.agent', 'control-plane', 'worktrees'), { recursive: true });
  fs.mkdirSync(path.join(targetRoot, '.agent', 'control-plane', 'executions'), { recursive: true });
  fs.mkdirSync(path.join(targetRoot, '.agent', 'runs'), { recursive: true });

  const runPlaceholder = path.join(targetRoot, '.agent', 'runs', '.gitkeep');
  if (!fs.existsSync(runPlaceholder)) {
    fs.writeFileSync(runPlaceholder, '', 'utf8');
  }
}

function mergePortablePackageScripts(targetPackagePath: string): void {
  const existing = readJsonFile<Record<string, unknown>>(targetPackagePath) || {};
  const next = {
    ...existing,
    scripts: {
      ...(typeof existing.scripts === 'object' && existing.scripts !== null ? (existing.scripts as Record<string, string>) : {}),
      ...PORTABLE_REQUIRED_PACKAGE_SCRIPTS
    }
  };

  writeJson(targetPackagePath, next);
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

function validatePromptMirrors(targetRoot: string): { ok: boolean; detail: string } {
  const claude = path.join(targetRoot, 'CLAUDE.md');
  const agents = path.join(targetRoot, 'AGENTS.md');
  const gemini = path.join(targetRoot, 'GEMINI.md');
  if (![claude, agents, gemini].every((file) => fs.existsSync(file))) {
    return { ok: false, detail: 'Missing one or more prompt mirror files' };
  }

  const base = fs.readFileSync(claude, 'utf8');
  const mirrorsAligned =
    base === fs.readFileSync(agents, 'utf8') &&
    base === fs.readFileSync(gemini, 'utf8');

  return {
    ok: mirrorsAligned,
    detail: mirrorsAligned ? 'CLAUDE.md, AGENTS.md, and GEMINI.md are aligned' : 'Prompt mirror drift detected'
  };
}

function validatePortableMcpConfig(targetRoot: string): { ok: boolean; detail: string } {
  const mcpPath = path.join(targetRoot, '.mcp.json');
  if (!fs.existsSync(mcpPath)) {
    return { ok: false, detail: 'Missing .mcp.json' };
  }

  const config = readJsonFile<{
    mcpServers?: {
      ['gg-skills']?: { args?: string[]; env?: Record<string, string> };
    };
  }>(mcpPath);

  const server = config?.mcpServers?.['gg-skills'];
  if (!server) {
    return { ok: false, detail: 'Missing gg-skills server entry in .mcp.json' };
  }

  const expectedArgs = path.join(targetRoot, 'mcp-servers', 'gg-skills', 'dist', 'index.js');
  const expectedSkillsDir = path.join(targetRoot, '.agent', 'skills');
  const expectedWorkflowsDir = path.join(targetRoot, '.agent', 'workflows');
  const argsOk = Array.isArray(server.args) && server.args.includes(expectedArgs);
  const skillsOk = server.env?.SKILLS_DIR === expectedSkillsDir;
  const workflowsOk = server.env?.WORKFLOWS_DIR === expectedWorkflowsDir;
  const buildOk = fs.existsSync(expectedArgs);

  return {
    ok: Boolean(argsOk && skillsOk && workflowsOk && buildOk),
    detail: argsOk && skillsOk && workflowsOk && buildOk
      ? '.mcp.json points gg-skills at the target repo'
      : 'gg-skills MCP config does not point at target repo paths or gg-skills is not built'
  };
}

function validatePortablePackageScripts(targetRoot: string): { ok: boolean; detail: string } {
  const pkg = readJsonFile<{ scripts?: Record<string, string> }>(path.join(targetRoot, 'package.json'));
  const missing = Object.keys(PORTABLE_REQUIRED_PACKAGE_SCRIPTS).filter(
    (name) => pkg?.scripts?.[name] !== PORTABLE_REQUIRED_PACKAGE_SCRIPTS[name]
  );

  return {
    ok: missing.length === 0,
    detail: missing.length === 0
      ? 'Target package.json exposes harness verification scripts'
      : `Target package.json is missing harness scripts: ${missing.join(', ')}`
  };
}

function validatePortableHarnessSettings(targetRoot: string): { ok: boolean; detail: string } {
  const settings = readHarnessSettings(targetRoot);
  const filePath = harnessSettingsPath(targetRoot);
  return {
    ok: fs.existsSync(filePath) && settings.execution.loopBudget > 0,
    detail: fs.existsSync(filePath)
      ? `Harness settings are present at ${filePath}`
      : `Harness settings are missing at ${filePath}`
  };
}

function validatePortableDiagramArtifact(targetRoot: string): { ok: boolean; detail: string } {
  const settings = readHarnessSettings(targetRoot);
  const artifactPath = resolveHarnessDiagramPath(targetRoot, settings);
  return {
    ok: fs.existsSync(artifactPath),
    detail: fs.existsSync(artifactPath)
      ? `Dynamic harness diagram is present at ${artifactPath}`
      : `Dynamic harness diagram is missing at ${artifactPath}`
  };
}

function executeJsonNodeScript(
  targetRoot: string,
  scriptPath: string,
  args: string[]
): { code: number; stdout: string; stderr: string; parsed: unknown | null } {
  const result = executeCommand('node', [scriptPath, ...args], targetRoot, true);
  let parsed: unknown | null = null;
  try {
    parsed = result.stdout.trim() ? JSON.parse(result.stdout) : null;
  } catch {
    parsed = null;
  }
  return { ...result, parsed };
}

function runCliLike(projectRoot: string, targetRoot: string, args: string[]): CommandResult {
  const result = executeCommand(
    'node',
    [path.join(projectRoot, 'packages', 'gg-cli', 'dist', 'index.js'), '--json', '--project-root', targetRoot, ...args],
    projectRoot,
    true
  );

  let payload: unknown = null;
  try {
    payload = result.stdout.trim() ? JSON.parse(result.stdout) : null;
  } catch {
    payload = null;
  }

  return {
    code: result.code,
    payload
  };
}

function commandPortableVerify(
  projectRoot: string,
  targetRoot: string,
  runtimeMode: 'structure' | 'smoke',
  jsonMode: boolean
): CommandResult {
  const checks: Array<{ name: string; status: 'pass' | 'fail' | 'warn'; detail: string }> = [];
  const codexActivationCommand = `node ${path.join(projectRoot, 'packages', 'gg-cli', 'dist', 'index.js')} --project-root ${targetRoot} runtime activate ${targetRoot} --runtime codex`;

  const promptCheck = validatePromptMirrors(targetRoot);
  checks.push({ name: 'prompt_mirror', status: promptCheck.ok ? 'pass' : 'fail', detail: promptCheck.detail });

  const mcpCheck = validatePortableMcpConfig(targetRoot);
  checks.push({ name: 'mcp_config', status: mcpCheck.ok ? 'pass' : 'fail', detail: mcpCheck.detail });

  const packageScriptCheck = validatePortablePackageScripts(targetRoot);
  checks.push({
    name: 'package_scripts',
    status: packageScriptCheck.ok ? 'pass' : 'fail',
    detail: packageScriptCheck.detail
  });

  const harnessSettingsCheck = validatePortableHarnessSettings(targetRoot);
  checks.push({
    name: 'harness_settings',
    status: harnessSettingsCheck.ok ? 'pass' : 'fail',
    detail: harnessSettingsCheck.detail
  });

  const harnessDiagramCheck = validatePortableDiagramArtifact(targetRoot);
  checks.push({
    name: 'harness_diagram',
    status: harnessDiagramCheck.ok ? 'pass' : 'fail',
    detail: harnessDiagramCheck.detail
  });

  const doctor = commandDoctor(targetRoot, true);
  checks.push({
    name: 'doctor',
    status: doctor.code === 0 ? 'pass' : 'fail',
    detail: doctor.code === 0 ? 'gg doctor passed' : 'gg doctor failed'
  });

  const projectContext = executeCommand('node', [path.join(targetRoot, 'scripts', 'generate-project-context.mjs'), '--check'], targetRoot, true);
  checks.push({
    name: 'project_context',
    status: projectContext.code === 0 ? 'pass' : 'fail',
    detail: (projectContext.stdout || projectContext.stderr || '').trim() || 'project context check completed'
  });

  const audit = executeCommand('node', [path.join(targetRoot, 'scripts', 'persona-registry-audit.mjs')], targetRoot, true);
  checks.push({
    name: 'persona_audit',
    status: audit.code === 0 ? 'pass' : 'fail',
    detail: (audit.stdout || audit.stderr || '').trim() || 'persona audit completed'
  });

  const benchmark = executeJsonNodeScript(
    targetRoot,
    path.join(targetRoot, 'scripts', 'persona-registry-benchmark.mjs'),
    ['--json']
  );
  const benchmarkPayload = benchmark.parsed as { failed?: number; passed?: number } | null;
  const benchmarkOk = benchmark.code === 0 && (benchmarkPayload?.failed ?? 0) === 0;
  checks.push({
    name: 'persona_benchmark',
    status: benchmarkOk ? 'pass' : 'fail',
    detail: benchmarkOk
      ? `Persona routing benchmark passed (${benchmarkPayload?.passed ?? 0} cases)`
      : 'Persona routing benchmark failed'
  });

  const resolver = executeJsonNodeScript(
    targetRoot,
    path.join(targetRoot, 'scripts', 'persona-registry-resolve.mjs'),
    ['--prompt', 'ship auth hardening with oauth login, passkeys, and regression tests', '--classification', 'TASK', '--json']
  );

  const resolverOk =
    resolver.code === 0 &&
    typeof resolver.parsed === 'object' &&
    resolver.parsed !== null &&
    (resolver.parsed as { compoundPersona?: { id?: string } }).compoundPersona?.id === 'compound:auth-hardening:v1';
  checks.push({
    name: 'persona_resolve_smoke',
    status: resolverOk ? 'pass' : 'fail',
    detail: resolverOk
      ? 'Resolver selected auth-hardening compound as expected'
      : 'Resolver smoke prompt did not return the expected auth-hardening compound'
  });

  const codexStatus = executeJsonNodeScript(
    targetRoot,
    path.join(targetRoot, 'scripts', 'runtime-project-sync.mjs'),
    ['status', targetRoot, '--runtime', 'codex', '--json']
  );
  const codexActivation = codexStatus.parsed as { active?: boolean } | null;
  checks.push({
    name: 'runtime_activation_codex',
    status: codexActivation?.active ? 'pass' : 'warn',
    detail: codexActivation?.active
      ? 'Codex project-scoped MCPs are active for this target repo'
      : `Codex project-scoped MCPs are not active for this target repo. Run ${codexActivationCommand}`
  });

  const runtimeRegistryPath = path.join(targetRoot, '.agent', 'registry', 'mcp-runtime.json');
  const runtimeRegistry = readJsonFile<{
    profiles?: Record<string, { optional?: string[]; execution?: { adapterMode?: string; defaultLaunchTransport?: string } }>;
  }>(runtimeRegistryPath);
  const profiles = ['codex', 'claude', 'kimi'];
  const parityMissing = profiles.filter(
    (profile) => !runtimeRegistry?.profiles?.[profile]?.optional?.includes('claude-mem')
  );
  const kimiExecution = runtimeRegistry?.profiles?.kimi?.execution;
  const kimiExecutionOk =
    kimiExecution?.adapterMode === 'provider-api' &&
    kimiExecution?.defaultLaunchTransport === 'api-session';
  checks.push({
    name: 'runtime_registry',
    status: parityMissing.length === 0 && kimiExecutionOk ? 'pass' : 'fail',
    detail:
      parityMissing.length === 0 && kimiExecutionOk
        ? 'Runtime registry exposes claude-mem parity and the Kimi provider-api contract'
        : parityMissing.length > 0
          ? `Runtime registry missing claude-mem parity on: ${parityMissing.join(', ')}`
          : 'Runtime registry is missing the Kimi provider-api execution contract'
  });

  const harnessCliGet = runCliLike(projectRoot, targetRoot, ['harness', 'settings', 'get']);
  checks.push({
    name: 'harness_cli_settings_get',
    status: harnessCliGet.code === 0 ? 'pass' : 'fail',
    detail: harnessCliGet.code === 0 ? 'gg harness settings get passed' : 'gg harness settings get failed'
  });

  const harnessCliDiagram = runCliLike(projectRoot, targetRoot, ['harness', 'diagram', '--format', 'json']);
  checks.push({
    name: 'harness_cli_diagram',
    status: harnessCliDiagram.code === 0 ? 'pass' : 'fail',
    detail: harnessCliDiagram.code === 0 ? 'gg harness diagram --format json passed' : 'gg harness diagram --format json failed'
  });

  if (runtimeMode === 'smoke') {
    const smoke = executeJsonNodeScript(
      targetRoot,
      path.join(targetRoot, 'scripts', 'runtime-parity-smoke.mjs'),
      ['--allow-warn', '--json']
    );
    const smokePayload = smoke.parsed as { results?: Array<{ id?: string; status?: string }> } | null;
    const structuralFailures = (smokePayload?.results || []).filter(
      (entry) => entry.status === 'fail' && entry.id !== 'runtime_activation_codex_gg_skills'
    );
    checks.push({
      name: 'runtime_parity_smoke',
      status: smoke.code === 0 || structuralFailures.length === 0 ? 'pass' : 'warn',
      detail:
        smoke.code === 0 || structuralFailures.length === 0
          ? 'Runtime parity smoke passed or only host-specific gg-skills drift remains'
          : 'Runtime parity smoke found structural failures'
    });
  }

  const failures = checks.filter((check) => check.status === 'fail');
  const warnings = checks.filter((check) => check.status === 'warn');

  if (!jsonMode) {
    console.log(`Portable verify: ${targetRoot}`);
    for (const check of checks) {
      console.log(`[${check.status}] ${check.name}: ${check.detail}`);
    }
  }

  return {
    code: failures.length > 0 ? 1 : 0,
    payload: {
      targetRoot,
      runtimeMode,
      status: failures.length > 0 ? 'failed' : warnings.length > 0 ? 'passed_with_warnings' : 'passed',
      checks
    }
  };
}

function commandPortable(projectRoot: string, action: string | undefined, argv: string[], jsonMode: boolean): CommandResult {
  const { flags, positionals } = parseArgs(argv);
  const targetDir = positionals[0];
  if (!targetDir) {
    throw new Error('Usage: gg portable <init|verify> <targetDir> [--mode symlink|copy] [--runtime structure|smoke]');
  }

  if (action === 'verify') {
    const runtimeMode = (flagString(flags, 'runtime') === 'smoke' ? 'smoke' : 'structure') as 'structure' | 'smoke';
    return commandPortableVerify(projectRoot, path.resolve(targetDir), runtimeMode, jsonMode);
  }

  if (action !== 'init') {
    throw new Error('Usage: gg portable <init|verify> <targetDir> [--mode symlink|copy] [--runtime structure|smoke]');
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

  ensurePortableAgentAssets(projectRoot, targetRoot, mode);
  ensureSymlinkOrCopy(path.join(projectRoot, 'scripts'), path.join(targetRoot, 'scripts'), mode);
  ensureSymlinkOrCopy(path.join(projectRoot, 'evals'), path.join(targetRoot, 'evals'), mode);
  ensureSymlinkOrCopy(
    path.join(projectRoot, 'mcp-servers', 'gg-skills'),
    path.join(targetRoot, 'mcp-servers', 'gg-skills'),
    mode
  );
  ensurePortableDocs(projectRoot, targetRoot);
  readHarnessSettings(targetRoot);
  mergePortablePackageScripts(targetPackagePath);

  const sourcePrompt = path.join(projectRoot, 'CLAUDE.md');
  const targetPrompt = path.join(targetRoot, 'CLAUDE.md');
  if (!fs.existsSync(targetPrompt)) {
    fs.copyFileSync(sourcePrompt, targetPrompt);
  }

  const agentsAlias = path.join(targetRoot, 'AGENTS.md');
  if (!fs.existsSync(agentsAlias)) {
    fs.symlinkSync('CLAUDE.md', agentsAlias);
  }

  const geminiAlias = path.join(targetRoot, 'GEMINI.md');
  if (!fs.existsSync(geminiAlias)) {
    fs.symlinkSync('CLAUDE.md', geminiAlias);
  }

  const mcpPath = path.join(targetRoot, '.mcp.json');
  if (!fs.existsSync(mcpPath)) {
    fs.writeFileSync(mcpPath, `${renderMcpConfig(targetRoot)}\n`, 'utf8');
  }

  const contextRefresh = executeCommand(
    'node',
    [path.join(targetRoot, 'scripts', 'generate-project-context.mjs')],
    targetRoot,
    true
  );
  if (contextRefresh.code !== 0) {
    throw new Error(`Failed to generate project context for target: ${(contextRefresh.stderr || contextRefresh.stdout).trim()}`);
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
      `3. Run \`node ${path.join(projectRoot, 'packages', 'gg-cli', 'dist', 'index.js')} --project-root ${targetRoot} doctor\`.`,
      '4. Activate Codex project-scoped MCPs:',
      '```bash',
      `node ${path.join(projectRoot, 'packages', 'gg-cli', 'dist', 'index.js')} --project-root ${targetRoot} runtime activate ${targetRoot} --runtime codex`,
      '```',
      `5. Run \`node ${path.join(projectRoot, 'packages', 'gg-cli', 'dist', 'index.js')} --project-root ${projectRoot} portable verify ${targetRoot} --runtime structure\`.`,
      '6. Run `npm run harness:runtime-parity` to confirm Codex/Claude/Kimi parity wiring.',
      '7. Run `npm run harness:persona:audit` and `npm run harness:persona:benchmark` to confirm persona routing is intact.',
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

async function main(): Promise<void> {
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
      case 'worker':
        result = await commandWorker(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'bus':
        result = commandBus(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'runtime':
        result = commandRuntime(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'codex':
        result = commandCodex(projectRoot, maybeAction, rest, jsonMode);
        break;
      case 'context':
        result = commandContext(projectRoot, maybeAction, jsonMode);
        break;
      case 'validate':
        result = commandValidate(projectRoot, maybeAction, jsonMode);
        break;
      case 'harness':
        result = await commandHarness(projectRoot, maybeAction, rest, jsonMode);
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

void main();
