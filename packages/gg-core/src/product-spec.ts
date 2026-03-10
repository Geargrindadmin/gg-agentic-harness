import fs from 'node:fs';
import path from 'node:path';

export interface ProductLaneDefinition {
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

export interface ProductPackDefinition {
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

export type CanonicalProductSourceType = 'prompt' | 'prd' | 'prompt+constraints' | 'normalized';
export type DeliveryTarget = 'local-repo' | 'portable-target' | 'downstream-install';
export type ProductSpecFlagValue = string | boolean | string[];

export interface CanonicalProductSpec {
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

export interface GoSourceInput {
  sourceType: CanonicalProductSourceType;
  rawInput: string;
  sourceText: string;
  sourcePath?: string;
  normalizedSpec?: Partial<CanonicalProductSpec>;
}

export interface GoProductResolution {
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

export interface CanonicalSpecPromptContext {
  normalizedObjective: string;
  constraints: string[];
  acceptanceCriteria: string[];
}

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

const GO_LANE_HINTS: Record<string, string[]> = {
  'marketing-site': ['marketing', 'website', 'site', 'landing', 'pricing', 'case studies', 'contact', 'homepage', 'brand'],
  'saas-dashboard': ['dashboard', 'analytics', 'saas', 'workspace', 'tenant', 'settings', 'alerting', 'authenticated', 'application'],
  'admin-panel': ['admin', 'internal', 'operations', 'operator', 'moderation', 'audit', 'incident', 'status', 'control panel'],
  'crud-shell': ['crud', 'resource', 'records', 'table', 'forms', 'list detail', 'api backed', 'management'],
  'content-portal': ['content', 'documentation', 'docs', 'knowledge base', 'portal', 'publishing', 'mdx', 'articles']
};

const GO_PACK_HINTS: Record<string, string[]> = {
  'auth-rbac': ['auth', 'authentication', 'rbac', 'role based', 'roles', 'permissions', 'login', 'session'],
  'billing-stripe': ['stripe', 'subscription', 'checkout', 'payments'],
  'compliance-baseline': ['compliance', 'privacy', 'soc2', 'hipaa', 'audit policy', 'retention'],
  'notifications': ['notification', 'notifications', 'email', 'sms', 'slack', 'webhook'],
  'cms-content': ['cms', 'content', 'publishing', 'editorial', 'articles', 'docs'],
  'admin-ops': ['admin ops', 'operator', 'moderation', 'incident', 'audit views', 'operational controls']
};

const GO_PACK_INTEGRATIONS: Record<string, string[]> = {
  'auth-rbac': ['auth-provider'],
  'billing-stripe': ['stripe'],
  'compliance-baseline': ['audit-log-policy'],
  'notifications': ['notification-channels'],
  'cms-content': ['content-source'],
  'admin-ops': ['operator-roles'],
  'observability': ['telemetry-provider']
};

function uniqueStrings(items: string[]): string[] {
  return Array.from(new Set(items.filter(Boolean)));
}

function readJsonFileSafe<T = unknown>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
  } catch {
    return null;
  }
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

function extractObjectiveKeywords(text: string): string[] {
  return uniqueStrings(
    normalizeObjectiveText(text)
      .toLowerCase()
      .split(/[^a-z0-9._/-]+/u)
      .map((token) => token.trim())
      .filter((token) => token.length > 2 && !STOP_WORDS.has(token))
  ).slice(0, 5);
}

function flagString(flags: Record<string, ProductSpecFlagValue>, name: string): string | undefined {
  const value = flags[name];
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.length > 0 ? value[value.length - 1] : undefined;
  }

  return undefined;
}

function flagStringArray(flags: Record<string, ProductSpecFlagValue>, name: string): string[] {
  const value = flags[name];
  if (Array.isArray(value)) {
    return value.flatMap((item) => item.split(',')).map((item) => item.trim()).filter(Boolean);
  }
  if (typeof value === 'string') {
    return value.split(',').map((item) => item.trim()).filter(Boolean);
  }
  return [];
}

function loadJsonDefinitions<T>(dirPath: string): T[] {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  return fs.readdirSync(dirPath)
    .filter((item) => item.endsWith('.json'))
    .map((item) => readJsonFileSafe<T>(path.join(dirPath, item)))
    .filter((item): item is T => Boolean(item));
}

function looksLikeCanonicalProductSpec(value: unknown): value is Partial<CanonicalProductSpec> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }

