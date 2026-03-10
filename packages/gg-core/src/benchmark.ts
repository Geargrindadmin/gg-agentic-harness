import fs from 'node:fs';
import path from 'node:path';

export type BenchmarkSourceType = 'prompt' | 'prd' | 'normalized';
export type BenchmarkWorkflow = 'create' | 'go' | 'minion';
export type BenchmarkCaseStatus = 'pass' | 'fail' | 'skipped';
export type BenchmarkOutcome = 'HANDOFF_READY' | 'BLOCKED' | 'FAILED' | 'SKIPPED';

export interface HeadlessProductBenchmarkPolicy {
  fixtureFirst: boolean;
  downstreamProofAfterFixturePass: boolean;
  firstDownstreamTarget: string;
}

export interface HeadlessProductBenchmarkCase {
  id: string;
  workflow: BenchmarkWorkflow;
  sourceType: BenchmarkSourceType;
  request?: string;
  sourcePath?: string;
  lane: string;
  expectedPacks: string[];
  deliveryTarget: string;
  downstreamTarget?: string;
  expectedOutcome: Exclude<BenchmarkOutcome, 'SKIPPED'>;
}

export interface HeadlessProductBenchmarkCorpus {
  version: number;
  policy: HeadlessProductBenchmarkPolicy;
  mandatoryLanes: string[];
  unattendedV1Packs: string[];
  cases: HeadlessProductBenchmarkCase[];
}

export interface HeadlessProductBenchmarkChecks {
  laneMatch: boolean;
  packMatch: boolean;
  bundleCreated: boolean;
  buildVerified: boolean;
  configStable: boolean;
}

export interface HeadlessProductBenchmarkResult {
  caseId: string;
  lane: string;
  workflow: BenchmarkWorkflow;
  status: BenchmarkCaseStatus;
  outcome: BenchmarkOutcome;
  expectedOutcome: Exclude<BenchmarkOutcome, 'SKIPPED'>;
  checks: HeadlessProductBenchmarkChecks;
  notes: string[];
}

export interface HeadlessProductBenchmarkLaneSummary {
  total: number;
  passed: number;
  failed: number;
  skipped: number;
}

export interface HeadlessProductBenchmarkSummary {
  overallStatus: 'pass' | 'fail';
  totals: {
    totalCases: number;
    passed: number;
    failed: number;
    skipped: number;
  };
  lanes: Record<string, HeadlessProductBenchmarkLaneSummary>;
}

interface RawBenchmarkCorpus {
  version?: unknown;
  policy?: Partial<HeadlessProductBenchmarkPolicy>;
  mandatoryLanes?: unknown;
  unattendedV1Packs?: unknown;
  cases?: unknown;
}

interface RawBenchmarkCase {
  id?: unknown;
  workflow?: unknown;
  sourceType?: unknown;
  request?: unknown;
  summary?: unknown;
  sourcePath?: unknown;
  lane?: unknown;
  expectedPacks?: unknown;
  deliveryTarget?: unknown;
  downstreamTarget?: unknown;
  expectedOutcome?: unknown;
}

function normalizeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((entry): entry is string => typeof entry === 'string')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function normalizeWorkflow(value: unknown): BenchmarkWorkflow {
  if (value === 'create' || value === 'go' || value === 'minion') {
    return value;
  }
  return 'go';
}

function normalizeSourceType(value: unknown): BenchmarkSourceType {
  if (value === 'prompt' || value === 'prd' || value === 'normalized') {
    return value;
  }
  return 'prompt';
}

function normalizeExpectedOutcome(value: unknown): Exclude<BenchmarkOutcome, 'SKIPPED'> {
  if (value === 'HANDOFF_READY' || value === 'BLOCKED' || value === 'FAILED') {
    return value;
  }
  return 'HANDOFF_READY';
}

