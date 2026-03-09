#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
  console.error(
    'Usage: node scripts/agent-run-artifact.mjs <init|gate|mcp|event|feedback|persona|context|complete> [--key value ...]'
  );
  process.exit(2);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function requireArg(args, key) {
  if (!args[key]) {
    console.error(`Missing required argument --${key}`);
    usage();
  }
  return args[key];
}

function optionalArg(args, key, fallback = '') {
  if (args[key] !== undefined) return args[key];
  const camelKey = key.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
  if (args[camelKey] !== undefined) return args[camelKey];
  return fallback;
}

function nowIso() {
  return new Date().toISOString();
}

function parseIntegrationFlags(value) {
  const flags = {
    codeGraphContextMode: '',
    promptImproverMode: '',
    hydraMode: ''
  };

  if (!value) return flags;

  const trimmed = String(value).trim();
  if (!trimmed) return flags;

  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed);
      return {
        codeGraphContextMode: parsed.codeGraphContextMode || '',
        promptImproverMode: parsed.promptImproverMode || '',
        hydraMode: parsed.hydraMode || ''
      };
    } catch {
      return flags;
    }
  }

  for (const pair of trimmed.split(',')) {
    const [key, raw] = pair.split('=').map((item) => item.trim());
    if (!key || !raw) continue;
    if (key === 'codeGraphContextMode' || key === 'promptImproverMode' || key === 'hydraMode') {
      flags[key] = raw;
    }
  }

  return flags;
}

function runPath(runId) {
  return path.join('.agent', 'runs', `${runId}.json`);
}

