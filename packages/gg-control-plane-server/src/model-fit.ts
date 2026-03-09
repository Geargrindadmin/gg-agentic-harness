import { spawnSync } from 'node:child_process';

export interface ModelFitSystemSnapshot {
  available_ram_gb?: number;
  total_ram_gb?: number;
  cpu_cores?: number;
  cpu_name?: string;
  has_gpu?: boolean;
  gpu_name?: string | null;
  gpu_vram_gb?: number | null;
  backend?: string;
  unified_memory?: boolean;
  gpus?: Array<Record<string, unknown>>;
}

export interface ModelFitRecommendation {
  name: string;
  shortName: string;
  provider: string;
  category: string;
  useCase: string;
  fitLevel: string;
  score: number;
  estimatedTps: number;
  memoryRequiredGb: number;
  memoryAvailableGb: number;
  runtime: string;
  runtimeLabel: string;
  bestQuant: string;
  contextLength: number;
  notes: string[];
  lmStudioQuery: string;
}

export interface ModelFitSnapshot {
  available: boolean;
  binaryPath: string | null;
  system: ModelFitSystemSnapshot | null;
  recommendations: ModelFitRecommendation[];
  error: string | null;
}

export interface LMStudioCandidate {
  name: string;
  shortName: string;
  fitLevel: string;
  score: number;
  runtime: string;
  runtimeLabel: string;
  bestQuant: string;
  lmStudioQuery: string;
  availableForDownload: boolean;
}

function detectBinary(): string | null {
  const which = spawnSync('bash', ['-lc', 'command -v llmfit'], {
    encoding: 'utf8'
  });
  if (which.status !== 0) {
    return null;
  }
  const resolved = which.stdout.trim();
  return resolved || null;
}

function runJson(args: string[]): unknown {
  const result = spawnSync('llmfit', args, {
    encoding: 'utf8',
    timeout: 15_000
  });
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || 'llmfit failed').trim());
  }
  return JSON.parse(result.stdout || '{}');
}

function shortNameFromModel(name: string): string {
  return name.split('/').pop() || name;
}

function lmStudioQueryForModel(name: string): string {
  return shortNameFromModel(name)
    .replace(/-Instruct$/i, '')
    .replace(/-Base$/i, '')
    .replace(/-GGUF$/i, '')
    .replace(/_/g, ' ');
}

function normalizeRecommendation(input: any): ModelFitRecommendation {
  return {
    name: String(input.name || ''),
    shortName: shortNameFromModel(String(input.name || '')),
    provider: String(input.provider || ''),
    category: String(input.category || ''),
    useCase: String(input.use_case || ''),
    fitLevel: String(input.fit_level || ''),
    score: Number(input.score || 0),
    estimatedTps: Number(input.estimated_tps || 0),
    memoryRequiredGb: Number(input.memory_required_gb || 0),
    memoryAvailableGb: Number(input.memory_available_gb || 0),
    runtime: String(input.runtime || ''),
    runtimeLabel: String(input.runtime_label || ''),
    bestQuant: String(input.best_quant || ''),
    contextLength: Number(input.context_length || 0),
    notes: Array.isArray(input.notes) ? input.notes.map((entry: unknown) => String(entry)) : [],
    lmStudioQuery: lmStudioQueryForModel(String(input.name || ''))
  };
}

export function collectModelFitSnapshot(limit = 12): ModelFitSnapshot {
  const binaryPath = detectBinary();
  if (!binaryPath) {
    return {
      available: false,
      binaryPath: null,
      system: null,
      recommendations: [],
      error: 'llmfit is not installed'
    };
  }

  try {
    const systemPayload = runJson(['--json', 'system']) as { system?: ModelFitSystemSnapshot };
    const recommendationsPayload = runJson(['recommend', '--json', '--use-case', 'coding', '--limit', String(limit)]) as { models?: any[]; system?: ModelFitSystemSnapshot };
    return {
      available: true,
      binaryPath,
      system: recommendationsPayload.system || systemPayload.system || null,
      recommendations: Array.isArray(recommendationsPayload.models)
        ? recommendationsPayload.models.map(normalizeRecommendation)
        : [],
      error: null
    };
  } catch (error) {
    return {
      available: true,
      binaryPath,
      system: null,
      recommendations: [],
      error: error instanceof Error ? error.message : String(error)
    };
  }
}

export function collectLMStudioCandidates(limit = 12): LMStudioCandidate[] {
  const snapshot = collectModelFitSnapshot(limit);
  return snapshot.recommendations.map((recommendation) => ({
    name: recommendation.name,
    shortName: recommendation.shortName,
    fitLevel: recommendation.fitLevel,
    score: recommendation.score,
    runtime: recommendation.runtime,
    runtimeLabel: recommendation.runtimeLabel,
    bestQuant: recommendation.bestQuant,
    lmStudioQuery: recommendation.lmStudioQuery,
    availableForDownload: recommendation.runtime.toLowerCase().includes('llama')
      || recommendation.runtime.toLowerCase().includes('mlx')
      || recommendation.runtime.toLowerCase().includes('gguf')
      || recommendation.provider.toLowerCase() !== 'openai'
  }));
}
