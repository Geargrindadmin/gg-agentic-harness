import fs from 'node:fs';
import path from 'node:path';

export type HarnessPromptImproverMode = 'off' | 'auto' | 'force';
export type HarnessContextSource = 'standard' | 'codegraphcontext' | 'hybrid';
export type HarnessHydraMode = 'off' | 'shadow' | 'active';
export type HarnessValidateMode = 'none' | 'tsc' | 'lint' | 'test' | 'all';
export type HarnessDocSyncMode = 'auto' | 'off';
export type HarnessRiskTier = 'low' | 'medium' | 'high';

export interface HarnessDiagramSettings {
  autoRefreshSeconds: number;
  primaryArtifact: string;
}

export interface HarnessExecutionSettings {
  loopBudget: number;
  retryLimit: number;
  retryBackoffSeconds: number[];
  promptImproverMode: HarnessPromptImproverMode;
  contextSource: HarnessContextSource;
  hydraMode: HarnessHydraMode;
  validateMode: HarnessValidateMode;
  docSyncMode: HarnessDocSyncMode;
}

export interface HarnessGovernorSettings {
  cpuHighPct: number | null;
  cpuLowPct: number | null;
  modelVramGb: number | null;
  perAgentOverheadGb: number | null;
  reservedRamGb: number | null;
}

export interface HarnessArtifactSettings {
  promptVersion: string | null;
  workflowVersion: string | null;
  blueprintVersion: string | null;
  toolBundle: string | null;
  riskTier: HarnessRiskTier | null;
}

export interface HarnessSettings {
  diagram: HarnessDiagramSettings;
  execution: HarnessExecutionSettings;
  governor: HarnessGovernorSettings;
  artifacts: HarnessArtifactSettings;
}

const PROMPT_IMPROVER_MODES: readonly HarnessPromptImproverMode[] = ['off', 'auto', 'force'] as const;
const CONTEXT_SOURCES: readonly HarnessContextSource[] = ['standard', 'codegraphcontext', 'hybrid'] as const;
const HYDRA_MODES: readonly HarnessHydraMode[] = ['off', 'shadow', 'active'] as const;
const VALIDATE_MODES: readonly HarnessValidateMode[] = ['none', 'tsc', 'lint', 'test', 'all'] as const;
const DOC_SYNC_MODES: readonly HarnessDocSyncMode[] = ['auto', 'off'] as const;
const RISK_TIERS: readonly HarnessRiskTier[] = ['low', 'medium', 'high'] as const;

function ensureDir(dirPath: string): void {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeJson(filePath: string, value: unknown): void {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function readJson<T>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
  } catch {
    return null;
  }
}

function clampNumber(value: unknown, fallback: number, minimum: number, maximum: number): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(minimum, Math.min(maximum, parsed));
}

function nullableNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') {
    return null;
  }
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function enumValue<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return typeof value === 'string' && allowed.includes(value as T) ? (value as T) : fallback;
}

function nullableString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function nullableRiskTier(value: unknown): HarnessRiskTier | null {
  if (typeof value !== 'string') {
    return null;
  }
  return RISK_TIERS.includes(value as HarnessRiskTier) ? (value as HarnessRiskTier) : null;
}

export function harnessSettingsPath(projectRoot: string): string {
  return path.join(projectRoot, '.agent', 'control-plane', 'server', 'harness-settings.json');
}

export function defaultHarnessSettings(): HarnessSettings {
  return {
    diagram: {
      autoRefreshSeconds: 15,
      primaryArtifact: 'docs/architecture/agentic-harness-dynamic-user-diagram.html'
    },
    execution: {
      loopBudget: 50,
      retryLimit: 3,
      retryBackoffSeconds: [1, 2, 4],
      promptImproverMode: 'auto',
      contextSource: 'standard',
      hydraMode: 'off',
      validateMode: 'none',
      docSyncMode: 'auto'
    },
    governor: {
      cpuHighPct: null,
      cpuLowPct: null,
      modelVramGb: null,
      perAgentOverheadGb: null,
      reservedRamGb: null
    },
    artifacts: {
      promptVersion: null,
      workflowVersion: null,
      blueprintVersion: null,
      toolBundle: null,
      riskTier: null
    }
  };
}

