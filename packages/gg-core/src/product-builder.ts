import fs from 'node:fs';
import path from 'node:path';

import type { CanonicalProductSpec, ProductLaneDefinition, ProductPackDefinition } from './product-spec.js';

export interface ProductBundleFile {
  path: string;
  kind: 'config' | 'code' | 'doc';
}

export interface ProductBundleManifest {
  schemaVersion: 1;
  bundleId: string;
  generatedAt: string;
  summary: string;
  lane: string;
  targetStack: string;
  deliveryTarget: CanonicalProductSpec['deliveryTarget'];
  downstreamTarget?: string;
  enterprisePacks: string[];
  requiredIntegrations: string[];
  requiredGates: string[];
  acceptanceCriteria: string[];
  constraints: string[];
  requiresHumanReview: boolean;
  files: ProductBundleFile[];
  commands: {
    install: string;
    dev: string;
    build: string;
    lint: string;
    typecheck: string;
  };
}

export interface ProductBundleResult {
  bundleId: string;
  bundleDir: string;
  manifestPath: string;
  manifest: ProductBundleManifest;
  files: ProductBundleFile[];
}

export interface ProductBundleOptions {
  projectRoot: string;
  spec: CanonicalProductSpec;
  lane: ProductLaneDefinition;
  selectedPacks: ProductPackDefinition[];
  bundleId: string;
  outputDir?: string;
  overwrite?: boolean;
}

interface BundleContent {
  siteConfig: {
    name: string;
    eyebrow: string;
    headline: string;
    description: string;
    baseUrl: string;
    lane: string;
    targetStack: string;
  };
  navItems: Array<{ label: string; href: string }>;
  heroStats: Array<{ label: string; value: string }>;
  trustBadges: string[];
  proofPoints: Array<{ label: string; value: string }>;
  featureHighlights: Array<{ title: string; body: string }>;
  useCaseCards: Array<{ title: string; body: string }>;
  caseStudies: Array<{ company: string; outcome: string; detail: string }>;
  faqItems: Array<{ question: string; answer: string }>;
  finalCta: {
    eyebrow: string;
    headline: string;
    body: string;
    primaryLabel: string;
    primaryHref: string;
    secondaryLabel: string;
    secondaryHref: string;
  };
  capabilityCards: Array<{ title: string; body: string }>;
  packCards: Array<{ title: string; body: string }>;
  acceptanceCards: Array<{ title: string; body: string }>;
  pricingTiers: Array<{ name: string; price: string; summary: string; features: string[] }>;
  contactChannels: Array<{ label: string; detail: string }>;
  dashboardStats: Array<{ label: string; value: string; trend: string }>;
  dashboardModules: Array<{ title: string; body: string }>;
  dashboardAlerts: Array<{ title: string; detail: string; severity: 'low' | 'medium' | 'high' }>;
  adminQueues: Array<{ name: string; owner: string; status: string }>;
  adminOperators: Array<{ name: string; role: string; shift: string }>;
  auditEntries: Array<{ actor: string; action: string; at: string }>;
}

interface ProductBundleTemplate {
  files: ProductBundleFile[];
  content: BundleContent;
}

interface ParsedMarkdownSection {
  level: number;
  title: string;
  body: string[];
}

interface MarketingSignals {
  productName?: string;
  audience: string[];
  primaryGoal?: string;
  coreNarrative?: string;
  brandDirection: string[];
  messagingRequirements: string[];
  productThemes: string[];
  requiredOutcomes: string[];
  useCases: string[];
  faqPrompts: string[];
}

const SUPPORTED_STACKS = new Set(['nextjs-app-router']);

function isoNow(): string {
  return new Date().toISOString();
}

function uniqueStrings(items: string[]): string[] {
  return Array.from(new Set(items.filter(Boolean)));
}

function capitalize(value: string): string {
  if (!value) {
    return value;
  }
  return `${value[0].toUpperCase()}${value.slice(1)}`;
}

function titleCase(value: string): string {
  return value
    .split(/\s+/u)
    .filter(Boolean)
    .map((item) => capitalize(item))
    .join(' ');
}

function humanizeToken(value: string): string {
  return titleCase(value.replace(/[_-]+/gu, ' '));
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/gu, '-')
    .replace(/^-+|-+$/gu, '')
    .slice(0, 64);
}

function ensureCleanDir(dirPath: string, overwrite: boolean): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
    return;
  }

  const entries = fs.readdirSync(dirPath);
  if (entries.length === 0) {
    return;
  }

  if (!overwrite) {
    throw new Error(`Output directory already exists and is not empty: ${dirPath}`);
  }

  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeTextFile(root: string, relativePath: string, content: string): void {
  const filePath = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${content.replace(/\s+$/u, '')}\n`, 'utf8');
}

function normalizeHeading(value: string): string {
  return value.toLowerCase().trim().replace(/[`"'*:_-]+/gu, ' ').replace(/\s+/gu, ' ');
}

function parseMarkdownSections(raw: string): ParsedMarkdownSection[] {
  const sections: ParsedMarkdownSection[] = [];
  let current: ParsedMarkdownSection | null = null;

  for (const line of raw.split('\n')) {
    const headingMatch = /^(#{1,6})\s+(.+?)\s*$/u.exec(line.trim());
    if (headingMatch) {
      if (current) {
        sections.push(current);
      }
      current = {
        level: headingMatch[1].length,
        title: headingMatch[2].trim(),
        body: []
      };
      continue;
    }

    if (current) {
      current.body.push(line);
    }
  }

  if (current) {
    sections.push(current);
  }

  return sections;
}

function sectionBodyLines(section?: ParsedMarkdownSection): string[] {
  if (!section) {
    return [];
  }

  return section.body
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => !line.startsWith('```'));
}

function sectionParagraph(section?: ParsedMarkdownSection): string {
  return sectionBodyLines(section)
    .filter((line) => !/^[-*+]\s+/u.test(line))
    .join(' ')
    .replace(/\s+/gu, ' ')
    .trim();
}

function sectionBullets(section?: ParsedMarkdownSection): string[] {
  return sectionBodyLines(section)
    .filter((line) => /^[-*+]\s+/u.test(line))
    .map((line) => line.replace(/^[-*+]\s+/u, '').trim())
    .filter(Boolean);
}

function findSection(sections: ParsedMarkdownSection[], title: string): ParsedMarkdownSection | undefined {
  const target = normalizeHeading(title);
  return sections.find((section) => normalizeHeading(section.title) === target);
}

function findChildSections(sections: ParsedMarkdownSection[], parentTitle: string): ParsedMarkdownSection[] {
  const parent = findSection(sections, parentTitle);
  if (!parent) {
    return [];
  }

  const parentIndex = sections.indexOf(parent);
  const children: ParsedMarkdownSection[] = [];

  for (let index = parentIndex + 1; index < sections.length; index += 1) {
    const section = sections[index];
    if (section.level <= parent.level) {
      break;
    }
    children.push(section);
  }

  return children;
}

function readSourceDocument(projectRoot: string, spec: CanonicalProductSpec): string {
  if (!spec.sourcePath) {
    return '';
  }

  const candidatePath = path.join(projectRoot, spec.sourcePath);
  if (!fs.existsSync(candidatePath) || !fs.statSync(candidatePath).isFile()) {
    return '';
  }

  try {
    return fs.readFileSync(candidatePath, 'utf8');
  } catch {
    return '';
  }
}

