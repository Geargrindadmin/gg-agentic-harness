#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
export const REPO_ROOT = path.resolve(__dirname, '..');
export const REGISTRY_PATH = path.join(REPO_ROOT, '.agent', 'registry', 'persona-registry.json');
export const COMPOUND_REGISTRY_PATH = path.join(REPO_ROOT, '.agent', 'registry', 'persona-compounds.json');

const VALID_ROLES = new Set(['scout', 'planner', 'builder', 'reviewer', 'coordinator']);
const VALID_RISK_TIERS = new Set(['low', 'medium', 'high']);
const VALID_COMPOUND_SOURCES = new Set(['registry', 'runtime']);

export function loadRegistry(registryPath = REGISTRY_PATH) {
  const raw = fs.readFileSync(registryPath, 'utf8');
  const parsed = JSON.parse(raw);
  validateRegistry(parsed);
  return parsed;
}

export function loadCompoundRegistry(compoundPath = COMPOUND_REGISTRY_PATH, registry = loadRegistry()) {
  const raw = fs.readFileSync(compoundPath, 'utf8');
  const parsed = JSON.parse(raw);
  validateCompoundRegistry(parsed, registry);
  return parsed;
}

export function validateRegistry(registry) {
  if (!registry || typeof registry !== 'object') {
    throw new Error('Persona registry must be an object.');
  }
  if (!Array.isArray(registry.personas) || registry.personas.length === 0) {
    throw new Error('Persona registry must contain a non-empty personas array.');
  }

  const seen = new Set();
  for (const persona of registry.personas) {
    if (!persona.id || !persona.file) {
      throw new Error('Each persona must define id and file.');
    }
    if (seen.has(persona.id)) {
      throw new Error(`Duplicate persona id: ${persona.id}`);
    }
    seen.add(persona.id);
    if (!VALID_ROLES.has(persona.role)) {
      throw new Error(`Invalid persona role for ${persona.id}: ${persona.role}`);
    }
    for (const key of ['domains', 'selectionTriggers', 'defaultPartners', 'allowed', 'blocked']) {
      if (!Array.isArray(persona[key])) {
        throw new Error(`Persona ${persona.id} must define array field: ${key}`);
      }
    }
    if (typeof persona.memoryQuery !== 'string' || !persona.memoryQuery.trim()) {
      throw new Error(`Persona ${persona.id} must define memoryQuery.`);
    }
  }
}

export function validateCompoundRegistry(compoundRegistry, registry = loadRegistry()) {
  if (!compoundRegistry || typeof compoundRegistry !== 'object') {
    throw new Error('Compound persona registry must be an object.');
  }
  if (!Array.isArray(compoundRegistry.compounds) || compoundRegistry.compounds.length === 0) {
    throw new Error('Compound persona registry must contain a non-empty compounds array.');
  }

  const personaIndex = indexRegistry(registry);
  const seen = new Set();

  for (const compound of compoundRegistry.compounds) {
    if (!compound.id) {
      throw new Error('Each compound persona must define id.');
    }
    if (seen.has(compound.id)) {
      throw new Error(`Duplicate compound persona id: ${compound.id}`);
    }
    seen.add(compound.id);

    if (!VALID_COMPOUND_SOURCES.has(compound.source || 'registry')) {
      throw new Error(`Compound ${compound.id} has invalid source: ${compound.source}`);
    }
    if (!VALID_RISK_TIERS.has(compound.riskTier)) {
      throw new Error(`Compound ${compound.id} has invalid riskTier: ${compound.riskTier}`);
    }

    for (const key of [
      'classifications',
      'selectionTriggers',
      'memberPersonas',
      'collaboratorPersonas',
      'requiresAnyPersonaIds',
      'requiresAllPersonaIds',
      'requiresAnyHighRiskTerms',
      'notes'
    ]) {
      if (!Array.isArray(compound[key])) {
        throw new Error(`Compound ${compound.id} must define array field: ${key}`);
      }
    }

    if (!compound.primaryPersona || !personaIndex.has(compound.primaryPersona)) {
      throw new Error(`Compound ${compound.id} references missing primary persona: ${compound.primaryPersona}`);
    }

    for (const personaId of uniq([...compound.memberPersonas, ...compound.collaboratorPersonas])) {
      if (!personaIndex.has(personaId)) {
        throw new Error(`Compound ${compound.id} references unknown persona: ${personaId}`);
      }
    }

    for (const personaId of uniq([...compound.requiresAnyPersonaIds, ...compound.requiresAllPersonaIds])) {
      if (!personaIndex.has(personaId)) {
        throw new Error(`Compound ${compound.id} references unknown required persona: ${personaId}`);
      }
    }

    if (typeof compound.memoryQuery !== 'string' || !compound.memoryQuery.trim()) {
      throw new Error(`Compound ${compound.id} must define memoryQuery.`);
    }
    if (typeof compound.summary !== 'string' || !compound.summary.trim()) {
      throw new Error(`Compound ${compound.id} must define summary.`);
    }
    if (typeof compound.dispatchPlan !== 'string' || !compound.dispatchPlan.trim()) {
      throw new Error(`Compound ${compound.id} must define dispatchPlan.`);
    }
  }
}