export function normalizeHarnessSettings(input: Partial<HarnessSettings> | null | undefined): HarnessSettings {
  const defaults = defaultHarnessSettings();
  const execution: Partial<HarnessExecutionSettings> = input?.execution || {};
  const governor: Partial<HarnessGovernorSettings> = input?.governor || {};
  const artifacts: Partial<HarnessArtifactSettings> = input?.artifacts || {};

  const retryBackoffSeconds = Array.isArray(execution.retryBackoffSeconds)
    ? execution.retryBackoffSeconds
        .map((entry: number) => clampNumber(entry, 0, 0, 600))
        .filter((entry: number) => entry > 0)
        .slice(0, 8)
    : defaults.execution.retryBackoffSeconds;

  return {
    diagram: {
      autoRefreshSeconds: clampNumber(input?.diagram?.autoRefreshSeconds, defaults.diagram.autoRefreshSeconds, 5, 300),
      primaryArtifact: nullableString(input?.diagram?.primaryArtifact) || defaults.diagram.primaryArtifact
    },
    execution: {
      loopBudget: clampNumber(execution.loopBudget, defaults.execution.loopBudget, 1, 500),
      retryLimit: clampNumber(execution.retryLimit, defaults.execution.retryLimit, 0, 10),
      retryBackoffSeconds: retryBackoffSeconds.length ? retryBackoffSeconds : defaults.execution.retryBackoffSeconds,
      promptImproverMode: enumValue(execution.promptImproverMode, PROMPT_IMPROVER_MODES, defaults.execution.promptImproverMode),
      contextSource: enumValue(execution.contextSource, CONTEXT_SOURCES, defaults.execution.contextSource),
      hydraMode: enumValue(execution.hydraMode, HYDRA_MODES, defaults.execution.hydraMode),
      validateMode: enumValue(execution.validateMode, VALIDATE_MODES, defaults.execution.validateMode),
      docSyncMode: enumValue(execution.docSyncMode, DOC_SYNC_MODES, defaults.execution.docSyncMode)
    },
    governor: {
      cpuHighPct: nullableNumber(governor.cpuHighPct),
      cpuLowPct: nullableNumber(governor.cpuLowPct),
      modelVramGb: nullableNumber(governor.modelVramGb),
      perAgentOverheadGb: nullableNumber(governor.perAgentOverheadGb),
      reservedRamGb: nullableNumber(governor.reservedRamGb)
    },
    artifacts: {
      promptVersion: nullableString(artifacts.promptVersion),
      workflowVersion: nullableString(artifacts.workflowVersion),
      blueprintVersion: nullableString(artifacts.blueprintVersion),
      toolBundle: nullableString(artifacts.toolBundle),
      riskTier: nullableRiskTier(artifacts.riskTier)
    }
  };
}

export function readHarnessSettings(projectRoot: string): HarnessSettings {
  const filePath = harnessSettingsPath(projectRoot);
  const existing = readJson<Partial<HarnessSettings>>(filePath);
  const normalized = normalizeHarnessSettings(existing);
  writeJson(filePath, normalized);
  return normalized;
}

export function writeHarnessSettings(projectRoot: string, settings: Partial<HarnessSettings>): HarnessSettings {
  const normalized = normalizeHarnessSettings(settings);
  writeJson(harnessSettingsPath(projectRoot), normalized);
  return normalized;
}

export function resetHarnessSettings(projectRoot: string): HarnessSettings {
  const defaults = defaultHarnessSettings();
  writeJson(harnessSettingsPath(projectRoot), defaults);
  return defaults;
}

export function resolveHarnessDiagramPath(projectRoot: string, settings?: HarnessSettings): string {
  const relativePath = settings?.diagram.primaryArtifact || defaultHarnessSettings().diagram.primaryArtifact;
  return path.resolve(projectRoot, relativePath);
}