function extractProductNameFromSource(raw: string): string | undefined {
  const patterns = [
    /called\s+[`'"]?([A-Z][A-Za-z0-9]+(?:\s+[A-Z][A-Za-z0-9]+)*)[`'"]?/u,
    /for\s+[`'"]?([A-Z][A-Za-z0-9]+(?:\s+[A-Z][A-Za-z0-9]+)*)[`'"]?/u
  ];

  for (const pattern of patterns) {
    const match = pattern.exec(raw);
    if (match?.[1]) {
      return match[1].trim();
    }
  }

  return undefined;
}

function deriveMarketingSignals(projectRoot: string, spec: CanonicalProductSpec): MarketingSignals {
  const rawSource = readSourceDocument(projectRoot, spec);
  const sections = parseMarkdownSections(rawSource);
  const contentBlockSections = findChildSections(sections, 'Required Content Blocks');
  const faqSection = contentBlockSections.find((section) => normalizeHeading(section.title) === 'faq');
  const useCaseSection = contentBlockSections.find((section) => normalizeHeading(section.title) === 'use cases');

  const productSection = findSection(sections, 'Product');
  const audienceSection = findSection(sections, 'Audience');
  const goalSection = findSection(sections, 'Primary Goal');
  const narrativeSection = findSection(sections, 'Core Narrative');
  const brandSection = findSection(sections, 'Brand Direction');
  const messagingSection = findSection(sections, 'Messaging Requirements');
  const themesSection = findSection(sections, 'Product Themes To Highlight');
  const outcomesSection = findSection(sections, 'Required Site Outcomes');

  return {
    productName: extractProductNameFromSource(rawSource) || extractProductNameFromSource(sectionParagraph(productSection)),
    audience: sectionBullets(audienceSection),
    primaryGoal: sectionParagraph(goalSection),
    coreNarrative: sectionParagraph(narrativeSection),
    brandDirection: [
      ...sectionBullets(brandSection),
      ...sectionBodyLines(brandSection).filter((line) => !/^[-*+]\s+/u.test(line))
    ],
    messagingRequirements: sectionBullets(messagingSection),
    productThemes: sectionBullets(themesSection),
    requiredOutcomes: sectionBullets(outcomesSection),
    useCases: [
      ...sectionBullets(useCaseSection),
      ...sectionBullets(findSection(sections, 'Use Cases'))
    ],
    faqPrompts: [
      ...sectionBullets(faqSection),
      ...sectionBullets(findSection(sections, 'FAQ'))
    ]
  };
}

function productFallbackName(laneId: string): string {
  switch (laneId) {
    case 'marketing-site':
      return 'Signal Foundry';
    case 'saas-dashboard':
      return 'Control Atlas';
    case 'admin-panel':
      return 'Ops Ledger';
    default:
      return 'Enterprise Product';
  }
}

function deriveProductName(summary: string, laneId: string): string {
  const tokens = summary
    .toLowerCase()
    .replace(/[^a-z0-9\s-]+/gu, ' ')
    .split(/\s+/u)
    .filter((token) => token.length > 2)
    .filter((token) => !['build', 'create', 'launch', 'design', 'site', 'dashboard', 'panel', 'with', 'from', 'for', 'into'].includes(token));

  const words = uniqueStrings(tokens).slice(0, 2).map((token) => titleCase(token));
  return words.length > 0 ? words.join(' ') : productFallbackName(laneId);
}

function deriveEyebrow(spec: CanonicalProductSpec, lane: ProductLaneDefinition): string {
  return `${humanizeToken(lane.id)} bundle for ${spec.deliveryTarget.replace(/-/gu, ' ')}`;
}

function describeCapability(capability: string): string {
  const humanized = humanizeToken(capability);
  return `${humanized} is scaffolded as a first-class surface instead of being left as follow-up glue code.`;
}

function describePack(pack: ProductPackDefinition): string {
  const added = pack.addsCapabilities.map(humanizeToken).join(', ');
  return added
    ? `${pack.description} Included capabilities: ${added}.`
    : pack.description;
}

function describeAcceptance(item: string, index: number): { title: string; body: string } {
  return {
    title: `Acceptance ${index + 1}`,
    body: item
  };
}

function buildHeroStats(
  spec: CanonicalProductSpec,
  lane: ProductLaneDefinition,
  selectedPacks: ProductPackDefinition[]
): Array<{ label: string; value: string }> {
  return [
    { label: 'Enabled packs', value: String(spec.enterprisePacks.length) },
    { label: 'Required gates', value: String(uniqueStrings([...lane.requiredGates, ...selectedPacks.flatMap((pack) => pack.requiredGates)]).length) },
    { label: 'Integrations', value: String(spec.requiredIntegrations.length) }
  ];
}

function firstItem(items: string[], fallback: string): string {
  return items.find(Boolean) || fallback;
}

function shortAudienceLabel(audience: string[]): string {
  const first = audience.find(Boolean);
  if (!first) {
    return 'Enterprise ops';
  }

  return first
    .replace(/^head of\s+/iu, '')
    .replace(/^vp of\s+/iu, 'VP ')
    .replace(/\s+leaders?$/iu, '')
    .trim();
}

function buildMarketingHeadline(productName: string, signals: MarketingSignals): string {
  const narrative = signals.coreNarrative?.replace(/\s+/gu, ' ').trim();
  if (narrative) {
    const directTurn = /^.+?\s+turns\s+(.+)$/iu.exec(narrative);
    if (directTurn?.[1]) {
      return `Turn ${directTurn[1].replace(/\.$/u, '')}`;
    }
  }

  return `${productName} automates complex operations without fragile internal tooling.`;
}

function buildMarketingDescription(productName: string, signals: MarketingSignals): string {
  const audience = signals.audience.length > 0
    ? `Built for ${signals.audience.slice(0, 3).join(', ')}.`
    : 'Built for enterprise operations and systems teams.';
  const narrative = signals.coreNarrative
    ? signals.coreNarrative.replace(/\s+/gu, ' ').trim()
    : `${productName} helps teams orchestrate approvals, exceptions, and cross-system work in one governed operating layer.`;

  return `${narrative} ${audience}`.trim();
}

function buildMarketingTrustBadges(signals: MarketingSignals): string[] {
  if (signals.audience.length > 0) {
    return signals.audience.slice(0, 4);
  }

  return ['Operations', 'Revenue Ops', 'Finance', 'IT'];
}

function buildMarketingProofPoints(signals: MarketingSignals): Array<{ label: string; value: string }> {
  const useCases = signals.useCases.length > 0 ? `${signals.useCases.length}+` : '4+';
  const systems = signals.requiredOutcomes.some((item) => /pricing|contact|case studies/iu.test(item))
    ? 'Launch-ready'
    : 'CRM + billing + support';

  return [
    { label: 'Core use cases', value: useCases },
    { label: 'Primary buyer', value: shortAudienceLabel(signals.audience) },
    { label: 'Operating surface', value: systems }
  ];
}

function buildMarketingFeatureHighlights(
  signals: MarketingSignals,
  selectedPacks: ProductPackDefinition[]
): Array<{ title: string; body: string }> {
  const themeCards = signals.productThemes.map((theme) => ({
    title: titleCase(theme),
    body: `${titleCase(theme)} is presented as an operational advantage, not just a feature checklist.`
  }));
  const packCards = selectedPacks.map((pack) => ({
    title: humanizeToken(pack.id),
    body: describePack(pack)
  }));

  return [...themeCards, ...packCards].slice(0, 6);
}

function buildMarketingUseCases(signals: MarketingSignals): Array<{ title: string; body: string }> {
  const defaultUseCases = [
    'Quote-to-cash orchestration',
    'Support escalation automation',
    'Finance approvals',
    'Renewal and onboarding operations'
  ];

  return (signals.useCases.length > 0 ? signals.useCases : defaultUseCases)
    .slice(0, 4)
    .map((item) => ({
      title: titleCase(item),
      body: `${titleCase(item)} gets a governed workflow story, clearer ownership, and fewer handoff gaps across teams and systems.`
    }));
}

function buildMarketingCaseStudies(productName: string, useCases: Array<{ title: string; body: string }>): Array<{ company: string; outcome: string; detail: string }> {
  const orgNames = ['Northstar RevOps', 'Harborline Finance', 'Atlas Support'];

  return useCases.slice(0, 3).map((item, index) => ({
    company: orgNames[index] || `${productName} Customer ${index + 1}`,
    outcome: `${item.title} moved from manual handoffs to governed execution.`,
    detail: item.body
  }));
}

function buildMarketingFaqItems(signals: MarketingSignals): Array<{ question: string; answer: string }> {
  const defaults = [
    'How quickly can a team launch?',
    'How does governance work?',
    'What systems can it integrate with?',
    'Who owns the workflows after rollout?'
  ];

  return (signals.faqPrompts.length > 0 ? signals.faqPrompts : defaults)
    .slice(0, 4)
    .map((question) => ({
      question: question.endsWith('?') ? question : `${question}?`,
      answer: 'The launch path is structured around controlled rollout, clear ownership, and operational visibility rather than fragile one-off automations.'
    }));
}

function buildMarketingPricingTiers(productName: string, signals: MarketingSignals): Array<{ name: string; price: string; summary: string; features: string[] }> {
  const firstUseCase = firstItem(signals.useCases, 'Cross-functional operations');

  return [
    {
      name: 'Pilot',
      price: 'From $2.5k/mo',
      summary: `A focused rollout for teams validating ${productName} against one high-value workflow.`,
      features: ['Single-team launch', titleCase(firstUseCase), 'Executive-ready reporting baseline']
    },
    {
      name: 'Scale',
      price: 'Custom',
      summary: 'Expand into multiple business systems with governed rollout and clearer operational ownership.',
      features: ['Cross-system orchestration', 'Exception handling and approvals', 'Observability and audit surfaces']
    },
    {
      name: 'Enterprise',
      price: 'Talk to sales',
      summary: 'A rollout path for multi-team operating models, tighter controls, and executive adoption.',
      features: ['Multi-team governance', 'Pack-aware implementation plan', 'Security and operations review path']
    }
  ];
}

function buildMarketingContactChannels(productName: string, signals: MarketingSignals): Array<{ label: string; detail: string }> {
  return [
    { label: 'Primary CTA', detail: 'Book a Demo' },
    { label: 'Secondary CTA', detail: 'See Platform Overview' },
    { label: 'Best-fit teams', detail: signals.audience.slice(0, 3).join(', ') || `${productName} is designed for enterprise operations and systems leaders.` }
  ];
}

function buildMarketingFinalCta(productName: string, signals: MarketingSignals) {
  return {
    eyebrow: 'Launch motion',
    headline: `Give ${productName} a real enterprise launch surface.`,
    body: signals.primaryGoal
      ? signals.primaryGoal
      : 'Turn the product story into a conversion-ready demo funnel with clearer positioning, proof, and rollout confidence.',
    primaryLabel: 'Book a Demo',
    primaryHref: '/contact',
    secondaryLabel: 'See Platform Overview',
    secondaryHref: '/pricing'
  };
}

function buildDashboardStats(selectedPacks: ProductPackDefinition[]): Array<{ label: string; value: string; trend: string }> {
  return [
    { label: 'Active workspaces', value: '24', trend: '+3.2% week over week' },
    { label: 'Automations healthy', value: `${92 + Math.min(7, selectedPacks.length)}%`, trend: 'steady after latest release' },
    { label: 'Incidents in review', value: `${Math.max(2, selectedPacks.length)}`, trend: 'triage queue stays below threshold' }
  ];
}

function buildDashboardModules(
  lane: ProductLaneDefinition,
  selectedPacks: ProductPackDefinition[]
): Array<{ title: string; body: string }> {
  const laneModules = lane.requiredCapabilities.map((capability) => ({
    title: humanizeToken(capability),
    body: describeCapability(capability)
  }));
  const packModules = selectedPacks.map((pack) => ({
    title: humanizeToken(pack.id),
    body: describePack(pack)
  }));
  return [...laneModules, ...packModules].slice(0, 6);
}

function buildDashboardAlerts(spec: CanonicalProductSpec): Array<{ title: string; detail: string; severity: 'low' | 'medium' | 'high' }> {
  return [
    {
      title: 'Validation gate alignment',
      detail: `${spec.validationProfile} is encoded as the default validation profile for this bundle.`,
      severity: spec.requiresHumanReview ? 'medium' : 'low'
    },
    {
      title: 'Human review contract',
      detail: spec.requiresHumanReview
        ? 'At least one pack or constraint requires reviewer sign-off before merge.'
        : 'No extra review packs were detected in the selected configuration.',
      severity: spec.requiresHumanReview ? 'high' : 'low'
    },
    {
      title: 'Delivery target',
      detail: spec.deliveryTarget === 'downstream-install'
        ? `Bundle is shaped for downstream install into ${spec.downstreamTarget || 'the named target'}.`
        : `Bundle is prepared for ${spec.deliveryTarget.replace(/-/gu, ' ')} handoff.`,
      severity: spec.deliveryTarget === 'local-repo' ? 'low' : 'medium'
    }
  ];
}

function buildAdminQueues(selectedPacks: ProductPackDefinition[]): Array<{ name: string; owner: string; status: string }> {
  return [
    { name: 'Escalations', owner: 'Ops duty', status: 'Watching latency envelope' },
    { name: 'Policy review', owner: 'Risk lead', status: selectedPacks.some((pack) => pack.id === 'compliance-baseline') ? 'Compliance bundle enabled' : 'Ready for manual policy inputs' },
    { name: 'Operator exceptions', owner: 'Platform admin', status: 'Permissions scoped and auditable' }
  ];
}

function buildAdminOperators(): Array<{ name: string; role: string; shift: string }> {
  return [
    { name: 'Avery Stone', role: 'Operations lead', shift: 'West / daytime' },
    { name: 'Jordan Vale', role: 'Incident commander', shift: 'Global / rolling' },
    { name: 'Kai Mercer', role: 'Compliance reviewer', shift: 'East / daytime' }
  ];
}

function buildAuditEntries(spec: CanonicalProductSpec): Array<{ actor: string; action: string; at: string }> {
  return [
    { actor: 'system', action: `Generated ${humanizeToken(spec.lane)} bundle contract`, at: '2026-03-09T09:00:00Z' },
    { actor: 'builder', action: `Attached packs: ${spec.enterprisePacks.join(', ') || 'none'}`, at: '2026-03-09T09:02:00Z' },
    { actor: 'review', action: spec.requiresHumanReview ? 'Manual review still required before production merge' : 'No additional review packs requested', at: '2026-03-09T09:05:00Z' }
  ];
}

function buildPricingTiers(productName: string, spec: CanonicalProductSpec): Array<{ name: string; price: string; summary: string; features: string[] }> {
  return [
    {
      name: 'Pilot',
      price: '$1,200',
      summary: `Fast validation path for ${productName} stakeholders.`,
      features: [
        'Conversion-focused landing surface',
        'Single workspace analytics summary',
        `Delivery target: ${spec.deliveryTarget.replace(/-/gu, ' ')}`
      ]
    },
    {
      name: 'Operational',
      price: '$3,800',
      summary: 'Full operating shell for buyers and internal operators.',
      features: [
        'Role-aware navigation patterns',
        'Audit and observability surfaces',
        'Enterprise-ready handoff bundle'
      ]
    },
    {
      name: 'Enterprise',
      price: 'Custom',
      summary: 'Pack-augmented rollout for regulated or multi-team deployment.',
      features: [
        `Selected packs: ${spec.enterprisePacks.join(', ') || 'none'}`,
        'Delivery checklist and manifest included',
        'Prepared for downstream install or local hardening'
      ]
    }
  ];
}

function buildContactChannels(spec: CanonicalProductSpec): Array<{ label: string; detail: string }> {
  const integrations = spec.requiredIntegrations.length > 0
    ? spec.requiredIntegrations.join(', ')
    : 'No external integrations were required by the selected packs.';

  return [
    { label: 'Implementation channel', detail: 'handoff@geargrind.dev' },
    { label: 'Operational handoff', detail: spec.deliveryTarget === 'downstream-install' ? `Coordinate downstream install into ${spec.downstreamTarget || 'the named target'}.` : 'Bundle can be unpacked directly into a target repo.' },
    { label: 'Integration notes', detail: integrations }
  ];
}

function buildBundleContent(
  projectRoot: string,
  spec: CanonicalProductSpec,
  lane: ProductLaneDefinition,
  selectedPacks: ProductPackDefinition[]
): BundleContent {
  const baseProductName = deriveProductName(spec.summary, lane.id);
  const marketingSignals = lane.id === 'marketing-site'
    ? deriveMarketingSignals(projectRoot, spec)
    : null;
  const productName = marketingSignals?.productName || baseProductName;
  const capabilities = uniqueStrings([
    ...lane.requiredCapabilities,
    ...selectedPacks.flatMap((pack) => pack.addsCapabilities)
  ]);
  const marketingUseCases = marketingSignals ? buildMarketingUseCases(marketingSignals) : [];

  return {
    siteConfig: {
      name: productName,
      eyebrow: lane.id === 'marketing-site' ? 'Enterprise workflow automation' : deriveEyebrow(spec, lane),
      headline: lane.id === 'marketing-site'
        ? buildMarketingHeadline(productName, marketingSignals as MarketingSignals)
        : `${productName} gives ${humanizeToken(lane.id)} teams a head start without sacrificing enterprise structure.`,
      description: lane.id === 'marketing-site'
        ? buildMarketingDescription(productName, marketingSignals as MarketingSignals)
        : spec.summary.endsWith('.') ? spec.summary : `${spec.summary}.`,
      baseUrl: 'https://example.com',
      lane: lane.id,
      targetStack: spec.targetStack
    },
    navItems: lane.id === 'marketing-site'
      ? [
          { label: 'Overview', href: '/' },
          { label: 'Use Cases', href: '#use-cases' },
          { label: 'Pricing', href: '/pricing' },
          { label: 'Contact', href: '/contact' }
        ]
      : lane.id === 'saas-dashboard'
        ? [
            { label: 'Overview', href: '/' },
            { label: 'Dashboard', href: '/dashboard' },
            { label: 'Reports', href: '/dashboard/reports' },
            { label: 'Settings', href: '/dashboard/settings' }
          ]
        : [
            { label: 'Overview', href: '/' },
            { label: 'Ops Home', href: '/ops' },
            { label: 'Incidents', href: '/ops/incidents' },
            { label: 'Audit', href: '/ops/audit' }
          ],
    heroStats: lane.id === 'marketing-site'
      ? buildMarketingProofPoints(marketingSignals as MarketingSignals)
      : buildHeroStats(spec, lane, selectedPacks),
    trustBadges: lane.id === 'marketing-site'
      ? buildMarketingTrustBadges(marketingSignals as MarketingSignals)
      : [],
    proofPoints: lane.id === 'marketing-site'
      ? buildMarketingProofPoints(marketingSignals as MarketingSignals)
      : buildHeroStats(spec, lane, selectedPacks),
    featureHighlights: lane.id === 'marketing-site'
      ? buildMarketingFeatureHighlights(marketingSignals as MarketingSignals, selectedPacks)
      : buildDashboardModules(lane, selectedPacks),
    useCaseCards: marketingUseCases,
    caseStudies: lane.id === 'marketing-site'
      ? buildMarketingCaseStudies(productName, marketingUseCases)
      : [],
    faqItems: lane.id === 'marketing-site'
      ? buildMarketingFaqItems(marketingSignals as MarketingSignals)
      : [],
    finalCta: lane.id === 'marketing-site'
      ? buildMarketingFinalCta(productName, marketingSignals as MarketingSignals)
      : {
          eyebrow: 'Delivery path',
          headline: `Move ${productName} into implementation.`,
          body: 'The generated bundle is ready for targeted hardening, verification, and downstream integration.',
          primaryLabel: 'Continue',
          primaryHref: '/',
          secondaryLabel: 'Review configuration',
          secondaryHref: '/'
        },
    capabilityCards: capabilities.slice(0, 6).map((capability) => ({
      title: humanizeToken(capability),
      body: describeCapability(capability)
    })),
    packCards: selectedPacks.map((pack) => ({
      title: humanizeToken(pack.id),
      body: describePack(pack)
    })),
    acceptanceCards: spec.acceptanceCriteria.slice(0, 6).map(describeAcceptance),
    pricingTiers: lane.id === 'marketing-site'
      ? buildMarketingPricingTiers(productName, marketingSignals as MarketingSignals)
      : buildPricingTiers(productName, spec),
    contactChannels: lane.id === 'marketing-site'
      ? buildMarketingContactChannels(productName, marketingSignals as MarketingSignals)
      : buildContactChannels(spec),
    dashboardStats: buildDashboardStats(selectedPacks),
    dashboardModules: buildDashboardModules(lane, selectedPacks),
    dashboardAlerts: buildDashboardAlerts(spec),
    adminQueues: buildAdminQueues(selectedPacks),
    adminOperators: buildAdminOperators(),
    auditEntries: buildAuditEntries(spec)
  };
}

function buildEnvExample(spec: CanonicalProductSpec): string {
  const lines = [
    'NEXT_PUBLIC_APP_NAME=Generated Product Bundle',
    'NEXT_PUBLIC_APP_URL=http://localhost:3000',
    'NEXT_PUBLIC_APP_ENV=development'
  ];

  if (spec.enterprisePacks.includes('observability')) {
    lines.push('NEXT_PUBLIC_TELEMETRY_ENABLED=true');
    lines.push('NEXT_PUBLIC_SENTRY_DSN=');
  }

  if (spec.enterprisePacks.includes('auth-rbac')) {
    lines.push('AUTH_PROVIDER=clerk');
    lines.push('SESSION_STRATEGY=jwt');
  }

  if (spec.enterprisePacks.includes('billing-stripe')) {
    lines.push('STRIPE_PUBLISHABLE_KEY=');
    lines.push('STRIPE_SECRET_KEY=');
    lines.push('BILLING_MODE=test');
  }

  if (spec.enterprisePacks.includes('notifications')) {
    lines.push('NOTIFICATION_CHANNELS=email,slack');
  }

  if (spec.enterprisePacks.includes('cms-content')) {
    lines.push('CONTENT_SOURCE=mdx');
  }

  if (spec.enterprisePacks.includes('admin-ops')) {
    lines.push('OPERATOR_ROLE_NAMES=owner,ops-admin,reviewer');
  }

  if (spec.enterprisePacks.includes('compliance-baseline')) {
    lines.push('DATA_RETENTION_POLICY=90d');
    lines.push('AUDIT_LOG_POLICY=append-only');
  }

  return lines.join('\n');
}

function renderPackageJson(spec: CanonicalProductSpec, content: BundleContent): string {
  return JSON.stringify({
    name: slugify(content.siteConfig.name) || spec.lane,
    version: '0.1.0',
    private: true,
    scripts: {
      dev: 'next dev',
      build: 'next build',
      start: 'next start',
      lint: 'eslint .',
      typecheck: 'tsc --noEmit'
    },
    dependencies: {
      next: '^16.0.0',
      react: '^19.0.0',
      'react-dom': '^19.0.0'
    },
    devDependencies: {
      '@types/node': '^22.13.9',
      '@types/react': '^19.0.10',
      '@types/react-dom': '^19.0.4',
      eslint: '^9.20.1',
      'eslint-config-next': '^16.0.0',
      typescript: '^5.9.2'
    }
  }, null, 2);
}

function renderTsconfig(): string {
  return JSON.stringify({
    compilerOptions: {
      target: 'ES2020',
      lib: ['dom', 'dom.iterable', 'es2020'],
      allowJs: false,
      skipLibCheck: true,
      strict: true,
      noEmit: true,
      esModuleInterop: true,
      module: 'esnext',
      moduleResolution: 'bundler',
      resolveJsonModule: true,
      isolatedModules: true,
      jsx: 'react-jsx',
      incremental: true,
      plugins: [{ name: 'next' }]
    },
    include: ['next-env.d.ts', '.next/types/**/*.ts', '.next/dev/types/**/*.ts', '**/*.ts', '**/*.tsx'],
    exclude: ['node_modules']
  }, null, 2);
}

function renderNextConfig(): string {
  return [
    "import type { NextConfig } from 'next';",
    '',
    'const projectRoot = process.cwd();',
    '',
    'const nextConfig: NextConfig = {',
    '  reactStrictMode: true,',
    '  turbopack: {',
    '    root: projectRoot',
    '  },',
    '  outputFileTracingRoot: projectRoot',
    '};',
    '',
    'export default nextConfig;'
  ].join('\n');
}

function renderEslintConfig(): string {
  return [
    "import nextVitals from 'eslint-config-next/core-web-vitals';",
    '',
    'const config = [',
    '  ...nextVitals',
    '];',
    '',
    'export default config;'
  ].join('\n');
}

function renderSiteModule(
  content: BundleContent,
  spec: CanonicalProductSpec,
  lane: ProductLaneDefinition,
  selectedPacks: ProductPackDefinition[]
): string {
  return [
    `export const siteContent = ${JSON.stringify({
      ...content,
      contract: {
        summary: spec.summary,
        requiredGates: uniqueStrings([...lane.requiredGates, ...selectedPacks.flatMap((pack) => pack.requiredGates)]).slice(0, 12),
        acceptanceCriteria: spec.acceptanceCriteria,
        constraints: spec.constraints,
        enterprisePacks: spec.enterprisePacks,
        requiredIntegrations: spec.requiredIntegrations,
        deliveryTarget: spec.deliveryTarget,
        downstreamTarget: spec.downstreamTarget || null
      }
    }, null, 2)} as const;`
  ].join('\n');
}

function renderTelemetryModule(spec: CanonicalProductSpec): string {
  return [
    'export const telemetryConfig = {',
    "  enabled: process.env.NEXT_PUBLIC_TELEMETRY_ENABLED !== 'false',",
    "  environment: process.env.NEXT_PUBLIC_APP_ENV || 'development',",
    `  integrations: ${JSON.stringify(spec.requiredIntegrations.filter((item) => item.includes('telemetry') || item.includes('provider')), null, 2)}`,
    '};',
    '',
    'export function describeTelemetry(): string {',
    "  return telemetryConfig.enabled ? `Telemetry enabled for ${telemetryConfig.environment}` : 'Telemetry disabled';",
    '}'
  ].join('\n');
}

function renderAuthModule(): string {
  return [
    'export const authConfig = {',
    "  provider: process.env.AUTH_PROVIDER || 'clerk',",
    "  sessionStrategy: process.env.SESSION_STRATEGY || 'jwt',",
    "  roleCookie: 'gg_role'",
    '};',
    '',
    'export const demoRoles = [',
    "  'owner',",
    "  'admin',",
    "  'analyst',",
    "  'reviewer'",
    '] as const;'
  ].join('\n');
}

function renderButtonComponent(): string {
  return [
    "import type { ReactNode } from 'react';",
    "import Link from 'next/link';",
    '',
    "type ButtonVariant = 'primary' | 'secondary';",
    '',
    'interface ButtonProps {',
    '  href: string;',
    '  children: ReactNode;',
    '  variant?: ButtonVariant;',
    '}',
    '',
    'export function Button({ href, children, variant = \'primary\' }: ButtonProps) {',
    '  return (',
    '    <Link className={`button button--${variant}`} href={href}>',
    '      {children}',
    '    </Link>',
    '  );',
    '}'
  ].join('\n');
}

function renderPanelComponent(): string {
  return [
    "import type { ReactNode } from 'react';",
    '',
    'interface PanelProps {',
    '  title: string;',
    '  eyebrow?: string;',
    '  children: ReactNode;',
    '}',
    '',
    'export function Panel({ title, eyebrow, children }: PanelProps) {',
    '  return (',
    '    <article className="card panel">',
    '      {eyebrow ? <div className="eyebrow">{eyebrow}</div> : null}',
    '      <h3>{title}</h3>',
    '      <div className="stack">{children}</div>',
    '    </article>',
    '  );',
    '}'
  ].join('\n');
}

function renderAppShellComponent(): string {
  return [
    "import type { ReactNode } from 'react';",
    "import Link from 'next/link';",
    '',
    'interface AppShellProps {',
    '  title: string;',
    '  summary: string;',
    '  navItems: ReadonlyArray<{ label: string; href: string }>;',
    '  asideTitle: string;',
    '  asideItems: ReadonlyArray<string>;',
    '  children: ReactNode;',
    '}',
    '',
    'export function AppShell({ title, summary, navItems, asideTitle, asideItems, children }: AppShellProps) {',
    '  return (',
    '    <div className="shell-grid">',
    '      <aside className="shell-sidebar">',
    '        <div className="stack">',
    '          <div className="eyebrow">Operational shell</div>',
    '          <h1 className="shell-title">{title}</h1>',
    '          <p className="muted">{summary}</p>',
    '        </div>',
    '        <nav className="stack shell-nav">',
    '          {navItems.map((item) => (',
    '            <Link key={item.href} href={item.href}>',
    '              {item.label}',
    '            </Link>',
    '          ))}',
    '        </nav>',
    '        <section className="card stack">',
    '          <div className="eyebrow">{asideTitle}</div>',
    '          <ul className="list-reset stack">',
    '            {asideItems.map((item) => (',
    '              <li key={item}>{item}</li>',
    '            ))}',
    '          </ul>',
    '        </section>',
    '      </aside>',
    '      <main className="shell-panel">{children}</main>',
    '    </div>',
    '  );',
    '}'
  ].join('\n');
}

function renderLayout(): string {
  return [
    "import type { Metadata } from 'next';",
    "import type { ReactNode } from 'react';",
    "import './globals.css';",
    "import { siteContent } from '../lib/site';",
    '',
    'export const metadata: Metadata = {',
    '  metadataBase: new URL(siteContent.siteConfig.baseUrl),',
    '  title: {',
    '    default: siteContent.siteConfig.name,',
    "    template: `%s | ${siteContent.siteConfig.name}`",
    '  },',
    '  description: siteContent.siteConfig.description',
    '};',
    '',
    'export default function RootLayout({ children }: { children: ReactNode }) {',
    '  return (',
    '    <html lang="en">',
    '      <body className={`lane-${siteContent.siteConfig.lane}`}>{children}</body>',
    '    </html>',
    '  );',
    '}'
  ].join('\n');
}

function renderGlobalsCss(): string {
  return [
    ':root {',
    '  --bg: #f5f1e8;',
    '  --surface: rgba(255, 255, 255, 0.78);',
    '  --surface-strong: #fffdf8;',
    '  --ink: #132235;',
    '  --muted: #526173;',
    '  --accent: #b4502e;',
    '  --accent-strong: #0d6873;',
    '  --line: rgba(19, 34, 53, 0.12);',
    '  --shadow: 0 24px 80px rgba(15, 27, 45, 0.14);',
    '  --radius-xl: 28px;',
    '  --radius-lg: 18px;',
    '  --font-display: "Space Grotesk", "Avenir Next", "Segoe UI", sans-serif;',
    '  --font-body: "IBM Plex Sans", "Segoe UI", sans-serif;',
    '}',
    '',
    'body.lane-saas-dashboard {',
    '  --bg: #eef4ef;',
    '  --accent: #17685f;',
    '  --accent-strong: #0e3f67;',
    '}',
    '',
    'body.lane-admin-panel {',
    '  --bg: #f4efe7;',
    '  --accent: #8b5527;',
    '  --accent-strong: #233955;',
    '}',
    '',
    '* {',
    '  box-sizing: border-box;',
    '}',
    '',
    'html {',
    '  font-family: var(--font-body);',
    '  background: var(--bg);',
    '  color: var(--ink);',
    '}',
    '',
    'body {',
    '  margin: 0;',
    '  min-height: 100vh;',
    '  background:',
    '    radial-gradient(circle at top right, rgba(13, 104, 115, 0.16), transparent 32%),',
    '    radial-gradient(circle at left center, rgba(180, 80, 46, 0.14), transparent 30%),',
    '    linear-gradient(180deg, #faf7f1 0%, var(--bg) 100%);',
    '}',
    '',
    'a {',
    '  color: inherit;',
    '  text-decoration: none;',
    '}',
    '',
    '.page {',
    '  max-width: 1180px;',
    '  margin: 0 auto;',
    '  padding: 32px 24px 88px;',
    '}',
    '',
    '.topbar, .hero, .section, .shell-panel > section, .shell-sidebar > section {',
    '  margin-bottom: 28px;',
    '}',
    '',
    '.topbar {',
    '  display: flex;',
    '  align-items: center;',
    '  justify-content: space-between;',
    '  gap: 18px;',
    '}',
    '',
    '.brand {',
    '  display: flex;',
    '  flex-direction: column;',
    '  gap: 6px;',
    '}',
    '',
    '.brand-mark {',
    '  display: inline-flex;',
    '  align-items: center;',
    '  gap: 10px;',
    '  font-family: var(--font-display);',
    '  font-size: 1.05rem;',
    '  letter-spacing: 0.06em;',
    '  text-transform: uppercase;',
    '}',
    '',
    '.brand-mark::before {',
    '  content: "";',
    '  width: 14px;',
    '  height: 14px;',
    '  border-radius: 999px;',
    '  background: linear-gradient(135deg, var(--accent), var(--accent-strong));',
    '  box-shadow: 0 0 0 6px rgba(255, 255, 255, 0.55);',
    '}',
    '',
    '.eyebrow {',
    '  font-family: var(--font-display);',
    '  font-size: 0.78rem;',
    '  letter-spacing: 0.1em;',
    '  text-transform: uppercase;',
    '  color: var(--muted);',
    '}',
    '',
    '.nav-inline {',
    '  display: flex;',
    '  flex-wrap: wrap;',
    '  gap: 16px;',
    '  color: var(--muted);',
    '}',
    '',
    '.hero {',
    '  display: grid;',
    '  gap: 24px;',
    '  grid-template-columns: minmax(0, 1.3fr) minmax(320px, 0.7fr);',
    '  align-items: stretch;',
    '}',
    '',
    '.hero-card, .card {',
    '  border: 1px solid var(--line);',
    '  border-radius: var(--radius-xl);',
    '  background: var(--surface);',
    '  backdrop-filter: blur(16px);',
    '  box-shadow: var(--shadow);',
    '  padding: 24px;',
    '}',
    '',
    '.display {',
    '  margin: 0;',
    '  font-family: var(--font-display);',
    '  font-size: clamp(2.5rem, 4vw, 4.8rem);',
    '  line-height: 0.95;',
    '}',
    '',
    '.lede, .muted {',
    '  color: var(--muted);',
    '  line-height: 1.7;',
    '}',
    '',
    '.button-row, .list-reset, .stack {',
    '  display: flex;',
    '  flex-direction: column;',
    '  gap: 14px;',
    '}',
    '',
    '.button-row {',
    '  flex-direction: row;',
    '  flex-wrap: wrap;',
    '  margin-top: 24px;',
    '}',
    '',
    '.button {',
    '  display: inline-flex;',
    '  align-items: center;',
    '  justify-content: center;',
    '  min-height: 44px;',
    '  padding: 0 18px;',
    '  border-radius: 999px;',
    '  border: 1px solid transparent;',
    '  font-weight: 600;',
    '  transition: transform 160ms ease, box-shadow 160ms ease;',
    '}',
    '',
    '.button:hover {',
    '  transform: translateY(-1px);',
    '  box-shadow: 0 12px 30px rgba(19, 34, 53, 0.14);',
    '}',
    '',
    '.button--primary {',
    '  color: white;',
    '  background: linear-gradient(135deg, var(--accent), var(--accent-strong));',
    '}',
    '',
    '.button--secondary {',
    '  color: var(--ink);',
    '  background: rgba(255, 255, 255, 0.72);',
    '  border-color: var(--line);',
    '}',
    '',
    '.stat-grid, .card-grid, .mini-grid {',
    '  display: grid;',
    '  gap: 18px;',
    '  grid-template-columns: repeat(3, minmax(0, 1fr));',
    '}',
    '',
    '.trust-strip {',
    '  display: flex;',
    '  flex-wrap: wrap;',
    '  gap: 12px;',
    '}',
    '',
    '.trust-pill {',
    '  display: inline-flex;',
    '  align-items: center;',
    '  min-height: 40px;',
    '  padding: 0 14px;',
    '  border-radius: 999px;',
    '  border: 1px solid var(--line);',
    '  background: rgba(255, 255, 255, 0.72);',
    '  color: var(--muted);',
    '  font-weight: 600;',
    '}',
    '',
    '.stat {',
    '  padding: 18px;',
    '  border-radius: var(--radius-lg);',
    '  background: rgba(255, 255, 255, 0.76);',
    '  border: 1px solid var(--line);',
    '}',
    '',
    '.stat-value {',
    '  display: block;',
    '  margin-top: 8px;',
    '  font-family: var(--font-display);',
    '  font-size: 1.8rem;',
    '}',
    '',
    '.section-header {',
    '  display: flex;',
    '  justify-content: space-between;',
    '  gap: 16px;',
    '  align-items: end;',
    '  margin-bottom: 18px;',
    '}',
    '',
    '.section h2, .card h3, .shell-title {',
    '  margin: 0;',
    '  font-family: var(--font-display);',
    '}',
    '',
    '.panel {',
    '  min-height: 100%;',
    '}',
    '',
    '.faq-list {',
    '  display: grid;',
    '  gap: 18px;',
    '}',
    '',
    '.faq-item h3 {',
    '  margin: 0 0 8px;',
    '  font-family: var(--font-display);',
    '}',
    '',
    '.cta-banner {',
    '  background: linear-gradient(135deg, rgba(180, 80, 46, 0.14), rgba(13, 104, 115, 0.12)), var(--surface);',
    '}',
    '',
    '.list-reset {',
    '  list-style: none;',
    '  padding: 0;',
    '  margin: 0;',
    '}',
    '',
    '.table {',
    '  width: 100%;',
    '  border-collapse: collapse;',
    '}',
    '',
    '.table th, .table td {',
    '  text-align: left;',
    '  padding: 12px 0;',
    '  border-bottom: 1px solid var(--line);',
    '}',
    '',
    '.severity {',
    '  display: inline-flex;',
    '  align-items: center;',
    '  border-radius: 999px;',
    '  padding: 6px 10px;',
    '  font-size: 0.8rem;',
    '  font-weight: 600;',
    '  background: rgba(255, 255, 255, 0.7);',
    '  border: 1px solid var(--line);',
    '}',
    '',
    '.severity--high { color: #8d2a20; }',
    '.severity--medium { color: #9b6317; }',
    '.severity--low { color: #1e6a52; }',
    '',
    '.shell-grid {',
    '  display: grid;',
    '  min-height: 100vh;',
    '  grid-template-columns: minmax(260px, 300px) minmax(0, 1fr);',
    '}',
    '',
    '.shell-sidebar {',
    '  position: sticky;',
    '  top: 0;',
    '  align-self: start;',
    '  min-height: 100vh;',
    '  padding: 32px 24px;',
    '  border-right: 1px solid var(--line);',
    '  background: rgba(255, 255, 255, 0.52);',
    '  backdrop-filter: blur(18px);',
    '}',
    '',
    '.shell-nav a {',
    '  padding: 10px 12px;',
    '  border-radius: 14px;',
    '  background: rgba(255, 255, 255, 0.52);',
    '  border: 1px solid transparent;',
    '}',
    '',
    '.shell-nav a:hover {',
    '  border-color: var(--line);',
    '}',
    '',
    '.shell-panel {',
    '  padding: 36px 28px 72px;',
    '}',
    '',
    '.form-grid {',
    '  display: grid;',
    '  gap: 14px;',
    '}',
    '',
    '.input, .textarea {',
    '  width: 100%;',
    '  border: 1px solid var(--line);',
    '  border-radius: 16px;',
    '  padding: 14px 16px;',
    '  background: rgba(255, 255, 255, 0.86);',
    '  color: var(--ink);',
    '  font: inherit;',
    '}',
    '',
    '.textarea {',
    '  min-height: 140px;',
    '  resize: vertical;',
    '}',
    '',
    '@media (max-width: 960px) {',
    '  .hero, .shell-grid {',
    '    grid-template-columns: 1fr;',
    '  }',
    '',
    '  .stat-grid, .card-grid, .mini-grid {',
    '    grid-template-columns: 1fr;',
    '  }',
    '',
    '  .shell-sidebar {',
    '    position: static;',
    '    min-height: auto;',
    '    border-right: none;',
    '    border-bottom: 1px solid var(--line);',
    '  }',
    '',
    '  .topbar, .section-header {',
    '    flex-direction: column;',
    '    align-items: flex-start;',
    '  }',
    '}'
  ].join('\n');
}

function renderHealthRoute(): string {
  return [
    'export async function GET() {',
    '  return Response.json({',
    "    ok: true,",
    "    service: 'generated-product-bundle'",
    '  });',
    '}'
  ].join('\n');
}

function renderMarketingHomePage(): string {
  return [
    "import { Button } from '../components/ui/button';",
    "import { Panel } from '../components/ui/panel';",
    "import { siteContent } from '../lib/site';",
    '',
    'export default function HomePage() {',
    '  return (',
    '    <main className="page">',
    '      <header className="topbar">',
    '        <div className="brand">',
    '          <div className="brand-mark">{siteContent.siteConfig.name}</div>',
    '          <div className="eyebrow">{siteContent.siteConfig.eyebrow}</div>',
    '        </div>',
    '        <nav className="nav-inline">',
    '          {siteContent.navItems.map((item) => (',
    '            <a key={item.href} href={item.href}>{item.label}</a>',
    '          ))}',
    '        </nav>',
    '      </header>',
    '',
    '      <section className="hero">',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">{siteContent.siteConfig.eyebrow}</div>',
    '          <h1 className="display">{siteContent.siteConfig.headline}</h1>',
    '          <p className="lede">{siteContent.siteConfig.description}</p>',
    '          <div className="button-row">',
    '            <Button href={siteContent.finalCta.primaryHref}>{siteContent.finalCta.primaryLabel}</Button>',
    '            <Button href={siteContent.finalCta.secondaryHref} variant="secondary">{siteContent.finalCta.secondaryLabel}</Button>',
    '          </div>',
    '        </article>',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">Proof points</div>',
    '          <div className="stat-grid">',
    '            {siteContent.proofPoints.map((item) => (',
    '              <div className="stat" key={item.label}>',
    '                <span>{item.label}</span>',
    '                <strong className="stat-value">{item.value}</strong>',
    '              </div>',
    '            ))}',
    '          </div>',
    '        </article>',
    '      </section>',
    '',
    '      <section className="section">',
    '        <div className="eyebrow">Trusted by the teams who own operating leverage</div>',
    '        <div className="trust-strip">',
    '          {siteContent.trustBadges.map((item) => (',
    '            <span className="trust-pill" key={item}>{item}</span>',
    '          ))}',
    '        </div>',
    '      </section>',
    '',
    '      <section className="section">',
    '        <div className="section-header">',
    '          <div>',
    '            <div className="eyebrow">Platform story</div>',
    '            <h2>Built to make complex operations feel governable</h2>',
    '          </div>',
    '          <p className="muted">The first pass should explain the product in buyer language instead of exposing internal harness mechanics.</p>',
    '        </div>',
    '        <div className="card-grid">',
    '          {siteContent.featureHighlights.map((item) => (',
    '            <Panel key={item.title} title={item.title}>',
    '              <p className="muted">{item.body}</p>',
    '            </Panel>',
    '          ))}',
    '        </div>',
    '      </section>',
    '',
    '      <section className="section" id="use-cases">',
    '        <div className="section-header">',
    '          <div>',
    '            <div className="eyebrow">Use cases</div>',
    '            <h2>Where teams feel the value first</h2>',
    '          </div>',
    '          <p className="muted">Each use case shows how SignalForge can replace fragmented handoffs with a governed operating layer.</p>',
    '        </div>',
    '        <div className="card-grid">',
    '          {siteContent.useCaseCards.map((item) => (',
    '            <Panel key={item.title} title={item.title}>',
    '              <p className="muted">{item.body}</p>',
    '            </Panel>',
    '          ))}',
    '        </div>',
    '      </section>',
    '',
    '      <section className="section">',
    '        <div className="section-header">',
    '          <div>',
    '            <div className="eyebrow">Case studies</div>',
    '            <h2>Example operating wins</h2>',
    '          </div>',
    '        </div>',
    '        <div className="card-grid">',
    '          {siteContent.caseStudies.map((item) => (',
    '            <Panel key={item.company} title={item.company} eyebrow={item.outcome}>',
    '              <p className="muted">{item.detail}</p>',
    '            </Panel>',
    '          ))}',
    '        </div>',
    '      </section>',
    '',
    '      <section className="section">',
    '        <div className="section-header">',
    '          <div>',
    '            <div className="eyebrow">Frequently asked questions</div>',
    '            <h2>What buyers want answered before the first demo</h2>',
    '          </div>',
    '        </div>',
    '        <div className="faq-list">',
    '          {siteContent.faqItems.map((item) => (',
    '            <article className="card faq-item" key={item.question}>',
    '              <h3>{item.question}</h3>',
    '              <p className="muted">{item.answer}</p>',
    '            </article>',
    '          ))}',
    '        </div>',
    '      </section>',
    '',
    '      <section className="section">',
    '        <article className="hero-card stack cta-banner">',
    '          <div className="eyebrow">{siteContent.finalCta.eyebrow}</div>',
    '          <h2>{siteContent.finalCta.headline}</h2>',
    '          <p className="lede">{siteContent.finalCta.body}</p>',
    '          <div className="button-row">',
    '            <Button href={siteContent.finalCta.primaryHref}>{siteContent.finalCta.primaryLabel}</Button>',
    '            <Button href={siteContent.finalCta.secondaryHref} variant="secondary">{siteContent.finalCta.secondaryLabel}</Button>',
    '          </div>',
    '        </article>',
    '      </section>',
    '    </main>',
    '  );',
    '}'
  ].join('\n');
}

function renderPricingPage(): string {
  return [
    "import { Button } from '../../components/ui/button';",
    "import { Panel } from '../../components/ui/panel';",
    "import { siteContent } from '../../lib/site';",
    '',
    'export default function PricingPage() {',
    '  return (',
    '    <main className="page">',
    '      <section className="section">',
    '        <div className="section-header">',
    '          <div>',
    '            <div className="eyebrow">Commercial framing</div>',
    '            <h1 className="display">Pricing that matches rollout scope and governance depth</h1>',
    '          </div>',
    '          <Button href="/" variant="secondary">Back to overview</Button>',
    '        </div>',
    '        <p className="lede">Use pricing to frame implementation maturity, ownership, and cross-system depth without forcing the landing page to behave like a checkout flow.</p>',
    '        <div className="card-grid">',
    '          {siteContent.pricingTiers.map((tier) => (',
    '            <Panel key={tier.name} title={tier.name} eyebrow={tier.price}>',
    '              <p className="muted">{tier.summary}</p>',
    '              <ul className="list-reset">',
    '                {tier.features.map((feature) => (',
    '                  <li key={feature}>{feature}</li>',
    '                ))}',
    '              </ul>',
    '            </Panel>',
    '          ))}',
    '        </div>',
    '      </section>',
    '    </main>',
    '  );',
    '}'
  ].join('\n');
}

function renderContactPage(): string {
  return [
    "import { siteContent } from '../../lib/site';",
    '',
    'export default function ContactPage() {',
    '  return (',
    '    <main className="page">',
    '      <section className="hero">',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">Handoff intake</div>',
    '          <h1 className="display">Turn interest into a qualified demo conversation</h1>',
    '          <p className="lede">Use this capture surface to collect the buyer context, systems in scope, and rollout constraints that matter for a real enterprise demo.</p>',
    '          <div className="form-grid">',
    '            <input className="input" placeholder="Your team or company" />',
    '            <input className="input" placeholder="Primary outcome" />',
    '            <textarea className="textarea" placeholder="Describe the launch timeline, integrations, and constraints." />',
    '          </div>',
    '        </article>',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">Response channels</div>',
    '          <div className="stack">',
    '            {siteContent.contactChannels.map((item) => (',
    '              <div key={item.label}>',
    '                <strong>{item.label}</strong>',
    '                <p className="muted">{item.detail}</p>',
    '              </div>',
    '            ))}',
    '          </div>',
    '        </article>',
    '      </section>',
    '    </main>',
    '  );',
    '}'
  ].join('\n');
}

function renderIntroPage(entryHref: string, entryLabel: string): string {
  return [
    "import { Button } from '../components/ui/button';",
    "import { Panel } from '../components/ui/panel';",
    "import { siteContent } from '../lib/site';",
    '',
    'export default function HomePage() {',
    '  return (',
    '    <main className="page">',
    '      <header className="topbar">',
    '        <div className="brand">',
    '          <div className="brand-mark">{siteContent.siteConfig.name}</div>',
    '          <div className="eyebrow">{siteContent.siteConfig.eyebrow}</div>',
    '        </div>',
    '        <nav className="nav-inline">',
    '          {siteContent.navItems.map((item) => (',
    '            <a key={item.href} href={item.href}>{item.label}</a>',
    '          ))}',
    '        </nav>',
    '      </header>',
    '',
    '      <section className="hero">',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">Bundle overview</div>',
    '          <h1 className="display">{siteContent.siteConfig.headline}</h1>',
    '          <p className="lede">{siteContent.siteConfig.description}</p>',
    '          <div className="button-row">',
    `            <Button href="${entryHref}">${entryLabel}</Button>`,
    '            <Button href="/sign-in" variant="secondary">Review sign-in stub</Button>',
    '          </div>',
    '        </article>',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">Core metrics</div>',
    '          <div className="stat-grid">',
    '            {siteContent.heroStats.map((item) => (',
    '              <div className="stat" key={item.label}>',
    '                <span>{item.label}</span>',
    '                <strong className="stat-value">{item.value}</strong>',
    '              </div>',
    '            ))}',
    '          </div>',
    '        </article>',
    '      </section>',
    '',
    '      <section className="section">',
    '        <div className="section-header">',
    '          <div>',
    '            <div className="eyebrow">Generated modules</div>',
    '            <h2>Operational areas already modeled in the starter</h2>',
    '          </div>',
    '        </div>',
    '        <div className="card-grid">',
    '          {siteContent.dashboardModules.map((item) => (',
    '            <Panel key={item.title} title={item.title}>',
    '              <p className="muted">{item.body}</p>',
    '            </Panel>',
    '          ))}',
    '        </div>',
    '      </section>',
    '    </main>',
    '  );',
    '}'
  ].join('\n');
}

function renderDashboardLayout(sectionTitle: string): string {
  return [
    "import type { ReactNode } from 'react';",
    "import { AppShell } from '../../components/ui/app-shell';",
    "import { siteContent } from '../../lib/site';",
    '',
    'export default function DashboardLayout({ children }: { children: ReactNode }) {',
    '  return (',
    '    <AppShell',
    '      title={siteContent.siteConfig.name}',
    '      summary={siteContent.siteConfig.description}',
    '      navItems={siteContent.navItems}',
    `      asideTitle="${sectionTitle}"`,
    '      asideItems={siteContent.contract.acceptanceCriteria.slice(0, 4)}',
    '    >',
    '      {children}',
    '    </AppShell>',
    '  );',
    '}'
  ].join('\n');
}

function renderDashboardPage(): string {
  return [
    "import { Panel } from '../../components/ui/panel';",
    "import { siteContent } from '../../lib/site';",
    '',
    'export default function DashboardPage() {',
    '  return (',
    '    <section className="stack">',
    '      <div className="section-header">',
    '        <div>',
    '          <div className="eyebrow">Command overview</div>',
    '          <h2>Primary dashboard</h2>',
    '        </div>',
    '      </div>',
    '      <div className="stat-grid">',
    '        {siteContent.dashboardStats.map((item) => (',
    '          <div className="stat" key={item.label}>',
    '            <span>{item.label}</span>',
    '            <strong className="stat-value">{item.value}</strong>',
    '            <div className="muted">{item.trend}</div>',
    '          </div>',
    '        ))}',
    '      </div>',
    '      <div className="card-grid">',
    '        {siteContent.dashboardModules.map((item) => (',
    '          <Panel key={item.title} title={item.title}>',
    '            <p className="muted">{item.body}</p>',
    '          </Panel>',
    '        ))}',
    '      </div>',
    '    </section>',
    '  );',
    '}'
  ].join('\n');
}

function renderReportsPage(): string {
  return [
    "import { siteContent } from '../../../lib/site';",
    '',
    'export default function ReportsPage() {',
    '  return (',
    '    <section className="card stack">',
    '      <div className="eyebrow">Operational alerts</div>',
    '      <h2>Reports and exceptions</h2>',
    '      <table className="table">',
    '        <thead>',
    '          <tr>',
    '            <th>Alert</th>',
    '            <th>Detail</th>',
    '            <th>Severity</th>',
    '          </tr>',
    '        </thead>',
    '        <tbody>',
    '          {siteContent.dashboardAlerts.map((item) => (',
    '            <tr key={item.title}>',
    '              <td>{item.title}</td>',
    '              <td>{item.detail}</td>',
    '              <td><span className={`severity severity--${item.severity}`}>{item.severity}</span></td>',
    '            </tr>',
    '          ))}',
    '        </tbody>',
    '      </table>',
    '    </section>',
    '  );',
    '}'
  ].join('\n');
}

function renderSettingsPage(hasAuthPack: boolean, hasObservabilityPack: boolean): string {
  const lines: string[] = [];
  if (hasAuthPack) {
    lines.push("import { authConfig } from '../../../lib/auth';");
  }
  if (hasObservabilityPack) {
    lines.push("import { describeTelemetry } from '../../../lib/telemetry';");
  }
  lines.push("import { siteContent } from '../../../lib/site';");
  lines.push('');
  lines.push('export default function SettingsPage() {');
  lines.push('  return (');
  lines.push('    <section className="card stack">');
  lines.push('      <div className="eyebrow">Configuration</div>');
  lines.push('      <h2>Settings surface</h2>');
  lines.push('      <p className="muted">Use this page to wire the selected packs into real providers and policy controls.</p>');
  lines.push('      <ul className="list-reset">');
  if (hasAuthPack) {
    lines.push('        <li><strong>Auth provider:</strong> {authConfig.provider} ({authConfig.sessionStrategy})</li>');
  }
  if (hasObservabilityPack) {
    lines.push('        <li><strong>Telemetry:</strong> {describeTelemetry()}</li>');
  }
  lines.push('        {siteContent.contract.requiredIntegrations.map((item) => (');
  lines.push('          <li key={item}><strong>Integration:</strong> {item}</li>');
  lines.push('        ))}');
  lines.push('      </ul>');
  lines.push('    </section>');
  lines.push('  );');
  lines.push('}');
  return lines.join('\n');
}

function renderSignInPage(hasAuthPack: boolean): string {
  return [
    hasAuthPack ? "import { authConfig, demoRoles } from '../../lib/auth';" : '',
    '',
    'export default function SignInPage() {',
    '  return (',
    '    <main className="page">',
    '      <section className="hero">',
    '        <article className="hero-card stack">',
    '          <div className="eyebrow">Authentication stub</div>',
    '          <h1 className="display">Sign in to the generated shell</h1>',
    '          <div className="form-grid">',
    '            <input className="input" placeholder="Work email" />',
    '            <input className="input" placeholder="Password or SSO code" />',
    '          </div>',
    '        </article>',
    '        <article className="hero-card stack">',
    hasAuthPack ? '          <p className="muted">Provider: {authConfig.provider}</p>' : '          <p className="muted">Authentication pack was not selected for this bundle.</p>',
    hasAuthPack ? '          <p className="muted">Roles: {demoRoles.join(\', \')}</p>' : '',
    '        </article>',
    '      </section>',
    '    </main>',
    '  );',
    '}'
  ].filter(Boolean).join('\n');
}

function renderOpsHomePage(): string {
  return [
    "import { Panel } from '../../components/ui/panel';",
    "import { siteContent } from '../../lib/site';",
    '',
    'export default function OpsHomePage() {',
    '  return (',
    '    <section className="stack">',
    '      <div className="section-header">',
    '        <div>',
    '          <div className="eyebrow">Operator command</div>',
    '          <h2>Ops home</h2>',
    '        </div>',
    '      </div>',
    '      <div className="card-grid">',
    '        {siteContent.adminQueues.map((item) => (',
    '          <Panel key={item.name} title={item.name} eyebrow={item.owner}>',
    '            <p className="muted">{item.status}</p>',
    '          </Panel>',
    '        ))}',
    '      </div>',
    '    </section>',
    '  );',
    '}'
  ].join('\n');
}

function renderOperatorsPage(): string {
  return [
    "import { siteContent } from '../../../lib/site';",
    '',
    'export default function OperatorsPage() {',
    '  return (',
    '    <section className="card stack">',
    '      <div className="eyebrow">Operator coverage</div>',
    '      <h2>Shift roster</h2>',
    '      <table className="table">',
    '        <thead>',
    '          <tr>',
    '            <th>Name</th>',
    '            <th>Role</th>',
    '            <th>Shift</th>',
    '          </tr>',
    '        </thead>',
    '        <tbody>',
    '          {siteContent.adminOperators.map((item) => (',
    '            <tr key={item.name}>',
    '              <td>{item.name}</td>',
    '              <td>{item.role}</td>',
    '              <td>{item.shift}</td>',
    '            </tr>',
    '          ))}',
    '        </tbody>',
    '      </table>',
    '    </section>',
    '  );',
    '}'
  ].join('\n');
}

function renderIncidentsPage(): string {
  return [
    "import { siteContent } from '../../../lib/site';",
    '',
    'export default function IncidentsPage() {',
    '  return (',
    '    <section className="card stack">',
    '      <div className="eyebrow">Live work</div>',
    '      <h2>Incident queues</h2>',
    '      <ul className="list-reset">',
    '        {siteContent.dashboardAlerts.map((item) => (',
    '          <li key={item.title}>',
    '            <strong>{item.title}</strong> <span className={`severity severity--${item.severity}`}>{item.severity}</span>',
    '            <div className="muted">{item.detail}</div>',
    '          </li>',
    '        ))}',
    '      </ul>',
    '    </section>',
    '  );',
    '}'
  ].join('\n');
}

function renderAuditPage(): string {
  return [
    "import { siteContent } from '../../../lib/site';",
    '',
    'export default function AuditPage() {',
    '  return (',
    '    <section className="card stack">',
    '      <div className="eyebrow">Audit trail</div>',
    '      <h2>Recent administrative activity</h2>',
    '      <table className="table">',
    '        <thead>',
    '          <tr>',
    '            <th>Actor</th>',
    '            <th>Action</th>',
    '            <th>Timestamp</th>',
    '          </tr>',
    '        </thead>',
    '        <tbody>',
    '          {siteContent.auditEntries.map((item) => (',
    '            <tr key={`${item.actor}-${item.at}`}>',
    '              <td>{item.actor}</td>',
    '              <td>{item.action}</td>',
    '              <td>{item.at}</td>',
    '            </tr>',
    '          ))}',
    '        </tbody>',
    '      </table>',
    '    </section>',
    '  );',
    '}'
  ].join('\n');
}

function renderReadme(manifest: ProductBundleManifest, content: BundleContent): string {
  const lines = [
    `# ${content.siteConfig.name}`,
    '',
    `Generated by gg-agentic-harness on ${manifest.generatedAt}.`,
    '',
    '## What this bundle contains',
    '',
    `- Lane: ${humanizeToken(manifest.lane)}`,
    `- Target stack: ${manifest.targetStack}`,
    `- Delivery target: ${manifest.deliveryTarget.replace(/-/gu, ' ')}`,
    `- Selected packs: ${manifest.enterprisePacks.join(', ') || 'none'}`,
    '',
    '## Commands',
    '',
    `- Install: \`${manifest.commands.install}\``,
    `- Dev: \`${manifest.commands.dev}\``,
    `- Build: \`${manifest.commands.build}\``,
    `- Lint: \`${manifest.commands.lint}\``,
    `- Typecheck: \`${manifest.commands.typecheck}\``,
    '',
    '## Acceptance criteria',
    ...manifest.acceptanceCriteria.map((item) => `- ${item}`),
    '',
    '## Constraints',
    ...(manifest.constraints.length > 0 ? manifest.constraints.map((item) => `- ${item}`) : ['- None recorded.']),
    '',
    '## Required gates',
    ...manifest.requiredGates.map((item) => `- ${item}`),
    '',
    '## Required integrations',
    ...(manifest.requiredIntegrations.length > 0 ? manifest.requiredIntegrations.map((item) => `- ${item}`) : ['- None recorded.']),
    '',
    '## Notes',
    manifest.requiresHumanReview
      ? '- This bundle still requires human review before production merge because one or more packs or constraints carry review obligations.'
      : '- No extra human-review packs were detected in the generated contract.',
    ''
  ];

  return lines.join('\n');
}

function buildProductBundleTemplate(
  spec: CanonicalProductSpec,
  lane: ProductLaneDefinition,
  selectedPacks: ProductPackDefinition[]
): ProductBundleTemplate {
  if (!SUPPORTED_STACKS.has(spec.targetStack)) {
    throw new Error(`Product builder currently supports only: ${Array.from(SUPPORTED_STACKS).join(', ')}`);
  }

  if (!['marketing-site', 'saas-dashboard', 'admin-panel'].includes(lane.id)) {
    throw new Error(`Product builder does not yet support lane: ${lane.id}`);
  }

  const content = buildBundleContent(projectRoot, spec, lane, selectedPacks);
  const hasAuthPack = spec.enterprisePacks.includes('auth-rbac');
  const hasObservabilityPack = spec.enterprisePacks.includes('observability');
  const files: ProductBundleFile[] = [
    { path: '.env.example', kind: 'config' },
    { path: '.gitignore', kind: 'config' },
    { path: 'eslint.config.mjs', kind: 'config' },
    { path: 'gg-product-bundle.json', kind: 'config' },
    { path: 'next-env.d.ts', kind: 'config' },
    { path: 'next.config.ts', kind: 'config' },
    { path: 'package.json', kind: 'config' },
    { path: 'README.md', kind: 'doc' },
    { path: 'tsconfig.json', kind: 'config' },
    { path: 'src/app/api/health/route.ts', kind: 'code' },
    { path: 'src/app/globals.css', kind: 'code' },
    { path: 'src/app/layout.tsx', kind: 'code' },
    { path: 'src/components/ui/button.tsx', kind: 'code' },
    { path: 'src/components/ui/panel.tsx', kind: 'code' },
    { path: 'src/lib/site.ts', kind: 'code' }
  ];

  if (hasObservabilityPack) {
    files.push({ path: 'src/lib/telemetry.ts', kind: 'code' });
  }

  if (hasAuthPack) {
    files.push({ path: 'src/lib/auth.ts', kind: 'code' });
    files.push({ path: 'src/app/sign-in/page.tsx', kind: 'code' });
  }

  if (lane.id === 'marketing-site') {
    files.push({ path: 'src/app/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/pricing/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/contact/page.tsx', kind: 'code' });
  } else if (lane.id === 'saas-dashboard') {
    files.push({ path: 'src/app/page.tsx', kind: 'code' });
    files.push({ path: 'src/components/ui/app-shell.tsx', kind: 'code' });
    files.push({ path: 'src/app/dashboard/layout.tsx', kind: 'code' });
    files.push({ path: 'src/app/dashboard/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/dashboard/reports/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/dashboard/settings/page.tsx', kind: 'code' });
  } else if (lane.id === 'admin-panel') {
    files.push({ path: 'src/app/page.tsx', kind: 'code' });
    files.push({ path: 'src/components/ui/app-shell.tsx', kind: 'code' });
    files.push({ path: 'src/app/ops/layout.tsx', kind: 'code' });
    files.push({ path: 'src/app/ops/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/ops/operators/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/ops/incidents/page.tsx', kind: 'code' });
    files.push({ path: 'src/app/ops/audit/page.tsx', kind: 'code' });
  }

  return { files, content };
}

export function createProductBundle(options: ProductBundleOptions): ProductBundleResult {
  const { projectRoot, spec, lane, selectedPacks, bundleId, overwrite = false } = options;
  const bundleDir = options.outputDir
    ? path.resolve(projectRoot, options.outputDir)
    : path.join(projectRoot, '.agent', 'product-bundles', bundleId);
  ensureCleanDir(bundleDir, overwrite);

  const template = buildProductBundleTemplate(spec, lane, selectedPacks);
  const manifest: ProductBundleManifest = {
    schemaVersion: 1,
    bundleId,
    generatedAt: isoNow(),
    summary: spec.summary,
    lane: spec.lane,
    targetStack: spec.targetStack,
    deliveryTarget: spec.deliveryTarget,
    downstreamTarget: spec.downstreamTarget,
    enterprisePacks: spec.enterprisePacks,
    requiredIntegrations: spec.requiredIntegrations,
    requiredGates: uniqueStrings([...lane.requiredGates, ...selectedPacks.flatMap((pack) => pack.requiredGates)]),
    acceptanceCriteria: spec.acceptanceCriteria,
    constraints: spec.constraints,
    requiresHumanReview: spec.requiresHumanReview,
    files: template.files,
    commands: {
      install: 'npm install',
      dev: 'npm run dev',
      build: 'npm run build',
      lint: 'npm run lint',
      typecheck: 'npm run typecheck'
    }
  };

  writeTextFile(bundleDir, '.env.example', buildEnvExample(spec));
  writeTextFile(bundleDir, '.gitignore', ['node_modules', '.next', '.env.local', 'dist', 'tsconfig.tsbuildinfo'].join('\n'));
  writeTextFile(bundleDir, 'eslint.config.mjs', renderEslintConfig());
  writeTextFile(bundleDir, 'next-env.d.ts', ['/// <reference types="next" />', '/// <reference types="next/image-types/global" />', '', '// This file is auto-generated by Next.js and should not be edited.'].join('\n'));
  writeTextFile(bundleDir, 'next.config.ts', renderNextConfig());
  writeTextFile(bundleDir, 'package.json', renderPackageJson(spec, template.content));
  writeTextFile(bundleDir, 'README.md', renderReadme(manifest, template.content));
  writeTextFile(bundleDir, 'tsconfig.json', renderTsconfig());
  writeTextFile(bundleDir, 'gg-product-bundle.json', JSON.stringify(manifest, null, 2));
  writeTextFile(bundleDir, 'src/app/api/health/route.ts', renderHealthRoute());
  writeTextFile(bundleDir, 'src/app/globals.css', renderGlobalsCss());
  writeTextFile(bundleDir, 'src/app/layout.tsx', renderLayout());
  writeTextFile(bundleDir, 'src/components/ui/button.tsx', renderButtonComponent());
  writeTextFile(bundleDir, 'src/components/ui/panel.tsx', renderPanelComponent());
  writeTextFile(bundleDir, 'src/lib/site.ts', renderSiteModule(template.content, spec, lane, selectedPacks));

  if (spec.enterprisePacks.includes('observability')) {
    writeTextFile(bundleDir, 'src/lib/telemetry.ts', renderTelemetryModule(spec));
  }

  if (spec.enterprisePacks.includes('auth-rbac')) {
    writeTextFile(bundleDir, 'src/lib/auth.ts', renderAuthModule());
    writeTextFile(bundleDir, 'src/app/sign-in/page.tsx', renderSignInPage(true));
  }

  if (lane.id === 'marketing-site') {
    writeTextFile(bundleDir, 'src/app/page.tsx', renderMarketingHomePage());
    writeTextFile(bundleDir, 'src/app/pricing/page.tsx', renderPricingPage());
    writeTextFile(bundleDir, 'src/app/contact/page.tsx', renderContactPage());
  }

  if (lane.id === 'saas-dashboard') {
    writeTextFile(bundleDir, 'src/app/page.tsx', renderIntroPage('/dashboard', 'Open dashboard'));
    writeTextFile(bundleDir, 'src/components/ui/app-shell.tsx', renderAppShellComponent());
    writeTextFile(bundleDir, 'src/app/dashboard/layout.tsx', renderDashboardLayout('Delivery criteria'));
    writeTextFile(bundleDir, 'src/app/dashboard/page.tsx', renderDashboardPage());
    writeTextFile(bundleDir, 'src/app/dashboard/reports/page.tsx', renderReportsPage());
    writeTextFile(bundleDir, 'src/app/dashboard/settings/page.tsx', renderSettingsPage(spec.enterprisePacks.includes('auth-rbac'), spec.enterprisePacks.includes('observability')));
  }

  if (lane.id === 'admin-panel') {
    writeTextFile(bundleDir, 'src/app/page.tsx', renderIntroPage('/ops', 'Open ops home'));
    writeTextFile(bundleDir, 'src/components/ui/app-shell.tsx', renderAppShellComponent());
    writeTextFile(bundleDir, 'src/app/ops/layout.tsx', renderDashboardLayout('Operator checklist'));
    writeTextFile(bundleDir, 'src/app/ops/page.tsx', renderOpsHomePage());
    writeTextFile(bundleDir, 'src/app/ops/operators/page.tsx', renderOperatorsPage());
    writeTextFile(bundleDir, 'src/app/ops/incidents/page.tsx', renderIncidentsPage());
    writeTextFile(bundleDir, 'src/app/ops/audit/page.tsx', renderAuditPage());
  }

  return {
    bundleId,
    bundleDir,
    manifestPath: path.join(bundleDir, 'gg-product-bundle.json'),
    manifest,
    files: template.files
  };
}