function readRun(runId) {
  const p = runPath(runId);
  if (!fs.existsSync(p)) {
    console.error(`Run artifact not found: ${p}`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function writeRun(runId, data) {
  const p = runPath(runId);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  data.updatedAt = nowIso();
  fs.writeFileSync(p, `${JSON.stringify(data, null, 2)}\n`);
  console.log(p);
}

function ensureFeedbackStructures(artifact) {
  if (!Array.isArray(artifact.events)) artifact.events = [];
  if (!Array.isArray(artifact.retries)) artifact.retries = [];
  if (!Array.isArray(artifact.failureSignatures)) artifact.failureSignatures = [];
  if (!artifact.feedbackLoops || typeof artifact.feedbackLoops !== 'object') {
    artifact.feedbackLoops = { internal: [], external: [] };
  }
  if (!Array.isArray(artifact.feedbackLoops.internal)) artifact.feedbackLoops.internal = [];
  if (!Array.isArray(artifact.feedbackLoops.external)) artifact.feedbackLoops.external = [];
}

function normalizePersonaRouting(resolution) {
  const compound = resolution.compoundPersona || null;
  return {
    routingConfidence: resolution.confidence || 'none',
    dispatchPlan: resolution.dispatchPlan || '',
    boardRequired: Boolean(resolution.boardRequired),
    highRiskTerms: Array.isArray(resolution.highRiskTerms) ? resolution.highRiskTerms : [],
    createPersonaSuggested: Boolean(resolution.createPersonaSuggested),
    promoteCompoundSuggested: Boolean(resolution.promoteCompoundSuggested),
    primaryPersonaId: resolution.primaryPersona?.id || '',
    collaboratorPersonaIds: Array.isArray(resolution.collaboratorPersonas)
      ? resolution.collaboratorPersonas.map((persona) => persona.id).filter(Boolean)
      : [],
    matchedPersonaIds: Array.isArray(resolution.matchedPersonas)
      ? resolution.matchedPersonas.map((persona) => persona.id).filter(Boolean)
      : [],
    compoundPersona: compound
      ? {
          id: compound.id || '',
          source: compound.source || '',
          riskTier: compound.riskTier || '',
          dispatchPlan: compound.dispatchPlan || '',
          primaryPersonaId: compound.primaryPersonaId || '',
          collaboratorPersonaIds: Array.isArray(compound.collaboratorPersonaIds)
            ? compound.collaboratorPersonaIds.filter(Boolean)
            : [],
          memberPersonaIds: Array.isArray(compound.memberPersonaIds) ? compound.memberPersonaIds.filter(Boolean) : [],
          memoryQuery: compound.memoryQuery || '',
          summary: compound.summary || '',
          reasons: Array.isArray(compound.reasons) ? compound.reasons : [],
          score: Number.isFinite(compound.score) ? compound.score : null,
          promoteSuggested: Boolean(compound.promoteSuggested),
          signature: compound.signature || ''
        }
      : null,
    recordedAt: nowIso()
  };
}

function updateRetrySummary(artifact, gateName, attempt) {
  const existing = artifact.retries.find((entry) => entry.gate === gateName);
  if (existing) {
    existing.attempts = Math.max(existing.attempts, attempt);
    return;
  }

  artifact.retries.push({
    gate: gateName,
    attempts: attempt
  });
}

function recordFailureSignature(artifact, payload) {
  ensureFeedbackStructures(artifact);

  const signature = payload.signature || `${payload.gate}|${payload.command}|${payload.exitCode}`;
  const timestamp = nowIso();
  const existing = artifact.failureSignatures.find((entry) => entry.signature === signature);

  if (existing) {
    existing.count += 1;
    existing.lastSeenAt = timestamp;
    existing.lastCommand = payload.command;
    existing.lastDetail = payload.detail;
    existing.lastExitCode = payload.exitCode;
    existing.failureCode = payload.failureCode;
    existing.failurePath = payload.failurePath;
  } else {
    artifact.failureSignatures.push({
      signature,
      gate: payload.gate,
      count: 1,
      firstSeenAt: timestamp,
      lastSeenAt: timestamp,
      lastCommand: payload.command,
      lastDetail: payload.detail,
      lastExitCode: payload.exitCode,
      failureCode: payload.failureCode,
      failurePath: payload.failurePath
    });
  }

  const current = existing || artifact.failureSignatures[artifact.failureSignatures.length - 1];
  if (current.count < 2) return;

  const alreadyTriggered = artifact.feedbackLoops.internal.some(
    (entry) => entry.kind === 'recurring-failure' && entry.signature === signature
  );
  if (alreadyTriggered) return;

  artifact.feedbackLoops.internal.push({
    kind: 'recurring-failure',
    status: 'triggered',
    gate: payload.gate,
    signature,
    summary: `Recurring failure signature detected for ${payload.gate}`,
    detail: payload.detail,
    target: payload.failurePath,
    trigger: 'same-signature-repeated-in-run',
    timestamp
  });
}

const [command, ...rest] = process.argv.slice(2);
if (!command) usage();
const args = parseArgs(rest);

if (command === 'init') {
  const runId = requireArg(args, 'id');
  const runtimeProfile = optionalArg(args, 'runtime', 'codex');
  const classification = optionalArg(args, 'classification', 'TASK');
  const taskSummary = optionalArg(args, 'summary', '');
  const contextSource = optionalArg(args, 'context-source', '');
  const integrationFlags = parseIntegrationFlags(optionalArg(args, 'integration-flags', ''));
  const promptVersion = optionalArg(args, 'prompt-version', '');
  const workflowVersion = optionalArg(args, 'workflow-version', '');
  const blueprintVersion = optionalArg(args, 'blueprint-version', '');
  const toolBundle = optionalArg(args, 'tool-bundle', '');
  const riskTier = optionalArg(args, 'risk-tier', '');
  const now = nowIso();

  const artifact = {
    schemaVersion: 1,
    runId,
    createdAt: now,
    updatedAt: now,
    status: 'in_progress',
    runtimeProfile,
    activeRuntime: runtimeProfile,
    classification,
    taskSummary,
    contextSource,
    integrationFlags,
    promptVersion,
    workflowVersion,
    blueprintVersion,
    toolBundle,
    riskTier,
    selectedSkills: [],
    mcpCalls: [],
    gates: [],
    events: [],
    failureSignatures: [],
    feedbackLoops: {
      internal: [],
      external: []
    },
    retries: [],
    delegationDecisions: [],
    delegationFailures: [],
    workerGraph: {
      workers: [],
      edges: []
    },
    messageBusHealth: {
      status: 'healthy',
      transport: 'json-local',
      pendingMessages: 0,
      lastCursor: 0
    },
    runtimeScorecards: [],
    personaRouting: null,
    rollback: null
  };

  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'context') {
  const runId = requireArg(args, 'id');
  const contextSource = optionalArg(args, 'context-source', '');
  const integrationFlags = parseIntegrationFlags(optionalArg(args, 'integration-flags', ''));

  const artifact = readRun(runId);
  if (contextSource) artifact.contextSource = contextSource;
  artifact.integrationFlags = {
    ...(artifact.integrationFlags || {
      codeGraphContextMode: '',
      promptImproverMode: '',
      hydraMode: ''
    }),
    ...integrationFlags
  };
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'gate') {
  const runId = requireArg(args, 'id');
  const name = optionalArg(args, 'name') || optionalArg(args, 'gate');
  if (!name) {
    console.error('Missing required argument --name (or --gate)');
    usage();
  }
  const gateCommand = optionalArg(args, 'command', optionalArg(args, 'detail', 'n/a'));
  const gateDetail = optionalArg(args, 'detail', '');
  const statusInput = optionalArg(args, 'status', '').toLowerCase();
  let exitCode = Number(optionalArg(args, 'exit-code', Number.NaN));
  let status = statusInput;
  if (!Number.isFinite(exitCode)) {
    if (statusInput === 'pass' || statusInput === 'success') exitCode = 0;
    else if (statusInput === 'fail' || statusInput === 'failed') exitCode = 1;
    else if (statusInput === 'skipped') exitCode = 0;
    else {
      console.error('Missing required argument --exit-code (or provide --status pass|fail|skipped)');
      usage();
    }
  }
  if (!status) status = exitCode === 0 ? 'pass' : 'fail';
  const attempt = Number(args.attempt || 1);
  const signature = optionalArg(args, 'signature', '');
  const failureCode = optionalArg(args, 'failure-code', '');
  const failurePath = optionalArg(args, 'failure-path', '');

  const artifact = readRun(runId);
  ensureFeedbackStructures(artifact);
  artifact.gates.push({
    name,
    status,
    command: gateCommand,
    exitCode,
    attempt,
    detail: gateDetail,
    signature,
    timestamp: nowIso()
  });
  updateRetrySummary(artifact, name, attempt);
  if (status === 'fail') {
    recordFailureSignature(artifact, {
      gate: name,
      command: gateCommand,
      detail: gateDetail,
      exitCode,
      signature: signature || [name, failureCode, failurePath].filter(Boolean).join('|'),
      failureCode,
      failurePath
    });
  }
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'mcp') {
  const runId = requireArg(args, 'id');
  const server = requireArg(args, 'server');
  const tool = requireArg(args, 'tool');
  const status = args.status || 'pass';
  const detail = args.detail || '';

  const artifact = readRun(runId);
  artifact.mcpCalls.push({
    server,
    tool,
    status,
    detail,
    timestamp: nowIso()
  });
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'complete') {
  const runId = requireArg(args, 'id');
  const status = optionalArg(args, 'status', 'success');
  const summary = optionalArg(args, 'summary', '');

  const artifact = readRun(runId);
  artifact.status = status;
  if (summary) artifact.summary = summary;
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'event') {
  const runId = requireArg(args, 'id');
  const eventType = requireArg(args, 'event-type');
  const summary = requireArg(args, 'summary');
  const status = optionalArg(args, 'status', 'info');
  const detail = optionalArg(args, 'detail', '');
  const target = optionalArg(args, 'target', '');

  const artifact = readRun(runId);
  ensureFeedbackStructures(artifact);
  artifact.events.push({
    eventType,
    summary,
    status,
    detail,
    target,
    timestamp: nowIso()
  });
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'feedback') {
  const runId = requireArg(args, 'id');
  const scope = requireArg(args, 'scope');
  const kind = requireArg(args, 'kind');
  const summary = requireArg(args, 'summary');
  const status = optionalArg(args, 'status', 'info');
  const detail = optionalArg(args, 'detail', '');
  const target = optionalArg(args, 'target', '');
  const trigger = optionalArg(args, 'trigger', '');
  const proposalPath = optionalArg(args, 'proposal-path', '');
  const signature = optionalArg(args, 'signature', '');
  const sourceRuns = optionalArg(args, 'source-runs', '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  if (!['internal', 'external'].includes(scope)) {
    console.error('Feedback scope must be internal or external.');
    process.exit(1);
  }

  const artifact = readRun(runId);
  ensureFeedbackStructures(artifact);
  artifact.feedbackLoops[scope].push({
    kind,
    status,
    summary,
    detail,
    target,
    trigger,
    proposalPath,
    signature,
    sourceRuns,
    timestamp: nowIso()
  });
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'persona') {
  const runId = requireArg(args, 'id');
  const resolutionFile = requireArg(args, 'resolution-file');
  const raw = fs.readFileSync(path.resolve(resolutionFile), 'utf8');
  const resolution = JSON.parse(raw);

  const artifact = readRun(runId);
  artifact.personaRouting = normalizePersonaRouting(resolution);
  writeRun(runId, artifact);
  process.exit(0);
}

usage();
