#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolvePrompt } from './persona-registry-lib.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..');
const DEFAULT_CORPUS_PATH = path.join(REPO_ROOT, 'evals', 'persona-routing-corpus.json');

function parseArgs(argv) {
  const args = { json: false, corpus: DEFAULT_CORPUS_PATH };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--json') args.json = true;
    else if (arg === '--corpus') args.corpus = path.resolve(argv[++i] ?? DEFAULT_CORPUS_PATH);
  }
  return args;
}

function readCorpus(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function includesAll(actualItems, expectedItems) {
  return expectedItems.filter((item) => !actualItems.includes(item));
}

function compareResult(result, expected) {
  const failures = [];
  const collaboratorIds = result.collaboratorPersonas.map((persona) => persona.id);
  const compound = result.compoundPersona;

  if (typeof expected.primaryPersonaId === 'string' && result.primaryPersona.id !== expected.primaryPersonaId) {
    failures.push(`primaryPersona.id expected ${expected.primaryPersonaId}, received ${result.primaryPersona.id}`);
  }

  if (typeof expected.dispatchPlan === 'string' && result.dispatchPlan !== expected.dispatchPlan) {
    failures.push(`dispatchPlan expected ${expected.dispatchPlan}, received ${result.dispatchPlan}`);
  }

  if (typeof expected.boardRequired === 'boolean' && result.boardRequired !== expected.boardRequired) {
    failures.push(`boardRequired expected ${expected.boardRequired}, received ${result.boardRequired}`);
  }

  if (typeof expected.compoundRequired === 'boolean') {
    if (expected.compoundRequired && !compound) failures.push('compoundPersona expected, received null');
    if (!expected.compoundRequired && compound) failures.push(`compoundPersona not expected, received ${compound.id}`);
  }

  if (typeof expected.compoundSource === 'string' && (compound?.source ?? null) !== expected.compoundSource) {
    failures.push(`compound source expected ${expected.compoundSource}, received ${compound?.source ?? 'null'}`);
  }

  if (typeof expected.compoundId === 'string' && (compound?.id ?? null) !== expected.compoundId) {
    failures.push(`compound id expected ${expected.compoundId}, received ${compound?.id ?? 'null'}`);
  }

  if (typeof expected.compoundIdPrefix === 'string' && !(compound?.id || '').startsWith(expected.compoundIdPrefix)) {
    failures.push(`compound id expected prefix ${expected.compoundIdPrefix}, received ${compound?.id ?? 'null'}`);
  }

  if (Array.isArray(expected.collaboratorIncludes) && expected.collaboratorIncludes.length > 0) {
    const missingCollaborators = includesAll(collaboratorIds, expected.collaboratorIncludes);
    if (missingCollaborators.length > 0) {
      failures.push(`missing collaborators: ${missingCollaborators.join(', ')}`);
    }
  }

  if (Array.isArray(expected.highRiskTermsIncludes) && expected.highRiskTermsIncludes.length > 0) {
    const missingRiskTerms = includesAll(result.highRiskTerms, expected.highRiskTermsIncludes);
    if (missingRiskTerms.length > 0) {
      failures.push(`missing high-risk terms: ${missingRiskTerms.join(', ')}`);
    }
  }

  return failures;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const corpus = readCorpus(args.corpus);
  if (!Array.isArray(corpus.cases) || corpus.cases.length === 0) {
    throw new Error(`Invalid benchmark corpus: ${args.corpus}`);
  }

  const results = corpus.cases.map((testCase) => {
    const result = resolvePrompt(testCase.prompt, { classification: testCase.classification });
    const failures = compareResult(result, testCase.expected || {});
    return {
      id: testCase.id,
      classification: testCase.classification,
      prompt: testCase.prompt,
      status: failures.length === 0 ? 'pass' : 'fail',
      failures,
      actual: {
        primaryPersonaId: result.primaryPersona.id,
        dispatchPlan: result.dispatchPlan,
        boardRequired: result.boardRequired,
        collaboratorIds: result.collaboratorPersonas.map((persona) => persona.id),
        highRiskTerms: result.highRiskTerms,
        compoundPersona: result.compoundPersona
          ? {
              id: result.compoundPersona.id,
              source: result.compoundPersona.source
            }
          : null
      }
    };
  });

  const failed = results.filter((entry) => entry.status === 'fail');
  const payload = {
    corpus: args.corpus,
    total: results.length,
    passed: results.length - failed.length,
    failed: failed.length,
    results
  };

  if (args.json) {
    console.log(JSON.stringify(payload, null, 2));
  } else {
    console.log(`Persona routing benchmark: ${payload.passed}/${payload.total} passed`);
    for (const entry of results) {
      console.log(`[${entry.status}] ${entry.id}`);
      for (const failure of entry.failures) {
        console.log(`  - ${failure}`);
      }
    }
  }

  process.exit(failed.length === 0 ? 0 : 1);
}

main();