  const candidate = value as Record<string, unknown>;
  return typeof candidate.summary === 'string'
    && typeof candidate.lane === 'string'
    && typeof candidate.targetStack === 'string';
}

function summarizeStructuredSourceText(raw: string): string {
  const lines = raw
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !line.startsWith('```'))
    .map((line) => line.replace(/^#+\s*/u, '').replace(/^[-*+]\s*/u, ''));

  return normalizeObjectiveText(lines.slice(0, 12).join(' ')).slice(0, 1600);
}

function scoreKeywordMatches(text: string, keywords: string[]): { score: number; matches: string[] } {
  let score = 0;
  const matches: string[] = [];

  for (const keyword of uniqueStrings(keywords.map((item) => normalizeSearchText(item)).filter(Boolean))) {
    if (!text.includes(keyword)) {
      continue;
    }
    matches.push(keyword);
    score += keyword.includes(' ') ? 3 : 2;
  }

  return { score, matches };
}

export function normalizeSearchText(input: string): string {
  return input.toLowerCase().replace(/[_-]+/gu, ' ');
}

export function resolveGoSourceInput(
  projectRoot: string,
  rawGoal: string,
  flags: Record<string, ProductSpecFlagValue>
): GoSourceInput {
  const trimmed = rawGoal.trim();
  const hasConstraintFlags = ['lane', 'pack', 'target-stack', 'delivery-target', 'downstream-target'].some((key) => flags[key] !== undefined);
  const candidatePath = path.isAbsolute(trimmed) ? trimmed : path.resolve(projectRoot, trimmed);

  if (trimmed && fs.existsSync(candidatePath) && fs.statSync(candidatePath).isFile()) {
    const sourcePath = path.relative(projectRoot, candidatePath);
    const raw = fs.readFileSync(candidatePath, 'utf8');
    if (candidatePath.endsWith('.json')) {
      const parsed = readJsonFileSafe<Record<string, unknown>>(candidatePath);
      if (looksLikeCanonicalProductSpec(parsed)) {
        return {
          sourceType: 'normalized',
          rawInput: trimmed,
          sourceText: typeof parsed.summary === 'string' ? parsed.summary : raw,
          sourcePath,
          normalizedSpec: parsed as Partial<CanonicalProductSpec>
        };
      }
    }

    return {
      sourceType: 'prd',
      rawInput: trimmed,
      sourceText: summarizeStructuredSourceText(raw),
      sourcePath
    };
  }

  return {
    sourceType: hasConstraintFlags ? 'prompt+constraints' : 'prompt',
    rawInput: trimmed,
    sourceText: trimmed
  };
}

export function loadProductLanes(projectRoot: string): ProductLaneDefinition[] {
  return loadJsonDefinitions<ProductLaneDefinition>(path.join(projectRoot, '.agent', 'product-lanes'));
}

export function loadProductPacks(projectRoot: string): ProductPackDefinition[] {
  return loadJsonDefinitions<ProductPackDefinition>(path.join(projectRoot, '.agent', 'packs'));
}

function resolveProductLane(
  projectRoot: string,
  objectiveText: string,
  flags: Record<string, ProductSpecFlagValue>,
  normalizedSpec?: Partial<CanonicalProductSpec>
): { lane: ProductLaneDefinition; laneConfidence: number; laneEvidence: string[] } {
  const lanes = loadProductLanes(projectRoot);
  if (lanes.length === 0) {
    throw new Error('No product lane definitions found in .agent/product-lanes');
  }

  const laneOverride = flagString(flags, 'lane') || (typeof normalizedSpec?.lane === 'string' ? normalizedSpec.lane : undefined);
  if (laneOverride) {
    const matched = lanes.find((lane) => lane.id === laneOverride);
    if (!matched) {
      throw new Error(`Unknown product lane: ${laneOverride}`);
    }
    return {
      lane: matched,
      laneConfidence: typeof normalizedSpec?.laneConfidence === 'number'
        ? Math.max(0, Math.min(1, normalizedSpec.laneConfidence))
        : 1,
      laneEvidence: ['lane override']
    };
  }

  const normalizedText = normalizeSearchText(objectiveText);
  const objectiveKeywords = extractObjectiveKeywords(objectiveText);
  const scored = lanes.map((lane) => {
    const laneKeywords = [
      lane.id,
      lane.name,
      lane.description,
      lane.category,
      ...lane.requiredCapabilities.map((item) => item.replace(/-/gu, ' ')),
      ...(GO_LANE_HINTS[lane.id] || [])
    ];
    const keywordScore = scoreKeywordMatches(normalizedText, laneKeywords);
    const tokenScore = objectiveKeywords.filter((token) => normalizeSearchText(`${lane.id} ${lane.name} ${lane.description}`).includes(token)).length;
    return {
      lane,
      score: keywordScore.score + tokenScore + (lane.v1Mandatory ? 0.25 : 0),
      matches: keywordScore.matches
    };
  }).sort((left, right) => right.score - left.score || left.lane.id.localeCompare(right.lane.id));

  const top = scored[0];
  const secondScore = scored[1]?.score ?? 0;

  if (!top || top.score <= 0) {
    const fallback = lanes.find((lane) => lane.id === 'saas-dashboard') || lanes[0];
    return {
      lane: fallback,
      laneConfidence: 0.34,
      laneEvidence: ['no strong lane keywords found; defaulted to saas-dashboard']
    };
  }

  const confidence = Number(
    Math.min(
      0.98,
      Math.max(0.55, top.score / Math.max(1, top.score + secondScore + 1) + (top.score - secondScore >= 2 ? 0.1 : 0))
    ).toFixed(2)
  );

  return {
    lane: top.lane,
    laneConfidence: confidence,
    laneEvidence: top.matches.slice(0, 5)
  };
}

function resolveTargetStack(
  lane: ProductLaneDefinition,
  objectiveText: string,
  flags: Record<string, ProductSpecFlagValue>,
  normalizedSpec?: Partial<CanonicalProductSpec>
): { targetStack: string; notes: string[] } {
  const override = flagString(flags, 'target-stack') || (typeof normalizedSpec?.targetStack === 'string' ? normalizedSpec.targetStack : undefined);
  if (override) {
    if (!lane.allowedStacks.includes(override)) {
      return {
        targetStack: lane.defaultStack,
        notes: [`Requested stack ${override} is not allowed for lane ${lane.id}; using ${lane.defaultStack}.`]
      };
    }
    return { targetStack: override, notes: [] };
  }

  const lower = normalizeSearchText(objectiveText);
  const preferences = [
    { keyword: 'next.js', stack: 'nextjs-app-router' },
    { keyword: 'nextjs', stack: 'nextjs-app-router' },
    { keyword: 'vite react node', stack: 'vite-react-node' },
    { keyword: 'vite react', stack: 'vite-react' },
    { keyword: 'mdx', stack: 'mdx-docs-site' },
    { keyword: 'docs site', stack: 'mdx-docs-site' }
  ];

  const matched = preferences.find((item) => lower.includes(item.keyword) && lane.allowedStacks.includes(item.stack));
  return {
    targetStack: matched?.stack || lane.defaultStack,
    notes: []
  };
}

function resolveRequestedPackIds(
  objectiveText: string,
  flags: Record<string, ProductSpecFlagValue>,
  normalizedSpec?: Partial<CanonicalProductSpec>
): string[] {
  const lower = normalizeSearchText(objectiveText);
  const requested = new Set<string>(flagStringArray(flags, 'pack'));

  if (Array.isArray(normalizedSpec?.enterprisePacks)) {
    normalizedSpec.enterprisePacks.forEach((item) => {
      if (typeof item === 'string') {
        requested.add(item);
      }
    });
  }

  for (const [packId, keywords] of Object.entries(GO_PACK_HINTS)) {
    if (objectiveRequestsPack(packId, lower, keywords)) {
      requested.add(packId);
    }
  }

  return Array.from(requested);
}

function objectiveRequestsPack(packId: string, lower: string, keywords: string[]): boolean {
  if (packId === 'billing-stripe') {
    return objectiveRequestsBillingStripePack(lower);
  }

  return keywords.some((keyword) => lower.includes(normalizeSearchText(keyword)));
}

function objectiveRequestsBillingStripePack(lower: string): boolean {
  const negatedSignals = [
    /\binformational pricing\b/iu,
    /\bpricing section only\b/iu,
    /\bdo not add\b[\s\S]{0,160}\b(stripe|checkout|subscriptions?|payments?|billing api|billing apis|billing integration)\b/iu,
    /\bno\b[\s\S]{0,80}\b(stripe|checkout|subscriptions?|payments?|billing api|billing apis|billing integration)\b/iu,
    /\bwithout\b[\s\S]{0,80}\b(stripe|checkout|subscriptions?|payments?|billing api|billing apis|billing integration)\b/iu
  ];

  if (negatedSignals.some((pattern) => pattern.test(lower))) {
    return false;
  }

  const strongSignals = [
    /\bstripe\b/iu,
    /\bcheckout\b/iu,
    /\bsubscriptions?\b/iu,
    /\bpayments?\b/iu,
    /\bbilling (portal|settings|integration|integrations|provider|providers|api|apis|webhook)\b/iu,
    /\b(customer|self serve|self-serve|subscription)\s+billing\b/iu
  ];

  return strongSignals.some((pattern) => pattern.test(lower));
}

function resolveProductPacks(
  projectRoot: string,
  lane: ProductLaneDefinition,
  objectiveText: string,
  flags: Record<string, ProductSpecFlagValue>,
  normalizedSpec?: Partial<CanonicalProductSpec>
): {
  selectedPacks: ProductPackDefinition[];
  requestedPackIds: string[];
  unsupportedRequestedPackIds: string[];
  missingConfig: string[];
  reviewReasons: string[];
} {
  const packDefinitions = loadProductPacks(projectRoot);
  const packMap = new Map(packDefinitions.map((pack) => [pack.id, pack]));
  const requestedPackIds = resolveRequestedPackIds(objectiveText, flags, normalizedSpec);
  const unsupportedRequestedPackIds: string[] = [];
  const selectedPackIds = new Set(lane.defaultPacks);

  requestedPackIds.forEach((packId) => {
    if (!lane.allowedPacks.includes(packId)) {
      unsupportedRequestedPackIds.push(packId);
      return;
    }
    selectedPackIds.add(packId);
  });

  const selectedPacks = Array.from(selectedPackIds)
    .map((packId) => packMap.get(packId))
    .filter((pack): pack is ProductPackDefinition => Boolean(pack))
    .filter((pack) => pack.compatibleLanes.includes(lane.id));

  const missingConfig = uniqueStrings(selectedPacks.flatMap((pack) => pack.requiredConfig));
  const reviewReasons = uniqueStrings([
    ...unsupportedRequestedPackIds.map((packId) => `Requested pack ${packId} is not allowed for lane ${lane.id}.`),
    ...selectedPacks.filter((pack) => pack.reviewRequired).map((pack) => `Pack ${pack.id} requires human review.`),
    ...missingConfig.map((config) => `Missing required configuration: ${config}.`)
  ]);

  return {
    selectedPacks,
    requestedPackIds,
    unsupportedRequestedPackIds,
    missingConfig,
    reviewReasons
  };
}

function deriveRiskTier(lane: ProductLaneDefinition, selectedPacks: ProductPackDefinition[]): 'low' | 'medium' | 'high' {
  if (selectedPacks.some((pack) => pack.riskTier === 'high')) {
    return 'high';
  }
  if (selectedPacks.some((pack) => pack.riskTier === 'medium')) {
    return 'medium';
  }
  return lane.id === 'marketing-site' || lane.id === 'content-portal' ? 'low' : 'medium';
}

function resolveDeliveryTarget(
  objectiveText: string,
  flags: Record<string, ProductSpecFlagValue>,
  normalizedSpec?: Partial<CanonicalProductSpec>
): { deliveryTarget: DeliveryTarget; downstreamTarget?: string } {
  const override = flagString(flags, 'delivery-target') || (typeof normalizedSpec?.deliveryTarget === 'string' ? normalizedSpec.deliveryTarget : undefined);
  const downstreamOverride = flagString(flags, 'downstream-target') || (typeof normalizedSpec?.downstreamTarget === 'string' ? normalizedSpec.downstreamTarget : undefined);

  if (override === 'local-repo' || override === 'portable-target' || override === 'downstream-install') {
    return {
      deliveryTarget: override,
      downstreamTarget: override === 'downstream-install' ? downstreamOverride : undefined
    };
  }

  const lower = normalizeSearchText(objectiveText);
  if (lower.includes('ggv3')) {
    return { deliveryTarget: 'downstream-install', downstreamTarget: 'GGV3' };
  }
  if (lower.includes('portable')) {
    return { deliveryTarget: 'portable-target' };
  }
  if (lower.includes('downstream') || lower.includes('install the harness into') || lower.includes('install into ggv3')) {
    return {
      deliveryTarget: 'downstream-install',
      downstreamTarget: downstreamOverride
    };
  }

  return { deliveryTarget: 'local-repo' };
}

export function buildCanonicalProductSpec(
  projectRoot: string,
  source: GoSourceInput,
  promptContext: CanonicalSpecPromptContext,
  flags: Record<string, ProductSpecFlagValue>
): GoProductResolution {
  const normalizedSpec = source.normalizedSpec;
  const laneResolution = resolveProductLane(projectRoot, promptContext.normalizedObjective, flags, normalizedSpec);
  const stackResolution = resolveTargetStack(laneResolution.lane, promptContext.normalizedObjective, flags, normalizedSpec);
  const packResolution = resolveProductPacks(projectRoot, laneResolution.lane, promptContext.normalizedObjective, flags, normalizedSpec);
  const delivery = resolveDeliveryTarget(promptContext.normalizedObjective, flags, normalizedSpec);
  const riskTier = deriveRiskTier(laneResolution.lane, packResolution.selectedPacks);

  const reviewReasons = uniqueStrings([
    ...packResolution.reviewReasons,
    laneResolution.laneConfidence < 0.6 ? `Lane confidence is low (${laneResolution.laneConfidence}).` : '',
    !laneResolution.lane.v1Mandatory ? `Lane ${laneResolution.lane.id} is not part of the mandatory V1 proof set.` : '',
    delivery.deliveryTarget !== 'local-repo' ? `Delivery target ${delivery.deliveryTarget} requires downstream review.` : '',
    ...stackResolution.notes
  ]).filter(Boolean);

  const constraints = uniqueStrings([
    ...(Array.isArray(normalizedSpec?.constraints) ? normalizedSpec.constraints.filter((item): item is string => typeof item === 'string') : []),
    ...promptContext.constraints,
    ...stackResolution.notes,
    ...packResolution.unsupportedRequestedPackIds.map((packId) => `Drop or replace unsupported pack ${packId} for lane ${laneResolution.lane.id}.`),
    ...packResolution.missingConfig.map((config) => `Provide ${config} before fully unattended execution.`)
  ]).filter(Boolean);

  const requiredIntegrations = uniqueStrings([
    ...(Array.isArray(normalizedSpec?.requiredIntegrations)
      ? normalizedSpec.requiredIntegrations.filter((item): item is string => typeof item === 'string')
      : []),
    ...packResolution.selectedPacks.flatMap((pack) => GO_PACK_INTEGRATIONS[pack.id] || pack.requiredConfig)
  ]).filter(Boolean);

  const acceptanceCriteria = uniqueStrings([
    ...(Array.isArray(normalizedSpec?.acceptanceCriteria)
      ? normalizedSpec.acceptanceCriteria.filter((item): item is string => typeof item === 'string')
      : []),
    `Deliver the ${laneResolution.lane.name} lane using ${stackResolution.targetStack}.`,
    `Support lane capabilities: ${laneResolution.lane.requiredCapabilities.join(', ')}.`,
    `Apply enterprise packs: ${packResolution.selectedPacks.map((pack) => pack.id).join(', ')}.`,
    ...promptContext.acceptanceCriteria
  ]).filter(Boolean);

  const canonicalSpec: CanonicalProductSpec = {
    schemaVersion: 1,
    sourceType: source.sourceType,
    sourcePath: source.sourcePath,
    summary: typeof normalizedSpec?.summary === 'string' ? normalizedSpec.summary : promptContext.normalizedObjective,
    lane: laneResolution.lane.id,
    laneConfidence: typeof normalizedSpec?.laneConfidence === 'number'
      ? Math.max(0, Math.min(1, normalizedSpec.laneConfidence))
      : laneResolution.laneConfidence,
    targetStack: stackResolution.targetStack,
    riskTier,
    enterprisePacks: packResolution.selectedPacks.map((pack) => pack.id),
    constraints,
    requiredIntegrations,
    acceptanceCriteria,
    validationProfile: laneResolution.lane.id,
    deliveryTarget: delivery.deliveryTarget,
    downstreamTarget: delivery.downstreamTarget,
    requiresHumanReview: Boolean(normalizedSpec?.requiresHumanReview) || reviewReasons.length > 0
  };

  return {
    canonicalSpec,
    lane: laneResolution.lane,
    laneConfidence: canonicalSpec.laneConfidence,
    laneEvidence: laneResolution.laneEvidence,
    selectedPacks: packResolution.selectedPacks,
    requestedPackIds: packResolution.requestedPackIds,
    unsupportedRequestedPackIds: packResolution.unsupportedRequestedPackIds,
    missingConfig: packResolution.missingConfig,
    reviewReasons
  };
}