export function indexRegistry(registry) {
  return new Map(registry.personas.map((persona) => [persona.id, persona]));
}

function indexCompoundRegistry(compoundRegistry) {
  return new Map(compoundRegistry.compounds.map((compound) => [compound.id, compound]));
}

function uniq(items) {
  return [...new Set(items.filter(Boolean))];
}

export function normalizeText(value = '') {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9@.+/\-\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function tokenize(value = '') {
  return uniq(normalizeText(value).split(' '));
}

const HIGH_RISK_TERMS = [
  'auth',
  'authentication',
  'login',
  'signup',
  'oauth',
  'passkey',
  'credential',
  'password',
  'token',
  'secret',
  'secrets',
  'payment',
  'payments',
  'checkout',
  'billing',
  'refund',
  'invoice',
  'escrow',
  'kyc',
  'production',
  'deploy',
  'rollback'
];

const REVIEW_TERMS = ['review', 'audit', 'validate', 'verification', 'check'];
const BUILD_TERMS = ['build', 'create', 'implement', 'feature', 'system', 'ship', 'refactor'];
const DEBUG_TERMS = ['bug', 'debug', 'broken', 'failing', 'error', 'fix', 'incident', 'outage'];

function containsPhrase(text, phrase) {
  return text.includes(normalizeText(phrase));
}

function triggerScore(text, tokens, trigger) {
  const normalizedTrigger = normalizeText(trigger);
  if (!normalizedTrigger) return 0;
  const boundedText = ` ${text} `;
  if (normalizedTrigger.includes(' ') && boundedText.includes(` ${normalizedTrigger} `)) return 7;
  if (tokens.includes(normalizedTrigger)) return 4;
  if (boundedText.includes(` ${normalizedTrigger} `)) return 2;
  return 0;
}

function detectHighRisk(text, tokens) {
  return uniq(HIGH_RISK_TERMS.filter((term) => triggerScore(text, tokens, term) > 0));
}

function isReviewRequest(text, tokens) {
  return REVIEW_TERMS.some((term) => triggerScore(text, tokens, term) > 0);
}

function isBuildRequest(text, tokens) {
  return BUILD_TERMS.some((term) => triggerScore(text, tokens, term) > 0);
}

function isDebugRequest(text, tokens) {
  return DEBUG_TERMS.some((term) => triggerScore(text, tokens, term) > 0);
}

function scorePersona(persona, text, tokens, classification) {
  let score = 0;
  const reasons = [];
  let hasDirectMatch = false;

  if (containsPhrase(text, `@${persona.id}`)) {
    score += 100;
    reasons.push(`explicit @${persona.id}`);
    hasDirectMatch = true;
  }

  for (const trigger of persona.selectionTriggers) {
    const inc = triggerScore(text, tokens, trigger);
    if (inc > 0) {
      score += inc;
      reasons.push(`trigger:${trigger}`);
      hasDirectMatch = true;
    }
  }

  for (const domain of persona.domains) {
    const inc = triggerScore(text, tokens, domain.replace(/-/g, ' '));
    if (inc > 0) {
      score += Math.max(1, inc - 1);
      reasons.push(`domain:${domain}`);
      hasDirectMatch = true;
    }
  }

  if (classification === 'DECISION' && persona.role === 'planner') {
    score += 3;
    reasons.push('decision/planner bias');
  }
  if (classification === 'CRITICAL' && persona.role === 'coordinator') {
    score += 5;
    reasons.push('critical/coordinator bias');
  }
  if (isReviewRequest(text, tokens) && persona.role === 'reviewer') {
    score += 3;
    reasons.push('review bias');
  }
  if (isBuildRequest(text, tokens) && persona.role === 'builder') {
    score += 2;
    reasons.push('build bias');
  }
  if (isDebugRequest(text, tokens) && persona.id === 'debugger') {
    score += 6;
    reasons.push('debugger bias');
  }

  return { score, reasons: uniq(reasons), hasDirectMatch };
}

function confidenceFromScore(score) {
  if (score >= 18) return 'high';
  if (score >= 8) return 'medium';
  if (score > 0) return 'low';
  return 'none';
}

function deriveRiskTier(personas, highRiskTerms) {
  if (highRiskTerms.length > 0 || personas.some((persona) => persona.riskTier === 'high')) return 'high';
  if (personas.some((persona) => persona.riskTier === 'medium')) return 'medium';
  return 'low';
}

function scoreCompound(compound, context) {
  const {
    classification,
    text,
    tokens,
    memberIds,
    highRiskTerms,
    dispatchPlan,
    boardRequired
  } = context;

  if (!compound.classifications.includes(classification)) {
    return { score: 0, reasons: [] };
  }

  let score = 2;
  const reasons = [`classification:${classification}`];
  const matchedTriggers = [];

  for (const trigger of compound.selectionTriggers) {
    const inc = triggerScore(text, tokens, trigger);
    if (inc > 0) {
      score += inc;
      matchedTriggers.push(trigger);
      reasons.push(`trigger:${trigger}`);
    }
  }

  const matchedMembers = compound.memberPersonas.filter((personaId) => memberIds.has(personaId));
  if (matchedMembers.length > 0) {
    score += matchedMembers.length * 3;
    reasons.push(`members:${matchedMembers.join(',')}`);
  }

  const matchedAny = compound.requiresAnyPersonaIds.filter((personaId) => memberIds.has(personaId));
  if (matchedAny.length > 0) {
    score += 4;
    reasons.push(`requiresAnyPersonaIds:${matchedAny.join(',')}`);
  }

  if (
    compound.requiresAllPersonaIds.length > 0 &&
    compound.requiresAllPersonaIds.every((personaId) => memberIds.has(personaId))
  ) {
    score += 6;
    reasons.push(`requiresAllPersonaIds:${compound.requiresAllPersonaIds.join(',')}`);
  }

  const matchedRiskTerms = compound.requiresAnyHighRiskTerms.filter((term) => highRiskTerms.includes(term));
  const hasDomainEvidence = matchedTriggers.length > 0 || matchedRiskTerms.length > 0;
  if (!hasDomainEvidence) {
    return { score: 0, reasons: [] };
  }
  if (matchedRiskTerms.length > 0) {
    score += matchedRiskTerms.length * 2 + 2;
    reasons.push(`highRiskTerms:${matchedRiskTerms.join(',')}`);
  }

  if (dispatchPlan === compound.dispatchPlan) {
    score += 2;
    reasons.push('dispatch-plan alignment');
  }

  if (boardRequired && compound.riskTier === 'high') {
    score += 2;
    reasons.push('board/high-risk alignment');
  }

  return { score, reasons: uniq(reasons) };
}

function buildRuntimeCompoundSignature({ memberPersonaIds, classification, riskTier, highRiskTerms, dispatchPlan }) {
  return [
    memberPersonaIds.slice().sort().join(','),
    classification,
    riskTier,
    dispatchPlan,
    highRiskTerms.slice().sort().join(',')
  ].join('|');
}

function createRuntimeCompoundId(signature) {
  const hash = crypto.createHash('sha1').update(signature).digest('hex').slice(0, 10);
  return `compound:runtime:${hash}:v1`;
}

function combineMemoryQueries(personas, fallbackQuery) {
  const words = uniq(
    personas
      .flatMap((persona) => tokenize(persona.memoryQuery))
      .concat(tokenize(fallbackQuery))
  ).slice(0, 18);
  return words.join(' ');
}

function summarizeCompound(compound) {
  if (!compound) return null;
  return {
    id: compound.id,
    source: compound.source,
    riskTier: compound.riskTier,
    dispatchPlan: compound.dispatchPlan,
    primaryPersonaId: compound.primaryPersonaId,
    collaboratorPersonaIds: compound.collaboratorPersonaIds,
    memberPersonaIds: compound.memberPersonaIds,
    memoryQuery: compound.memoryQuery,
    summary: compound.summary,
    reasons: compound.reasons,
    score: compound.score,
    promoteSuggested: Boolean(compound.promoteSuggested),
    signature: compound.signature || ''
  };
}

function resolveCompoundPersona(context) {
  const {
    registryIndex,
    compoundRegistry,
    classification,
    primaryPersona,
    collaboratorPersonas,
    matchedPersonas,
    highRiskTerms,
    boardRequired,
    dispatchPlan,
    text,
    tokens
  } = context;

  const memberPersonas = uniq([primaryPersona, ...collaboratorPersonas]);
  const memberPersonaIds = uniq(memberPersonas.map((persona) => persona.id));
  const memberIds = new Set(memberPersonaIds);
  const compoundIndex = indexCompoundRegistry(compoundRegistry);

  const registryMatches = compoundRegistry.compounds
    .map((compound) => {
      const result = scoreCompound(compound, {
        classification,
        text,
        tokens,
        memberIds,
        highRiskTerms,
        dispatchPlan,
        boardRequired
      });
      return { compound, score: result.score, reasons: result.reasons };
    })
    .filter((entry) => entry.score >= 10)
    .sort((a, b) => b.score - a.score || a.compound.id.localeCompare(b.compound.id));

  if (registryMatches.length > 0) {
    const top = registryMatches[0];
    const compound = compoundIndex.get(top.compound.id);
    return summarizeCompound({
      id: compound.id,
      source: compound.source || 'registry',
      riskTier: compound.riskTier,
      dispatchPlan: compound.dispatchPlan,
      primaryPersonaId: compound.primaryPersona,
      collaboratorPersonaIds: uniq(compound.collaboratorPersonas).filter(
        (personaId) => personaId !== compound.primaryPersona
      ),
      memberPersonaIds: uniq([compound.primaryPersona, ...compound.memberPersonas]),
      memoryQuery: compound.memoryQuery,
      summary: compound.summary,
      reasons: uniq(top.reasons.concat(compound.notes.map((note) => `note:${note}`))),
      score: top.score,
      promoteSuggested: false
    });
  }

  const specialistMemberIds = memberPersonaIds.filter((personaId) => personaId !== 'orchestrator');
  const shouldCreateRuntimeCompound =
    specialistMemberIds.length >= 2 &&
    (matchedPersonas.length > 1 || boardRequired || highRiskTerms.length > 0);

  if (!shouldCreateRuntimeCompound) return null;

  const riskTier = deriveRiskTier(memberPersonas, highRiskTerms);
  const signature = buildRuntimeCompoundSignature({
    memberPersonaIds,
    classification,
    riskTier,
    highRiskTerms,
    dispatchPlan
  });

  return summarizeCompound({
    id: createRuntimeCompoundId(signature),
    source: 'runtime',
    riskTier,
    dispatchPlan,
    primaryPersonaId: primaryPersona.id,
    collaboratorPersonaIds: collaboratorPersonas.map((persona) => persona.id),
    memberPersonaIds,
    memoryQuery: combineMemoryQueries(memberPersonas, matchedPersonas[0]?.memoryQuery || ''),
    summary: `Runtime compound derived from ${memberPersonaIds.join(', ')} for ${classification.toLowerCase()} routing.`,
    reasons: uniq([
      `runtime-members:${memberPersonaIds.join(',')}`,
      matchedPersonas.length > 1 ? 'multi-persona match' : '',
      boardRequired ? 'board-required' : '',
      highRiskTerms.length > 0 ? `highRiskTerms:${highRiskTerms.join(',')}` : ''
    ]),
    score: 0,
    promoteSuggested: boardRequired || specialistMemberIds.length >= 3,
    signature
  });
}

export function resolvePrompt(prompt, options = {}) {
  const registry = options.registry ?? loadRegistry();
  const compoundRegistry = options.compoundRegistry ?? loadCompoundRegistry(COMPOUND_REGISTRY_PATH, registry);
  const classification = String(options.classification || 'TASK').toUpperCase();
  const text = normalizeText(prompt);
  const tokens = tokenize(prompt);
  const highRiskTerms = detectHighRisk(text, tokens);
  const explicit = registry.personas.filter((persona) => containsPhrase(text, `@${persona.id}`));
  const scored = registry.personas
    .map((persona) => {
      const result = scorePersona(persona, text, tokens, classification);
      return { ...persona, score: result.score, reasons: result.reasons, hasDirectMatch: result.hasDirectMatch };
    })
    .filter((persona) => persona.score > 0 && (persona.hasDirectMatch || persona.id === 'orchestrator'))
    .sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));

  const matched = explicit.length ? explicit.map((persona) => ({ ...persona, score: 100, reasons: ['explicit mention'] })) : scored;
  const domainSet = uniq(matched.flatMap((persona) => persona.domains));
  const multiDomain = matched.length > 1 || domainSet.length > 2;
  const boardRequired =
    matched.some((persona) => persona.requiresBoardFor.some((term) => highRiskTerms.includes(term))) ||
    highRiskTerms.length > 0;
  const registryIndex = indexRegistry(registry);

  let primary = matched[0] ?? registryIndex.get('orchestrator');
  let collaborators = matched.slice(1, 4);

  if (!primary) {
    throw new Error('Persona registry is missing orchestrator fallback.');
  }

  const shouldUseCoordinator =
    primary.id !== 'orchestrator' &&
    (multiDomain || classification === 'DECISION' || classification === 'CRITICAL' || boardRequired || isBuildRequest(text, tokens));

  if (shouldUseCoordinator) {
    const orchestrator = registryIndex.get('orchestrator');
    if (orchestrator) {
      collaborators = uniq([
        primary,
        ...collaborators,
        ...orchestrator.defaultPartners.map((id) => registryIndex.get(id)).filter(Boolean)
      ])
        .filter((persona) => persona.id !== orchestrator.id)
        .slice(0, 4);
      primary = orchestrator;
    }
  }

  if (boardRequired) {
    const security = registryIndex.get('security-auditor');
    if (security && primary.id !== security.id && !collaborators.some((persona) => persona.id === security.id)) {
      collaborators = [...collaborators, security].slice(0, 4);
    }
  }

  if (matched.length === 0) {
    const explorer = registryIndex.get('explorer-agent');
    const planner = registryIndex.get('project-planner');
    collaborators = uniq([explorer, planner].filter(Boolean)).slice(0, 2);
  }

  const baseDispatchPlan = shouldUseCoordinator
    ? 'coordinator-plus-specialists'
    : collaborators.length > 0
      ? 'specialist-team'
      : 'single-specialist';
  const compoundPersona = resolveCompoundPersona({
    registryIndex,
    compoundRegistry,
    classification,
    primaryPersona: primary,
    collaboratorPersonas: collaborators,
    matchedPersonas: matched,
    highRiskTerms,
    boardRequired,
    dispatchPlan: baseDispatchPlan,
    text,
    tokens
  });

  const effectivePrimary = compoundPersona ? registryIndex.get(compoundPersona.primaryPersonaId) ?? primary : primary;
  const effectiveCollaborators = compoundPersona
    ? uniq(compoundPersona.collaboratorPersonaIds.map((personaId) => registryIndex.get(personaId)).filter(Boolean))
        .filter((persona) => persona.id !== effectivePrimary.id)
        .slice(0, 4)
    : collaborators;

  const confidence = matched.length === 0 ? 'none' : confidenceFromScore(matched[0].score);
  const createPersonaSuggested = matched.length === 0;
  const promoteCompoundSuggested = Boolean(compoundPersona?.source === 'runtime' && compoundPersona.promoteSuggested);

  return {
    prompt,
    classification,
    confidence,
    boardRequired,
    highRiskTerms,
    createPersonaSuggested,
    promoteCompoundSuggested,
    dispatchPlan: compoundPersona?.dispatchPlan ?? baseDispatchPlan,
    primaryPersona: summarizePersona(effectivePrimary),
    collaboratorPersonas: effectiveCollaborators.map(summarizePersona),
    matchedPersonas: matched.slice(0, 6).map(summarizePersona),
    compoundPersona,
    notes: buildNotes({
    matched,
      shouldUseCoordinator: compoundPersona
        ? compoundPersona.dispatchPlan === 'coordinator-plus-specialists'
        : shouldUseCoordinator,
      createPersonaSuggested,
      boardRequired,
      highRiskTerms,
      compoundPersona,
      promoteCompoundSuggested
    })
  };
}