function normalizeBenchmarkCase(raw: RawBenchmarkCase): HeadlessProductBenchmarkCase {
  const sourceType = normalizeSourceType(raw.sourceType);
  const request = typeof raw.request === 'string'
    ? raw.request.trim()
    : typeof raw.summary === 'string'
      ? raw.summary.trim()
      : '';
  const sourcePath = typeof raw.sourcePath === 'string' ? raw.sourcePath.trim() : undefined;

  return {
    id: typeof raw.id === 'string' ? raw.id.trim() : 'unnamed-case',
    workflow: normalizeWorkflow(raw.workflow),
    sourceType,
    request: request || undefined,
    sourcePath: sourcePath || undefined,
    lane: typeof raw.lane === 'string' ? raw.lane.trim() : 'unknown',
    expectedPacks: normalizeStringArray(raw.expectedPacks),
    deliveryTarget: typeof raw.deliveryTarget === 'string' ? raw.deliveryTarget.trim() : 'local-repo',
    downstreamTarget: typeof raw.downstreamTarget === 'string' ? raw.downstreamTarget.trim() : undefined,
    expectedOutcome: normalizeExpectedOutcome(raw.expectedOutcome)
  };
}

export function loadHeadlessProductBenchmarkCorpus(
  projectRoot: string,
  corpusRelativePath = path.join('evals', 'headless-product-corpus.json')
): HeadlessProductBenchmarkCorpus {
  const corpusPath = path.join(projectRoot, corpusRelativePath);
  if (!fs.existsSync(corpusPath)) {
    throw new Error(`Benchmark corpus not found: ${corpusPath}`);
  }

  const parsed = JSON.parse(fs.readFileSync(corpusPath, 'utf8')) as RawBenchmarkCorpus;
  const rawCases = Array.isArray(parsed.cases) ? parsed.cases as RawBenchmarkCase[] : [];

  return {
    version: typeof parsed.version === 'number' ? parsed.version : 1,
    policy: {
      fixtureFirst: parsed.policy?.fixtureFirst !== false,
      downstreamProofAfterFixturePass: parsed.policy?.downstreamProofAfterFixturePass !== false,
      firstDownstreamTarget: typeof parsed.policy?.firstDownstreamTarget === 'string'
        ? parsed.policy.firstDownstreamTarget
        : 'GGV3'
    },
    mandatoryLanes: normalizeStringArray(parsed.mandatoryLanes),
    unattendedV1Packs: normalizeStringArray(parsed.unattendedV1Packs),
    cases: rawCases.map((entry) => normalizeBenchmarkCase(entry))
  };
}

export function summarizeHeadlessBenchmarkResults(
  corpus: HeadlessProductBenchmarkCorpus,
  results: HeadlessProductBenchmarkResult[]
): HeadlessProductBenchmarkSummary {
  const lanes: Record<string, HeadlessProductBenchmarkLaneSummary> = {};

  for (const lane of corpus.mandatoryLanes) {
    lanes[lane] = { total: 0, passed: 0, failed: 0, skipped: 0 };
  }

  for (const result of results) {
    if (!lanes[result.lane]) {
      lanes[result.lane] = { total: 0, passed: 0, failed: 0, skipped: 0 };
    }

    lanes[result.lane].total += 1;
    if (result.status === 'pass') {
      lanes[result.lane].passed += 1;
    } else if (result.status === 'fail') {
      lanes[result.lane].failed += 1;
    } else {
      lanes[result.lane].skipped += 1;
    }
  }

  const totals = results.reduce(
    (summary, result) => {
      summary.totalCases += 1;
      if (result.status === 'pass') {
        summary.passed += 1;
      } else if (result.status === 'fail') {
        summary.failed += 1;
      } else {
        summary.skipped += 1;
      }
      return summary;
    },
    { totalCases: 0, passed: 0, failed: 0, skipped: 0 }
  );

  return {
    overallStatus: totals.failed > 0 ? 'fail' : 'pass',
    totals,
    lanes
  };
}