function summarizePersona(persona) {
  return {
    id: persona.id,
    role: persona.role,
    file: persona.file,
    dispatchMode: persona.dispatchMode,
    riskTier: persona.riskTier,
    memoryQuery: persona.memoryQuery,
    defaultPartners: persona.defaultPartners,
    reasons: persona.reasons ?? [],
    score: persona.score ?? null
  };
}

function buildNotes({
  matched,
  shouldUseCoordinator,
  createPersonaSuggested,
  boardRequired,
  highRiskTerms,
  compoundPersona,
  promoteCompoundSuggested
}) {
  const notes = [];
  if (matched.length === 0) {
    notes.push('No strong persona match found; fall back to orchestrator discovery and consider registering a new persona.');
  }
  if (shouldUseCoordinator) {
    notes.push('Task spans multiple domains or governance-sensitive paths, so the orchestrator should coordinate sub-agents.');
  }
  if (boardRequired) {
    notes.push(`Board review required because high-risk terms were detected: ${highRiskTerms.join(', ')}.`);
  }
  if (compoundPersona) {
    notes.push(`Compound persona selected: ${compoundPersona.id} (${compoundPersona.source}).`);
  }
  if (promoteCompoundSuggested) {
    notes.push('Runtime compound is recurring-candidate material; promote it into persona-compounds.json if this routing pattern repeats.');
  }
  if (createPersonaSuggested) {
    notes.push('Persona coverage is low-confidence; run the persona-creation fallback from persona-dispatch governance before expanding automation.');
  }
  return notes;
}
